enum MessageRole { user, assistant }

class ChatMessage {
  final String text;
  final MessageRole role;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.role,
    required this.timestamp,
  });

  ChatMessage copyWith({
    String? text,
    MessageRole? role,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
