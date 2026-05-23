import '../models/message.dart';

abstract class ChatRepository {
  Stream<String> getChatStream(List<ChatMessage> messages);
}
