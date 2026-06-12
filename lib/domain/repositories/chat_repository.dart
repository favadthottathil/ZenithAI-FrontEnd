import '../models/message.dart';

abstract class ChatRepository {
  Stream<String> getChatStream(List<ChatMessage> messages, {String? conversationId});
  Future<List<Map<String, dynamic>>> getConversations();
  Future<Map<String, dynamic>> getConversation(String conversationId);
  Future<Map<String, dynamic>> createConversation();
  Future<bool> deleteConversation(String conversationId);
}
