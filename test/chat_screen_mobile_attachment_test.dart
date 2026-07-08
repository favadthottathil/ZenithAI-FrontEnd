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
    'mobile chat screen with attachment + open keyboard stays usable',
    (WidgetTester tester) async {
    // A typical phone size, portrait.
    await tester.binding.setSurfaceSize(const Size(390, 844));
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

    // Pick an image, like the "+" attachment button would.
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

    final previewImageFinder = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is MemoryImage,
    );
    expect(previewImageFinder, findsOneWidget);
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    const screenHeight = 844.0;
    final textFieldRectBefore = tester.getRect(textFieldFinder);
    expect(
      textFieldRectBefore.bottom,
      lessThanOrEqualTo(screenHeight),
      reason:
          'TextField should be within the visible screen before the keyboard opens',
    );

    // Now simulate the on-screen keyboard opening (typical height ~300px)
    // by tapping the text field and providing bottom view insets.
    await tester.tap(textFieldFinder);
    await tester.pumpAndSettle();

    final mediaQueryData = MediaQuery.of(
      tester.element(find.byType(ChatScreen)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: BlocProvider<ChatBloc>.value(
          value: bloc,
          child: MediaQuery(
            data: mediaQueryData.copyWith(
              viewInsets: const EdgeInsets.only(bottom: 300),
            ),
            child: const ChatScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final textFieldRectAfter = tester.getRect(textFieldFinder);
    expect(
      textFieldRectAfter.bottom,
      lessThanOrEqualTo(screenHeight - 300),
      reason:
          'TextField should remain above the keyboard, not hidden behind/below it',
    );

    // Typing should still work with the keyboard open and an attachment pending.
    await tester.enterText(textFieldFinder, 'hello world');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('hello world'), findsOneWidget);
  });
}
