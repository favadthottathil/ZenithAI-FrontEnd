import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../domain/models/message.dart';
import '../../domain/repositories/chat_repository.dart';
import 'chat_state.dart';

export 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _repository;
  StreamSubscription? _subscription;

  // Platform speech service instance managed by BLoC
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechEnabled = false;

  // High-fidelity BLoC-level Typewriter streaming properties
  String _typewriterBuffer = "";
  bool _streamDone = false;
  Timer? _typewriterTimer;

  ChatBloc({required ChatRepository repository})
    : _repository = repository,
      super(const ChatInitial()) {
    on<ChatMessageSent>(_onMessageSent);
    on<_UpdateStreamingMessages>(_onUpdateStreamingMessages);
    on<_StreamingFinished>(_onStreamingFinished);
    on<_StreamingError>(_onStreamingError);

    // Pure BLoC-only UI handlers
    on<UpdateActiveModel>(_onUpdateActiveModel);
    on<ToggleSpeechListening>(_onToggleSpeechListening);
    on<SetSpeechListening>(_onSetSpeechListening);
    on<UpdateInputText>(_onUpdateInputText);
    on<ToggleMessageLike>(_onToggleMessageLike);
    on<ToggleMessageDislike>(_onToggleMessageDislike);
    on<ToggleMessageSpeaking>(_onToggleMessageSpeaking);

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
      ),
    );
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
    final convs = await _repository.getConversations();
    emit(_copyStateWith(conversations: convs));
  }

  void _onStreamingError(_StreamingError event, Emitter<ChatState> emit) {
    emit(
      ChatError(
        state.messages,
        event.error,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: state.inputText,
      ),
    );
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    // Reset typewriter variables
    _typewriterBuffer = "";
    _streamDone = false;
    _typewriterTimer?.cancel();

    String? currentConvId = state.conversationId;
    if (currentConvId == null || currentConvId.isEmpty) {
      try {
        final convo = await _repository.createConversation();
        currentConvId = convo["conversation_id"];
      } catch (e) {
        currentConvId = "temp_${DateTime.now().millisecondsSinceEpoch}";
      }
    }

    final userMessage = ChatMessage(
      text: event.text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(userMessage);

    // Clears the input field (inputText: "") automatically upon send
    emit(
      ChatLoading(
        updatedMessages,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: "",
        conversationId: currentConvId,
        conversations: state.conversations,
      ),
    );

    final assistantMessage = ChatMessage(
      text: "",
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    );

    final messagesWithAssistant = List<ChatMessage>.from(updatedMessages)
      ..add(assistantMessage);

    emit(
      ChatStreaming(
        messagesWithAssistant,
        activeModel: state.activeModel,
        isListening: state.isListening,
        inputText: "",
        conversationId: currentConvId,
        conversations: state.conversations,
      ),
    );

    try {
      await _subscription?.cancel();

      final completer = Completer<void>();

      _startTypewriterTimer();

      _subscription = _repository
          .getChatStream(updatedMessages, conversationId: currentConvId)
          .listen(
            (chunk) {
              _typewriterBuffer += chunk;
            },
            onError: (error) {
              _typewriterTimer?.cancel();
              add(_StreamingError(error.toString()));
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
          updatedMessages,
          e.toString(),
          activeModel: state.activeModel,
          isListening: state.isListening,
          inputText: "",
          conversationId: currentConvId,
          conversations: state.conversations,
        ),
      );
    }
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
        }
      } catch (e) {
        emit(_copyStateWith(isListening: false));
      }
    } else {
      await _speechToText.stop();
      emit(_copyStateWith(isListening: false));
    }
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

  void _onToggleMessageSpeaking(
    ToggleMessageSpeaking event,
    Emitter<ChatState> emit,
  ) {
    final msgs = List<ChatMessage>.from(state.messages);
    if (event.index >= 0 && event.index < msgs.length) {
      final msg = msgs[event.index];
      msgs[event.index] = msg.copyWith(isSpeaking: !msg.isSpeaking);
      emit(_copyStateWith(messages: msgs));
    }
  }

  Future<void> _onLoadConversations(
    LoadConversations event,
    Emitter<ChatState> emit,
  ) async {
    final convs = await _repository.getConversations();
    emit(_copyStateWith(conversations: convs));
  }

  Future<void> _onSelectConversation(
    SelectConversation event,
    Emitter<ChatState> emit,
  ) async {
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
        return ChatMessage(
          text: m["content"] ?? "",
          role: role,
          timestamp: DateTime.now(),
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
          e.toString(),
          activeModel: state.activeModel,
          isListening: state.isListening,
          inputText: state.inputText,
          conversationId: event.conversationId,
          conversations: state.conversations,
        ),
      );
    }
  }

  void _onCreateNewConversation(
    CreateNewConversation event,
    Emitter<ChatState> emit,
  ) {
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
    final success = await _repository.deleteConversation(event.conversationId);
    if (success) {
      final convs = await _repository.getConversations();
      final isCurrentDeleted = state.conversationId == event.conversationId;
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
    }
  }

  // Helper utility to copy state and preserve sub-classes
  ChatState _copyStateWith({
    List<ChatMessage>? messages,
    String? activeModel,
    bool? isListening,
    String? inputText,
    String? conversationId,
    List<Map<String, dynamic>>? conversations,
  }) {
    final msgs = messages ?? state.messages;
    final model = activeModel ?? state.activeModel;
    final listening = isListening ?? state.isListening;
    final text = inputText ?? state.inputText;
    final convId = conversationId ?? state.conversationId;
    final convs = conversations ?? state.conversations;

    if (state is ChatInitial) {
      return ChatInitial(
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
      );
    } else if (state is ChatLoading) {
      return ChatLoading(
        msgs,
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
      );
    } else if (state is ChatStreaming) {
      return ChatStreaming(
        msgs,
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
      );
    } else if (state is ChatSuccess) {
      return ChatSuccess(
        msgs,
        activeModel: model,
        isListening: listening,
        inputText: text,
        conversationId: convId,
        conversations: convs,
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
      );
    }
    return ChatSuccess(
      msgs,
      activeModel: model,
      isListening: listening,
      inputText: text,
      conversationId: convId,
      conversations: convs,
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    _typewriterTimer?.cancel();
    return super.close();
  }
}

// Private events for stream updates
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
