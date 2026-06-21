import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image/image.dart' as img;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/security/attachment_validator.dart';
import '../../domain/models/message.dart';
import '../../domain/models/attachment.dart';
import '../../domain/repositories/chat_repository.dart';
import 'chat_state.dart';

export 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  // Prefix the backend uses on the first SSE chunk of a new chat to send
  // back the newly-created conversation's real ID.
  static const String _conversationIdSentinel = " CONV_ID:";

  final ChatRepository _repository;
  StreamSubscription? _subscription;

  // Platform speech service instance managed by BLoC
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechEnabled = false;

  // Text-to-speech engine used to read assistant responses aloud through
  // the device's loudspeaker.
  final FlutterTts _flutterTts = FlutterTts();
  int? _speakingMessageIndex;
  final List<String> _speechQueue = [];

  // High-fidelity BLoC-level Typewriter streaming properties
  String _typewriterBuffer = "";
  bool _streamDone = false;
  Timer? _typewriterTimer;

  ChatBloc({required ChatRepository repository})
    : _repository = repository,
      super(const ChatInitial()) {
    on<ChatMessageSent>(_onMessageSent);
    on<_ConversationIdReceived>(_onConversationIdReceived);
    on<_UpdateStreamingMessages>(_onUpdateStreamingMessages);
    on<_StreamingFinished>(_onStreamingFinished);
    on<_StreamingError>(_onStreamingError);
    on<_SpeechError>(_onSpeechError);
    on<_TtsFinished>(_onTtsFinished);

    _flutterTts.setCompletionHandler(() => add(const _TtsFinished()));
    _flutterTts.setCancelHandler(() => add(const _TtsFinished()));
    _flutterTts.setErrorHandler((msg) => add(const _TtsFinished()));

    // Pure BLoC-only UI handlers
    on<UpdateActiveModel>(_onUpdateActiveModel);
    on<ToggleSpeechListening>(_onToggleSpeechListening);
    on<SetSpeechListening>(_onSetSpeechListening);
    on<UpdateInputText>(_onUpdateInputText);
    on<ToggleMessageLike>(_onToggleMessageLike);
    on<ToggleMessageDislike>(_onToggleMessageDislike);
    on<ToggleMessageSpeaking>(_onToggleMessageSpeaking);
    on<AttachmentPicked>(_onAttachmentPicked);
    on<AttachmentRemoved>(_onAttachmentRemoved);
    on<RegenerateResponse>(_onRegenerateResponse);

    // Database events
    on<LoadConversations>(_onLoadConversations);
    on<SelectConversation>(_onSelectConversation);
    on<CreateNewConversation>(_onCreateNewConversation);
    on<DeleteConversation>(_onDeleteConversation);

    // Load past conversations on startup
    add(const LoadConversations());
  }

  void _onUpdateStreamingMessages(
    _UpdateStreamingMessages event,
    Emitter<ChatState> emit,
  ) {
    emit(
      ChatStreaming(
        event.messages,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: state.inputText,
        conversationId: state.conversationId,
        conversations: state.conversations,
      ),
    );
  }

  // Surfaces the real conversation ID the backend generated for a new chat
  // (sent as the first SSE chunk) so subsequent messages and the
  // conversation history list reference the correct ID.
  void _onConversationIdReceived(
    _ConversationIdReceived event,
    Emitter<ChatState> emit,
  ) {
    emit(_copyStateWith(conversationId: event.conversationId));
  }

  Future<void> _onStreamingFinished(
    _StreamingFinished event,
    Emitter<ChatState> emit,
  ) async {
    emit(
      ChatSuccess(
        state.messages,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: state.inputText,
        conversationId: state.conversationId,
        conversations: state.conversations,
      ),
    );
    // Reload past conversations list so the new chat title is updated in history
    try {
      final convs = await _repository.getConversations();
      emit(_copyStateWith(conversations: convs));
    } catch (e) {
      // Keep the existing conversations list; the chat itself still succeeded.
    }
  }

  void _onStreamingError(_StreamingError event, Emitter<ChatState> emit) {
    emit(
      ChatError(
        state.messages,
        event.error,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: state.inputText,
        conversationId: state.conversationId,
        conversations: state.conversations,
      ),
    );
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    // Cancel any in-flight stream from a previous message before starting a new one
    await _cancelActiveStream();

    // If this is a new chat, conversationId is null/empty here. The backend
    // generates a real ID and sends it back as the first SSE event
    // (handled in the listen callback below via _ConversationIdReceived).
    final String? currentConvId = state.conversationId;

    final userMessage = ChatMessage(
      text: event.text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
      attachments: state.pendingAttachments,
    );

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(userMessage);

    // Clears the input field (inputText: "") and any pending attachments
    // automatically upon send
    emit(
      ChatLoading(
        updatedMessages,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: "",
        conversationId: currentConvId,
        conversations: state.conversations,
        pendingAttachments: const [],
      ),
    );

    await _streamAssistantResponse(updatedMessages, currentConvId, emit);
  }

  // Re-runs the most recent user prompt: drops the previous assistant reply
  // (and anything after the last user message) and streams a fresh response
  // from the same conversation history.
  Future<void> _onRegenerateResponse(
    RegenerateResponse event,
    Emitter<ChatState> emit,
  ) async {
    final lastUserIndex = state.messages.lastIndexWhere(
      (m) => m.role == MessageRole.user,
    );
    if (lastUserIndex == -1) return;

    await _cancelActiveStream();

    final String? currentConvId = state.conversationId;

    final history = state.messages.sublist(0, lastUserIndex + 1);

    emit(
      ChatLoading(
        history,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: state.inputText,
        conversationId: currentConvId,
        conversations: state.conversations,
        pendingAttachments: state.pendingAttachments,
      ),
    );

    await _streamAssistantResponse(history, currentConvId, emit);
  }

  // Appends a placeholder assistant message, opens the SSE stream for the
  // given history, and feeds incoming chunks into the typewriter buffer.
  // Shared by both first-time sends and regenerations.
  Future<void> _streamAssistantResponse(
    List<ChatMessage> history,
    String? convId,
    Emitter<ChatState> emit,
  ) async {
    final assistantMessage = ChatMessage(
      text: "",
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    );

    final messagesWithAssistant = List<ChatMessage>.from(history)
      ..add(assistantMessage);

    emit(
      ChatStreaming(
        messagesWithAssistant,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: state.inputText,
        conversationId: convId,
        conversations: state.conversations,
        pendingAttachments: state.pendingAttachments,
      ),
    );

    try {
      final completer = Completer<void>();

      _startTypewriterTimer();

      _subscription = _repository
          .getChatStream(history, conversationId: convId)
          .listen(
            (chunk) {
              // The backend sends the newly-created conversation's real ID
              // as a sentinel chunk for new chats; route it to state instead
              // of the typewriter buffer.
              if (chunk.startsWith(_conversationIdSentinel)) {
                add(
                  _ConversationIdReceived(
                    chunk.substring(_conversationIdSentinel.length),
                  ),
                );
                return;
              }
              _typewriterBuffer += chunk;
            },
            onError: (error) {
              _typewriterTimer?.cancel();
              add(_StreamingError(_friendlyError(error)));
              if (!completer.isCompleted) completer.complete();
            },
            onDone: () {
              _streamDone = true;
              if (!completer.isCompleted) completer.complete();
            },
          );

      await completer.future;
    } catch (e) {
      _typewriterTimer?.cancel();
      emit(
        ChatError(
          history,
          _friendlyError(e),
          activeModel: state.activeModel,
          isListening: state.isListening,
          inputText: state.inputText,
          conversationId: convId,
          conversations: state.conversations,
          pendingAttachments: state.pendingAttachments,
        ),
      );
    }
  }

  // Repository exceptions are plain `Exception(message)`s; strip the
  // "Exception: " prefix Dart's default toString() adds so the message shown
  // to the user reads naturally in the error snackbar.
  String _friendlyError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  // Stops the active SSE subscription and typewriter timer, closing the
  // underlying HTTP connection so an abandoned response stops generating.
  Future<void> _cancelActiveStream() async {
    _typewriterTimer?.cancel();
    _typewriterTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _typewriterBuffer = "";
    _streamDone = false;
    await _flutterTts.stop();
    _speechQueue.clear();
    _speakingMessageIndex = null;
  }

  void _startTypewriterTimer() {
    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 12), (
      timer,
    ) {
      if (_typewriterBuffer.isNotEmpty) {
        // Character-by-character (one by one) typing animation.
        // Consume a dynamic number of characters based on buffer size to prevent lagging.
        int charsToTake = 1;
        final bufferLen = _typewriterBuffer.length;
        if (bufferLen > 400) {
          charsToTake = 12;
        } else if (bufferLen > 250) {
          charsToTake = 8;
        } else if (bufferLen > 120) {
          charsToTake = 5;
        } else if (bufferLen > 50) {
          charsToTake = 3;
        } else if (bufferLen > 15) {
          charsToTake = 2;
        }

        String consumed = _typewriterBuffer.substring(0, charsToTake);
        _typewriterBuffer = _typewriterBuffer.substring(charsToTake);

        final currentMessages = List<ChatMessage>.from(state.messages);
        if (currentMessages.isNotEmpty &&
            currentMessages.last.role == MessageRole.assistant) {
          final lastMsg = currentMessages.last;
          final updatedLastMsg = lastMsg.copyWith(
            text: lastMsg.text + consumed,
          );
          currentMessages[currentMessages.length - 1] = updatedLastMsg;
          add(_UpdateStreamingMessages(currentMessages));
        }
      } else if (_streamDone) {
        timer.cancel();
        add(_StreamingFinished());
      }
    });
  }

  // Pure UI handler implementations
  void _onUpdateActiveModel(UpdateActiveModel event, Emitter<ChatState> emit) {
    emit(_copyStateWith(activeModel: event.model));
  }

  void _onUpdateInputText(UpdateInputText event, Emitter<ChatState> emit) {
    emit(_copyStateWith(inputText: event.text));
  }

  void _onSetSpeechListening(
    SetSpeechListening event,
    Emitter<ChatState> emit,
  ) {
    emit(_copyStateWith(isListening: event.isListening));
  }

  Future<void> _onToggleSpeechListening(
    ToggleSpeechListening event,
    Emitter<ChatState> emit,
  ) async {
    if (!state.isListening) {
      try {
        if (!_speechEnabled) {
          _speechEnabled = await _speechToText.initialize(
            onError: (val) {
              add(_SpeechError(val.errorMsg));
              add(const SetSpeechListening(false));
            },
            onStatus: (val) {
              if (val == 'done' || val == 'notListening') {
                add(const SetSpeechListening(false));
              }
            },
          );
        }

        if (_speechEnabled) {
          emit(_copyStateWith(isListening: true, inputText: "Listening..."));

          await _speechToText.listen(
            onResult: (result) {
              add(UpdateInputText(result.recognizedWords));
            },
          );
        } else {
          emit(
            _copyStateWith(
              isListening: false,
              infoMessage:
                  "Microphone access is unavailable. Please grant microphone permission to use voice input.",
            ),
          );
        }
      } catch (e) {
        emit(
          _copyStateWith(
            isListening: false,
            infoMessage: "Could not start voice input: $e",
          ),
        );
      }
    } else {
      await _speechToText.stop();
      emit(_copyStateWith(isListening: false));
    }
  }

  void _onSpeechError(_SpeechError event, Emitter<ChatState> emit) {
    emit(_copyStateWith(isListening: false, infoMessage: event.message));
  }

  void _onToggleMessageLike(ToggleMessageLike event, Emitter<ChatState> emit) {
    final msgs = List<ChatMessage>.from(state.messages);
    if (event.index >= 0 && event.index < msgs.length) {
      final msg = msgs[event.index];
      msgs[event.index] = msg.copyWith(
        isLiked: !msg.isLiked,
        isDisliked: false, // Mutually exclusive
      );
      emit(_copyStateWith(messages: msgs));
    }
  }

  void _onToggleMessageDislike(
    ToggleMessageDislike event,
    Emitter<ChatState> emit,
  ) {
    final msgs = List<ChatMessage>.from(state.messages);
    if (event.index >= 0 && event.index < msgs.length) {
      final msg = msgs[event.index];
      msgs[event.index] = msg.copyWith(
        isDisliked: !msg.isDisliked,
        isLiked: false, // Mutually exclusive
      );
      emit(_copyStateWith(messages: msgs));
    }
  }

  Future<void> _onToggleMessageSpeaking(
    ToggleMessageSpeaking event,
    Emitter<ChatState> emit,
  ) async {
    if (event.index < 0 || event.index >= state.messages.length) return;

    final msgs = List<ChatMessage>.from(state.messages);
    final msg = msgs[event.index];
    final wasSpeaking = msg.isSpeaking;

    // Stop whatever is currently playing (if anything) before reacting.
    await _flutterTts.stop();
    _speechQueue.clear();
    if (_speakingMessageIndex != null &&
        _speakingMessageIndex! < msgs.length) {
      msgs[_speakingMessageIndex!] = msgs[_speakingMessageIndex!].copyWith(
        isSpeaking: false,
      );
    }
    _speakingMessageIndex = null;

    if (!wasSpeaking) {
      msgs[event.index] = msg.copyWith(isSpeaking: true);
      _speakingMessageIndex = event.index;
      emit(_copyStateWith(messages: msgs));

      _speechQueue.addAll(_chunkForSpeech(_stripMarkdownForSpeech(msg.text)));
      await _speakNextChunk();
    } else {
      emit(_copyStateWith(messages: msgs));
    }
  }

  // Speaks the next queued chunk, if any. The Android TTS engine silently
  // rejects inputs over ~4000 characters, so long responses are split into
  // smaller chunks and fed one at a time via the completion handler.
  Future<void> _speakNextChunk() async {
    if (_speechQueue.isEmpty) return;
    final chunk = _speechQueue.removeAt(0);
    await _flutterTts.speak(chunk);
  }

  // Clears the speaking indicator once playback finishes, is cancelled, or
  // errors out, so the volume icon reverts on its own without user input.
  void _onTtsFinished(_TtsFinished event, Emitter<ChatState> emit) {
    if (_speakingMessageIndex == null) return;

    if (_speechQueue.isNotEmpty) {
      _speakNextChunk();
      return;
    }

    final index = _speakingMessageIndex!;
    _speakingMessageIndex = null;
    if (index < 0 || index >= state.messages.length) return;

    final msgs = List<ChatMessage>.from(state.messages);
    msgs[index] = msgs[index].copyWith(isSpeaking: false);
    emit(_copyStateWith(messages: msgs));
  }

  // Splits text into TTS-safe chunks (well under the ~4000 char engine
  // limit), breaking on paragraph/sentence/word boundaries where possible
  // so words aren't cut mid-syllable.
  static const int _maxSpeechChunkLength = 3000;

  List<String> _chunkForSpeech(String text) {
    if (text.isEmpty) return const [];
    if (text.length <= _maxSpeechChunkLength) return [text];

    final chunks = <String>[];
    var remaining = text;
    while (remaining.length > _maxSpeechChunkLength) {
      var splitAt = remaining.lastIndexOf(
        RegExp(r'[\n.!?]\s'),
        _maxSpeechChunkLength,
      );
      if (splitAt <= 0) {
        splitAt = remaining.lastIndexOf(' ', _maxSpeechChunkLength);
      }
      if (splitAt <= 0) {
        splitAt = _maxSpeechChunkLength;
      } else {
        splitAt += 1; // include the punctuation/space in the first chunk
      }

      chunks.add(remaining.substring(0, splitAt).trim());
      remaining = remaining.substring(splitAt).trim();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  // Removes Markdown syntax (headings, bold/italic markers, horizontal
  // rules, code fences, links, etc.) so the TTS engine reads plain words
  // and titles instead of literal symbols like "##", "**" or "---".
  //
  // Note: String.replaceAll(RegExp, "$1") does NOT perform backreference
  // substitution in Dart -- it inserts the literal text "$1". Capture-group
  // replacements must use replaceAllMapped.
  String _stripMarkdownForSpeech(String text) {
    var result = text
        // Fenced code blocks
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        // Inline code
        .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '')
        // Images
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
        // Links -> link text only
        .replaceAllMapped(
          RegExp(r'\[([^\]]*)\]\([^)]*\)'),
          (m) => m.group(1) ?? '',
        )
        // Horizontal rules (---, ***, ___) on their own line
        .replaceAll(
          RegExp(r'^[ \t]*([-*_])\1{2,}[ \t]*$', multiLine: true),
          '',
        )
        // Headings: drop the leading #'s, keep the title text
        .replaceAll(RegExp(r'^[ \t]{0,3}#{1,6}[ \t]*', multiLine: true), '')
        // Bold
        .replaceAllMapped(
          RegExp(r'(\*\*|__)(.+?)\1'),
          (m) => m.group(2) ?? '',
        )
        // List bullets (must run before italic, which also uses single '*')
        .replaceAll(RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true), '')
        // Blockquotes
        .replaceAll(RegExp(r'^[ \t]*>[ \t]*', multiLine: true), '')
        // Italic
        .replaceAllMapped(
          RegExp(r'(?<!\*)\*([^*\n]+?)\*(?!\*)'),
          (m) => m.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'(?<!_)_([^_\n]+?)_(?!_)'),
          (m) => m.group(1) ?? '',
        );

    // Collapse blank lines left behind by removed rules/headings.
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result.trim();
  }

  static const int _maxAttachments = 4;
  // Backend caps the base64-encoded `data` field at 10,000,000 characters,
  // which corresponds to ~7.5MB of raw bytes (base64 inflates by 4/3). Stay
  // comfortably under that so encoding never pushes a file over the limit.
  static const int _maxAttachmentBytes = 7 * 1024 * 1024;
  static const int _maxImageDimension = 1280;
  static const int _maxFilenameLength = 255;

  void _onAttachmentPicked(AttachmentPicked event, Emitter<ChatState> emit) {
    if (state.pendingAttachments.length >= _maxAttachments) {
      emit(
        _copyStateWith(
          infoMessage: "You can attach up to $_maxAttachments files at a time.",
        ),
      );
      return;
    }

    var attachment = event.attachment;

    // Backend caps filenames at 255 characters and rejects longer ones (422).
    if (attachment.filename.length > _maxFilenameLength) {
      attachment = MessageAttachment(
        type: attachment.type,
        filename: attachment.filename.substring(0, _maxFilenameLength),
        mimeType: attachment.mimeType,
        bytes: attachment.bytes,
      );
    }

    if (attachment.type == AttachmentType.document) {
      if (attachment.bytes.length > _maxAttachmentBytes) {
        emit(_copyStateWith(infoMessage: "File too large (max 7MB)."));
        return;
      }
      // Backend only accepts a fixed set of MIME types for attachments.
      if (!AttachmentValidator.isAllowedMimeType(attachment.mimeType)) {
        emit(_copyStateWith(infoMessage: "That file type isn't supported."));
        return;
      }
      // Verify the bytes actually match the claimed document type — file
      // extensions/MIME are spoofable.
      final reason = AttachmentValidator.documentRejectionReason(
        attachment.mimeType,
        attachment.bytes,
      );
      if (reason != null) {
        emit(_copyStateWith(infoMessage: reason));
        return;
      }
    }

    if (attachment.type == AttachmentType.image) {
      // _resizeImageAttachment decodes the bytes; a decode failure means the
      // data isn't a real image, so reject it rather than sending unknown
      // bytes labeled as an image.
      final resized = _tryResizeImageAttachment(attachment);
      if (resized == null) {
        emit(
          _copyStateWith(infoMessage: "That image couldn't be read."),
        );
        return;
      }
      if (resized.bytes.length > _maxAttachmentBytes) {
        emit(_copyStateWith(infoMessage: "That image is too large to send."));
        return;
      }
      attachment = resized;
    }

    emit(
      _copyStateWith(
        pendingAttachments: List<MessageAttachment>.from(
          state.pendingAttachments,
        )..add(attachment),
      ),
    );
  }

  void _onAttachmentRemoved(AttachmentRemoved event, Emitter<ChatState> emit) {
    final attachments = List<MessageAttachment>.from(state.pendingAttachments);
    if (event.index >= 0 && event.index < attachments.length) {
      attachments.removeAt(event.index);
      emit(_copyStateWith(pendingAttachments: attachments));
    }
  }

  // Downscales the image so its longest side is at most _maxImageDimension
  // and re-encodes it as JPEG to keep the Gemini request payload small.
  // Returns null when the bytes can't be decoded as an image (validation
  // failure) or when re-encoding throws.
  MessageAttachment? _tryResizeImageAttachment(MessageAttachment attachment) {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(attachment.bytes);
    } catch (_) {
      return null;
    }
    if (decoded == null) return null;

    img.Image resized = decoded;
    if (decoded.width > _maxImageDimension ||
        decoded.height > _maxImageDimension) {
      resized = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: _maxImageDimension)
          : img.copyResize(decoded, height: _maxImageDimension);
    }

    final encoded = img.encodeJpg(resized, quality: 80);

    return MessageAttachment(
      type: AttachmentType.image,
      filename: attachment.filename,
      mimeType: "image/jpeg",
      bytes: Uint8List.fromList(encoded),
    );
  }

  Future<void> _onLoadConversations(
    LoadConversations event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final convs = await _repository.getConversations();
      emit(_copyStateWith(conversations: convs));
    } catch (e) {
      emit(
        _copyStateWith(
          infoMessage:
              "Couldn't load conversation history. Check your connection.",
        ),
      );
    }
  }

  Future<void> _onSelectConversation(
    SelectConversation event,
    Emitter<ChatState> emit,
  ) async {
    await _cancelActiveStream();

    emit(
      ChatLoading(
        const [],
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: state.inputText,
        conversationId: event.conversationId,
        conversations: state.conversations,
      ),
    );

    try {
      final convo = await _repository.getConversation(event.conversationId);
      final rawMsgs = convo["messages"] as List<dynamic>? ?? [];
      final messages = rawMsgs.map((m) {
        final role = m["role"] == "user"
            ? MessageRole.user
            : MessageRole.assistant;

        final rawAttachments = m["attachments"] as List<dynamic>? ?? [];
        final attachments = rawAttachments.map((a) {
          final type = a["type"] == "image"
              ? AttachmentType.image
              : AttachmentType.document;
          final bytes = base64Decode(a["data"] as String? ?? '');
          return MessageAttachment(
            type: type,
            filename: a["filename"] ?? '',
            mimeType: a["mime_type"] ?? '',
            bytes: bytes,
          );
        }).toList();

        return ChatMessage(
          text: m["content"] ?? "",
          role: role,
          timestamp: DateTime.now(),
          attachments: attachments,
        );
      }).toList();

      emit(
        ChatSuccess(
          messages,
          activeModel: state.activeModel,
          isListening: state.isListening,
          inputText: "",
          conversationId: event.conversationId,
          conversations: state.conversations,
        ),
      );
    } catch (e) {
      emit(
        ChatError(
          const [],
          "Couldn't load this conversation. Check your connection.",
          activeModel: state.activeModel,
          isListening: state.isListening,
          inputText: state.inputText,
          conversationId: event.conversationId,
          conversations: state.conversations,
        ),
      );
    }
  }

  Future<void> _onCreateNewConversation(
    CreateNewConversation event,
    Emitter<ChatState> emit,
  ) async {
    await _cancelActiveStream();

    emit(
      ChatInitial(
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: "",
        conversationId: null,
        conversations: state.conversations,
      ),
    );
  }

  Future<void> _onDeleteConversation(
    DeleteConversation event,
    Emitter<ChatState> emit,
  ) async {
    final isCurrentDeleted = state.conversationId == event.conversationId;
    if (isCurrentDeleted) {
      await _cancelActiveStream();
    }

    try {
      final success = await _repository.deleteConversation(
        event.conversationId,
      );
      if (!success) {
        emit(
          _copyStateWith(
            infoMessage: "Couldn't delete conversation. Please try again.",
          ),
        );
        return;
      }

      final convs = await _repository.getConversations();
      if (isCurrentDeleted) {
        emit(
          ChatInitial(
            activeModel: state.activeModel,
            isListening: state.isListening,
            inputText: "",
            conversationId: null,
            conversations: convs,
          ),
        );
      } else {
        emit(_copyStateWith(conversations: convs));
      }
    } catch (e) {
      emit(
        _copyStateWith(
          infoMessage: "Couldn't delete conversation. Please try again.",
        ),
      );
    }
  }

  // Helper utility to copy state and preserve sub-classes
  // infoMessage is a transient one-shot notification: any call to
  // _copyStateWith clears it unless explicitly provided, so it surfaces
  // exactly once via the SnackBar listener in ChatScreen.
  ChatState _copyStateWith({
    List<ChatMessage>? messages,
    String? activeModel,
    bool? isListening,
    String? inputText,
    String? conversationId,
    List<Map<String, dynamic>>? conversations,
    String? infoMessage,
    List<MessageAttachment>? pendingAttachments,
  }) {
    final msgs = messages ?? state.messages;
    final model = activeModel ?? state.activeModel;
    final listening = isListening ?? state.isListening;
    final text = inputText ?? state.inputText;
    final convId = conversationId ?? state.conversationId;
    final convs = conversations ?? state.conversations;
    final attachments = pendingAttachments ?? state.pendingAttachments;

    if (state is ChatInitial) {
      return ChatInitial(
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
        infoMessage: infoMessage,
        pendingAttachments: attachments,
      );
    } else if (state is ChatLoading) {
      return ChatLoading(
        msgs,
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
        infoMessage: infoMessage,
        pendingAttachments: attachments,
      );
    } else if (state is ChatStreaming) {
      return ChatStreaming(
        msgs,
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
        infoMessage: infoMessage,
        pendingAttachments: attachments,
      );
    } else if (state is ChatSuccess) {
      return ChatSuccess(
        msgs,
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
        infoMessage: infoMessage,
        pendingAttachments: attachments,
      );
    } else if (state is ChatError) {
      return ChatError(
        msgs,
        (state as ChatError).error,
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
        infoMessage: infoMessage,
        pendingAttachments: attachments,
      );
    }
    return ChatSuccess(
      msgs,
      activeModel: model,
      isListening: listening,
      inputText: text,
      conversationId: convId,
      conversations: convs,
      infoMessage: infoMessage,
      pendingAttachments: attachments,
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    _typewriterTimer?.cancel();
    _flutterTts.stop();
    return super.close();
  }
}

// Private events for stream updates
class _ConversationIdReceived extends ChatEvent {
  final String conversationId;
  const _ConversationIdReceived(this.conversationId);
  @override
  List<Object?> get props => [conversationId];
}

class _UpdateStreamingMessages extends ChatEvent {
  final List<ChatMessage> messages;
  const _UpdateStreamingMessages(this.messages);
  @override
  List<Object?> get props => [messages];
}

class _StreamingFinished extends ChatEvent {}

class _StreamingError extends ChatEvent {
  final String error;
  const _StreamingError(this.error);
  @override
  List<Object?> get props => [error];
}

class _SpeechError extends ChatEvent {
  final String message;
  const _SpeechError(this.message);
  @override
  List<Object?> get props => [message];
}

class _TtsFinished extends ChatEvent {
  const _TtsFinished();
}
