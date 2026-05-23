import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/models/message.dart';
import '../../domain/repositories/chat_repository.dart';
import 'chat_state.dart';

export 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _repository;
  StreamSubscription? _subscription;

  ChatBloc({required ChatRepository repository})
    : _repository = repository,
      super(const ChatInitial()) {
    on<ChatMessageSent>(_onMessageSent);
    on<_UpdateStreamingMessages>(_onUpdateStreamingMessages);
    on<_StreamingFinished>(_onStreamingFinished);
    on<_StreamingError>(_onStreamingError);
  }

  void _onUpdateStreamingMessages(
    _UpdateStreamingMessages event,
    Emitter<ChatState> emit,
  ) {
    emit(ChatStreaming(event.messages));
  }

  void _onStreamingFinished(_StreamingFinished event, Emitter<ChatState> emit) {
    emit(ChatSuccess(state.messages));
  }

  void _onStreamingError(_StreamingError event, Emitter<ChatState> emit) {
    emit(ChatError(state.messages, event.error));
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    print("BLOC: _onMessageSent triggered with '${event.text}'"); // DEBUG PRINT
    final userMessage = ChatMessage(
      text: event.text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(userMessage);

    emit(ChatLoading(updatedMessages));

    final assistantMessage = ChatMessage(
      text: "",
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    );

    final messagesWithAssistant = List<ChatMessage>.from(updatedMessages)
      ..add(assistantMessage);
    emit(ChatStreaming(messagesWithAssistant));

    try {
      await _subscription?.cancel();

      final completer = Completer<void>();

      _subscription = _repository
          .getChatStream(updatedMessages)
          .listen(
            (chunk) {
              print("BLOC RECEIVED CHUNK: $chunk"); // DEBUG PRINT
              final lastMsg = messagesWithAssistant.last;
              final updatedLastMsg = lastMsg.copyWith(
                text: lastMsg.text + chunk,
              );
              messagesWithAssistant[messagesWithAssistant.length - 1] =
                  updatedLastMsg;

              add(
                _UpdateStreamingMessages(
                  List<ChatMessage>.from(messagesWithAssistant),
                ),
              );
            },
            onError: (error) {
              print("BLOC STREAM ERROR: $error"); // DEBUG PRINT
              add(_StreamingError(error.toString()));
              if (!completer.isCompleted) completer.complete();
            },
            onDone: () {
              print("BLOC STREAM DONE"); // DEBUG PRINT
              add(_StreamingFinished());
              if (!completer.isCompleted) completer.complete();
            },
          );

      await completer.future;
    } catch (e) {
      emit(ChatError(updatedMessages, e.toString()));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}

// Private events for stream updates
class _UpdateStreamingMessages extends ChatEvent {
  final List<ChatMessage> messages;
  const _UpdateStreamingMessages(this.messages);
  @override
  List<Object> get props => [messages];
}

class _StreamingFinished extends ChatEvent {}

class _StreamingError extends ChatEvent {
  final String error;
  const _StreamingError(this.error);
  @override
  List<Object> get props => [error];
}
