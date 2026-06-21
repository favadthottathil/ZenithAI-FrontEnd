import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/domain/models/attachment.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/domain/repositories/chat_repository.dart';
import 'package:llm_chat_app/presentation/bloc/chat_bloc.dart';
import 'package:llm_chat_app/presentation/screens/chat_screen.dart';
import 'package:llm_chat_app/theme/app_theme.dart';

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

final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets(
    'small mobile screen with several attachments keeps the text field usable',
    (WidgetTester tester) async {
      // A smaller phone size (e.g. iPhone SE), portrait.
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bloc = ChatBloc(repository: FakeChatRepository());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: BlocProvider<ChatBloc>.value(
            value: bloc,
            child: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        bloc.add(
          AttachmentPicked(
            MessageAttachment(
              type: AttachmentType.image,
              filename: 'test$i.png',
              mimeType: 'image/png',
              bytes: _tinyPng,
            ),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final previewImageFinder = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      );
      expect(previewImageFinder, findsNWidgets(4));

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      final previewRect = tester.getRect(previewImageFinder.first);
      final textFieldRect = tester.getRect(textFieldFinder);
      expect(
        previewRect.bottom,
        lessThanOrEqualTo(textFieldRect.top + 1),
        reason: 'Attachment previews should sit above the text field',
      );

      await tester.enterText(textFieldFinder, 'hello world');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('hello world'), findsOneWidget);
    },
  );
}
