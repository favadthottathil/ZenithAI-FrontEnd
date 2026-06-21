import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../domain/models/message.dart';
import '../../domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  // Backend base URL is supplied at build time so the production endpoint is
  // never hardcoded in source:
  //   flutter build apk --dart-define=API_BASE_URL=https://api.example.com
  // The default below points at the deployed Render backend (HTTPS). For
  // local dev against a LAN backend, override with --dart-define, e.g.
  // 10.0.2.2 for Android Emulator, 127.0.0.1 for Windows/Web, or your host
  // machine's LAN IP for a physical device (backend running with --host 0.0.0.0).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: "https://llm-backend-08lr.onrender.com",
  );

  // The BLoC's getChatStream consumer parses a leading " CONV_ID:" chunk as
  // the newly-created conversation's real ID for a new chat. Kept identical
  // to the sentinel ChatBloc already expects so the BLoC needs no changes.
  static const String _conversationIdSentinel = " CONV_ID:";

  // Backend rejects requests whose `messages` array has more than 100 items
  // with a 422.
  static const int _maxMessagesPerRequest = 100;

  // The Render free tier spins the backend down after ~15 minutes of
  // inactivity; the first request after that wakes it back up and can take
  // 30-50s to respond. A short timeout (e.g. 10s) fails that cold-start
  // request every time, so REST calls use this longer timeout instead.
  static const Duration _restTimeout = Duration(seconds: 60);

  ChatRepositoryImpl() {
    // Release builds must talk to an encrypted endpoint. Cleartext HTTP is only
    // tolerated for local development (debug/profile builds).
    if (kReleaseMode && !baseUrl.startsWith("https://")) {
      throw StateError(
        "Release builds require an HTTPS API_BASE_URL "
        "(pass --dart-define=API_BASE_URL=https://...).",
      );
    }
  }

  // wss:// in production (HTTPS backend), ws:// for local HTTP dev.
  String get _wsBaseUrl {
    if (baseUrl.startsWith("https://")) {
      return "wss://${baseUrl.substring("https://".length)}";
    }
    if (baseUrl.startsWith("http://")) {
      return "ws://${baseUrl.substring("http://".length)}";
    }
    return baseUrl;
  }

  @override
  Stream<String> getChatStream(
    List<ChatMessage> messages, {
    String? conversationId,
  }) async* {
    final url = Uri.parse("$_wsBaseUrl/ws/chat-stream");

    // Backend rejects requests with more than 100 messages (422). Keep only
    // the most recent ones so very long conversations still send.
    final trimmedMessages = messages.length > _maxMessagesPerRequest
        ? messages.sublist(messages.length - _maxMessagesPerRequest)
        : messages;

    // Convert domain message models to json format expected by backend
    final formattedMessages = trimmedMessages.map((m) {
      final formatted = <String, dynamic>{
        "role": m.role.name,
        "content": m.text,
      };
      if (m.attachments.isNotEmpty) {
        formatted["attachments"] = m.attachments
            .map(
              (a) => {
                "type": a.type.name,
                "mime_type": a.mimeType,
                "filename": a.filename,
                "data": base64Encode(a.bytes),
              },
            )
            .toList();
      }
      return formatted;
    }).toList();

    final Map<String, dynamic> bodyMap = {
      "action": "start",
      "messages": formattedMessages,
    };
    if (conversationId != null && conversationId.isNotEmpty) {
      bodyMap["conversation_id"] = conversationId;
    }

    WebSocketChannel channel;
    int attempt = 0;
    // Render's free tier can take 30-50s to wake from a cold start, during
    // which the handshake gets dropped outright rather than timing out.
    // 5 attempts with growing backoff give the instance enough time to
    // finish waking up before giving up. Only retried while no chunk has
    // been received yet, so a half-streamed answer is never replayed.
    const int maxAttempts = 5;
    bool receivedAnyChunk = false;

    while (true) {
      attempt++;
      try {
        channel = WebSocketChannel.connect(url);
        await channel.ready.timeout(const Duration(seconds: 30));
        channel.sink.add(jsonEncode(bodyMap));
        break; // Connected and sent successfully
      } catch (e) {
        final errString = e.toString().toLowerCase();
        final isNetworkError =
            errString.contains("handshakeexception") ||
            errString.contains("handshake exception") ||
            errString.contains("connection terminated") ||
            errString.contains("socketexception") ||
            errString.contains("connection closed") ||
            errString.contains("timeoutexception") ||
            errString.contains("websocketchannelexception");

        if (isNetworkError && attempt < maxAttempts) {
          final delaySeconds = attempt * 3;
          await Future.delayed(Duration(seconds: delaySeconds));
          continue;
        }

        // Don't leak the backend URL/internal details to end users; log the
        // full diagnostic to the console in debug builds instead.
        if (kDebugMode) {
          debugPrint(
            "Connection failed. Ensure backend is running at $baseUrl. Error: $e",
          );
        }
        throw Exception("Couldn't reach the server. Check your connection.");
      }
    }

    final controller = StreamController<String>();
    controller.onCancel = () {
      try {
        channel.sink.add(jsonEncode({"action": "stop"}));
      } catch (_) {
        // Channel may already be closed; nothing to do.
      }
      channel.sink.close();
    };

    channel.stream.listen(
      (raw) {
        Map<String, dynamic> frame;
        try {
          frame = jsonDecode(raw as String) as Map<String, dynamic>;
        } catch (_) {
          return;
        }

        switch (frame["type"]) {
          case "conversation_id":
            receivedAnyChunk = true;
            controller.add(
              "$_conversationIdSentinel${frame["conversation_id"]}",
            );
          case "chunk":
            receivedAnyChunk = true;
            controller.add(frame["data"] as String);
          case "error":
            controller.addError(Exception(frame["message"]));
          case "done":
            controller.close();
        }
      },
      onError: (e) {
        if (!receivedAnyChunk) {
          controller.addError(
            Exception("Couldn't reach the server. Please try again."),
          );
        } else {
          controller.addError(e);
        }
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
    );

    yield* controller.stream;
  }

  // Helper function to retry standard HTTP requests that fail due to transient network conditions or Render's sleep/spin-up.
  Future<T> _retryRequest<T>(Future<T> Function() requestFn) async {
    // See getChatStream for why this needs enough attempts/backoff to ride
    // out a Render cold start (handshake drops outright, not just slow).
    int maxAttempts = 5;
    int attempt = 0;

    while (true) {
      attempt++;
      try {
        return await requestFn();
      } catch (e) {
        final errString = e.toString().toLowerCase();
        final isNetworkError =
            errString.contains("handshakeexception") ||
            errString.contains("handshake exception") ||
            errString.contains("connection terminated") ||
            errString.contains("socketexception") ||
            errString.contains("connection closed") ||
            errString.contains("timeoutexception") ||
            e is http.ClientException;

        if (isNetworkError && attempt < maxAttempts) {
          final delaySeconds = attempt * 3;
          await Future.delayed(Duration(seconds: delaySeconds));
          continue;
        }
        rethrow;
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getConversations() async {
    return _retryRequest(() async {
      final url = Uri.parse("$baseUrl/conversations");
      final response = await http.get(url).timeout(_restTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data["conversations"] ?? []);
      }
      throw Exception("Failed to load conversations: ${response.statusCode}");
    });
  }

  @override
  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    return _retryRequest(() async {
      final url = Uri.parse("$baseUrl/conversations/$conversationId");
      final response = await http.get(url).timeout(_restTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception("Failed to load conversation: ${response.statusCode}");
    });
  }

  @override
  Future<Map<String, dynamic>> createConversation() async {
    return _retryRequest(() async {
      final url = Uri.parse("$baseUrl/conversations");
      final response = await http.post(url).timeout(_restTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 429) {
        throw Exception(
          "You're sending requests too quickly. Please wait a moment and try again.",
        );
      }
      throw Exception("Failed to create conversation: ${response.statusCode}");
    });
  }

  @override
  Future<bool> deleteConversation(String conversationId) async {
    return _retryRequest(() async {
      final url = Uri.parse("$baseUrl/conversations/$conversationId");
      final response = await http.delete(url).timeout(_restTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["success"] == true;
      }
      throw Exception("Failed to delete conversation: ${response.statusCode}");
    });
  }
}
