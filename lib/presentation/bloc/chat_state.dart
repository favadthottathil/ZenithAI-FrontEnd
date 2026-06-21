import 'package:equatable/equatable.dart';
import '../../domain/models/message.dart';
import '../../domain/models/attachment.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class ChatMessageSent extends ChatEvent {
  final String text;
  const ChatMessageSent(this.text);

  @override
  List<Object?> get props => [text];
}

// Zero-setState BLoC events for UI actions
class UpdateActiveModel extends ChatEvent {
  final String model;
  const UpdateActiveModel(this.model);

  @override
  List<Object?> get props => [model];
}

class ToggleSpeechListening extends ChatEvent {
  const ToggleSpeechListening();
}

class SetSpeechListening extends ChatEvent {
  final bool isListening;
  const SetSpeechListening(this.isListening);

  @override
  List<Object?> get props => [isListening];
}

class UpdateInputText extends ChatEvent {
  final String text;
  const UpdateInputText(this.text);

  @override
  List<Object?> get props => [text];
}

class ToggleMessageLike extends ChatEvent {
  final int index;
  const ToggleMessageLike(this.index);

  @override
  List<Object?> get props => [index];
}

class ToggleMessageDislike extends ChatEvent {
  final int index;
  const ToggleMessageDislike(this.index);

  @override
  List<Object?> get props => [index];
}

class ToggleMessageSpeaking extends ChatEvent {
  final int index;
  const ToggleMessageSpeaking(this.index);

  @override
  List<Object?> get props => [index];
}

class AttachmentPicked extends ChatEvent {
  final MessageAttachment attachment;
  const AttachmentPicked(this.attachment);

  @override
  List<Object?> get props => [attachment];
}

class AttachmentRemoved extends ChatEvent {
  final int index;
  const AttachmentRemoved(this.index);

  @override
  List<Object?> get props => [index];
}

// Re-sends the most recent user prompt to the backend and streams a fresh
// assistant response in place of the previous one.
class RegenerateResponse extends ChatEvent {
  const RegenerateResponse();
}


// Redesigned ChatState to hold all state variables
abstract class ChatState extends Equatable {
  final List<ChatMessage> messages;
  final String activeModel;
  final bool isListening;
  final String inputText;
  final String? conversationId;
  final List<Map<String, dynamic>> conversations;
  final String? infoMessage;
  final List<MessageAttachment> pendingAttachments;

  const ChatState(
    this.messages, {
    this.activeModel = "ChatGPT 4o",
    this.isListening = false,
    this.inputText = "",
    this.conversationId,
    this.conversations = const [],
    this.infoMessage,
    this.pendingAttachments = const [],
  });

  @override
  List<Object?> get props => [
        messages,
        activeModel,
        isListening,
        inputText,
        conversationId,
        conversations,
        infoMessage,
        pendingAttachments,
      ];
}

class ChatInitial extends ChatState {
  const ChatInitial({
    super.activeModel,
    super.isListening,
    super.inputText,
    super.conversationId,
    super.conversations,
    super.infoMessage,
    super.pendingAttachments,
  }) : super(const []);
}

class ChatLoading extends ChatState {
  const ChatLoading(
    super.messages, {
    super.activeModel,
    super.isListening,
    super.inputText,
    super.conversationId,
    super.conversations,
    super.infoMessage,
    super.pendingAttachments,
  });
}

class ChatStreaming extends ChatState {
  const ChatStreaming(
    super.messages, {
    super.activeModel,
    super.isListening,
    super.inputText,
    super.conversationId,
    super.conversations,
    super.infoMessage,
    super.pendingAttachments,
  });
}

class ChatSuccess extends ChatState {
  const ChatSuccess(
    super.messages, {
    super.activeModel,
    super.isListening,
    super.inputText,
    super.conversationId,
    super.conversations,
    super.infoMessage,
    super.pendingAttachments,
  });
}

class ChatError extends ChatState {
  final String error;
  const ChatError(
    super.messages,
    this.error, {
    super.activeModel,
    super.isListening,
    super.inputText,
    super.conversationId,
    super.conversations,
    super.infoMessage,
    super.pendingAttachments,
  });

  @override
  List<Object?> get props => [
        messages,
        activeModel,
        isListening,
        inputText,
        conversationId,
        conversations,
        infoMessage,
        pendingAttachments,
        error,
      ];
}

// BLoC Database events
class LoadConversations extends ChatEvent {
  const LoadConversations();
}

class SelectConversation extends ChatEvent {
  final String conversationId;
  const SelectConversation(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

class CreateNewConversation extends ChatEvent {
  const CreateNewConversation();
}

class DeleteConversation extends ChatEvent {
  final String conversationId;
  const DeleteConversation(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}
