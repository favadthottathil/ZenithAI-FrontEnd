import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/message.dart';
import '../../domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  // For Android Emulator use 10.0.2.2, for Windows/Web use 127.0.0.1
  // For physical Android device debugging, use your host machine's IP address
  final String baseUrl = "http://192.168.1.125:8000";

  @override
  Stream<String> getChatStream(List<ChatMessage> messages) async* {
    final url = Uri.parse("$baseUrl/chat-stream");

    final request = http.Request("POST", url);
    request.headers["Content-Type"] = "application/json";
    request.headers["Accept"] = "text/event-stream";
    request.headers["Cache-Control"] = "no-cache";

    // Convert domain message models to json format expected by backend
    final formattedMessages = messages
        .map((m) => {"role": m.role.name, "content": m.text})
        .toList();

    request.body = jsonEncode({"messages": formattedMessages});

    print("REPOSITORY: Sending request to $url");
    http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(seconds: 30));
    } catch (e) {
      print("REPOSITORY ERROR: $e");
      throw Exception(
        "Connection failed. Ensure backend is running at $baseUrl. Error: $e",
      );
    }

    print("REPOSITORY: Received response status: ${response.statusCode}");

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to connect to chat stream: ${response.statusCode}",
      );
    }

    // Process the stream line by line
    yield* response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) {
          final trimmedLine = line.trim();
          if (trimmedLine.startsWith("data: ")) {
            return trimmedLine.substring(6);
          }
          return "";
        })
        .where((text) => text.isNotEmpty);
  }
}
