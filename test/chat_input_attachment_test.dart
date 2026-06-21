import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/domain/models/attachment.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/domain/repositories/chat_repository.dart';
import 'package:llm_chat_app/presentation/bloc/chat_bloc.dart';
import 'package:llm_chat_app/presentation/widgets/chat_input.dart';

class FakeChatRepository implements ChatRepository {
  @override
  Stream<String> getChatStream(
    List<ChatMessage> messages, {
    String? conversationId,
  }) {
    return const Stream<String>.empty();
  }

  @override
  Future<List<Map<String, dynamic>>> getConversations() async => [];

  @override
  Future<Map<String, dynamic>> getConversation(String conversationId) async =>
      {};

  @override
  Future<Map<String, dynamic>> createConversation() async => {};

  @override
  Future<bool> deleteConversation(String conversationId) async => true;
}

// 1x1 transparent PNG
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets(
    'attachment preview shows above the text field and input stays usable on a mobile-sized screen',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bloc = ChatBloc(repository: FakeChatRepository());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<ChatBloc>.value(
            value: bloc,
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInput(onSend: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      bloc.add(
        AttachmentPicked(
          MessageAttachment(
            type: AttachmentType.image,
            filename: 'test.png',
            mimeType: 'image/png',
            bytes: _tinyPng,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // The attachment preview thumbnail should be visible above the TextField.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      final textFieldRect = tester.getRect(find.byType(TextField));
      final imageRect = tester.getRect(find.byType(Image));
      expect(
        imageRect.bottom,
        lessThanOrEqualTo(textFieldRect.top + 1),
        reason: 'Attachment preview should sit above the text field',
      );

      // Typing should still work after attaching an image.
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('hello world'), findsOneWidget);
    },
  );
}
