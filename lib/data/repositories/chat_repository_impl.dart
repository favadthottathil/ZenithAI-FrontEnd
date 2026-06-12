import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/message.dart';
import '../../domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  // For Android Emulator use 10.0.2.2, for Windows/Web use 127.0.0.1
  // For physical Android device debugging, use your host machine's IP address
  final String baseUrl = "https://llm-backend-08lr.onrender.com";

  @override
  Stream<String> getChatStream(
    List<ChatMessage> messages, {
    String? conversationId,
  }) async* {
    final url = Uri.parse("$baseUrl/chat-stream");

    final request = http.Request("POST", url);
    request.headers["Content-Type"] = "application/json";
    request.headers["Accept"] = "text/event-stream";
    request.headers["Cache-Control"] = "no-cache";

    // Convert domain message models to json format expected by backend
    final formattedMessages = messages
        .map((m) => {"role": m.role.name, "content": m.text})
        .toList();

    final Map<String, dynamic> bodyMap = {"messages": formattedMessages};
    if (conversationId != null && conversationId.isNotEmpty) {
      bodyMap["conversation_id"] = conversationId;
    }

    request.body = jsonEncode(bodyMap);

    http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception(
        "Connection failed. Ensure backend is running at $baseUrl. Error: $e",
      );
    }


    if (response.statusCode != 200) {
      throw Exception(
        "Failed to connect to chat stream: ${response.statusCode}",
      );
    }

    // Process the stream event by event (\n\n delimited)
    String buffer = "";
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final index = buffer.indexOf("\n\n");
        if (index == -1) break;

        final event = buffer.substring(0, index);
        buffer = buffer.substring(index + 2);

        if (event.startsWith("data:")) {
          String data;
          if (event.startsWith("data: ")) {
            data = event.substring(6);
          } else {
            data = event.substring(5);
          }
          yield data;
        }
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getConversations() async {
    final url = Uri.parse("$baseUrl/conversations");
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data["conversations"] ?? []);
      }
    } catch (e) {
      //
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    final url = Uri.parse("$baseUrl/conversations/$conversationId");
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to load conversation: ${response.statusCode}");
  }

  @override
  Future<Map<String, dynamic>> createConversation() async {
    final url = Uri.parse("$baseUrl/conversations");
    final response = await http.post(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Failed to create conversation: ${response.statusCode}");
  }

  @override
  Future<bool> deleteConversation(String conversationId) async {
    final url = Uri.parse("$baseUrl/conversations/$conversationId");
    try {
      final response = await http
          .delete(url)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["success"] == true;
      }
    } catch (e) {
      //
    }
    return false;
  }
}
