import 'package:equatable/equatable.dart';
import '../../domain/models/message.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object> get props => [];
}

class ChatMessageSent extends ChatEvent {
  final String text;
  const ChatMessageSent(this.text);

  @override
  List<Object> get props => [text];
}

abstract class ChatState extends Equatable {
  final List<ChatMessage> messages;
  const ChatState(this.messages);

  @override
  List<Object> get props => [messages];
}

class ChatInitial extends ChatState {
  const ChatInitial() : super(const []);
}

class ChatLoading extends ChatState {
  const ChatLoading(super.messages);
}

class ChatStreaming extends ChatState {
  const ChatStreaming(super.messages);
}

class ChatSuccess extends ChatState {
  const ChatSuccess(super.messages);
}

class ChatError extends ChatState {
  final String error;
  const ChatError(super.messages, this.error);

  @override
  List<Object> get props => [messages, error];
}
