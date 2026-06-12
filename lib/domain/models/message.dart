enum MessageRole { user, assistant }

class ChatMessage {
  final String text;
  final MessageRole role;
  final DateTime timestamp;
  final bool isLiked;
  final bool isDisliked;
  final bool isSpeaking;

  ChatMessage({
    required this.text,
    required this.role,
    required this.timestamp,
    this.isLiked = false,
    this.isDisliked = false,
    this.isSpeaking = false,
  });

  ChatMessage copyWith({
    String? text,
    MessageRole? role,
    DateTime? timestamp,
    bool? isLiked,
    bool? isDisliked,
    bool? isSpeaking,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      isLiked: isLiked ?? this.isLiked,
      isDisliked: isDisliked ?? this.isDisliked,
      isSpeaking: isSpeaking ?? this.isSpeaking,
    );
  }
}
