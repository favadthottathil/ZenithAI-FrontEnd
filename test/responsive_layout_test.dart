// Exercises ChatScreen (empty state, message list with markdown/attachments,
// streaming with pending attachments) across a range of phone/tablet/desktop
// screen sizes to catch RenderFlex overflow errors and other layout
// exceptions.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// Lets tests jump straight to a given ChatState without driving the bloc
// through real events/streams.
class TestChatBloc extends ChatBloc {
  TestChatBloc() : super(repository: FakeChatRepository());

  void setTestState(ChatState state) => emit(state);
}

final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

const String _longWord =
    'Supercalifragilisticexpialidocioussupercalifragilisticexpialidocious'
    'supercalifragilisticexpialidocioussupercalifragilisticexpialidocious';

const String _markdownText = '''
# Heading one
## Heading two

This is **bold text** and a [link](https://example.com/very/long/path/that/keeps/going/and/going/and/going/forever) inline.

- bullet one
- bullet two with $_longWord embedded to test wrapping

```dart
void main() {
  print('https://example.com/another/extremely/long/url/segment/that/should/not/overflow');
}
```
''';

List<ChatMessage> _buildMessages() => [
  ChatMessage(
    text: 'Hi there, can you help me plan a trip to $_longWord?',
    role: MessageRole.user,
    timestamp: DateTime(2024, 1, 1),
  ),
  ChatMessage(
    text: _markdownText,
    role: MessageRole.assistant,
    timestamp: DateTime(2024, 1, 1, 0, 1),
  ),
  ChatMessage(
    text: 'Here are my attachments',
    role: MessageRole.user,
    timestamp: DateTime(2024, 1, 1, 0, 2),
    attachments: [
      MessageAttachment(
        type: AttachmentType.image,
        filename: 'photo1.png',
        mimeType: 'image/png',
        bytes: _tinyPng,
      ),
      MessageAttachment(
        type: AttachmentType.image,
        filename: 'photo2.png',
        mimeType: 'image/png',
        bytes: _tinyPng,
      ),
      MessageAttachment(
        type: AttachmentType.document,
        filename: 'a_very_long_document_filename_for_testing_wrap.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ],
  ),
];

List<MessageAttachment> _buildPendingAttachments() => [
  MessageAttachment(
    type: AttachmentType.image,
    filename: 'photo1.png',
    mimeType: 'image/png',
    bytes: _tinyPng,
  ),
  MessageAttachment(
    type: AttachmentType.image,
    filename: 'photo2.png',
    mimeType: 'image/png',
    bytes: _tinyPng,
  ),
  MessageAttachment(
    type: AttachmentType.document,
    filename: 'a_very_long_document_filename_for_testing_wrap_1.pdf',
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
  ),
  MessageAttachment(
    type: AttachmentType.document,
    filename: 'a_very_long_document_filename_for_testing_wrap_2.pdf',
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
  ),
];

// Covers small/large phones, foldables, tablets, and desktop/web widths,
// in both portrait and landscape.
const List<Size> _screenSizes = <Size>[
  Size(320, 568), // iPhone SE / smallest common phone
  Size(360, 740), // common small Android
  Size(390, 844), // iPhone 12/13/14
  Size(412, 915), // Pixel-class Android
  Size(600, 1024), // small tablet / large foldable, portrait
  Size(768, 1024), // iPad portrait
  Size(820, 1180), // iPad Air portrait
  Size(667, 375), // phone landscape (narrow height)
  Size(900, 600), // sidebar/drawer breakpoint, landscape
  Size(1024, 768), // tablet landscape / small desktop
  Size(1440, 900), // laptop
  Size(1920, 1080), // full HD desktop
];

Future<void> _pumpChatScreen(WidgetTester tester, TestChatBloc bloc) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: BlocProvider<ChatBloc>.value(value: bloc, child: const ChatScreen()),
    ),
  );
}

void main() {
  // flutter_tts has no test-mode plugin implementation; ChatBloc.close()
  // calls FlutterTts.stop(), which would otherwise throw a
  // MissingPluginException that leaks into (and fails) the next test.
  const ttsChannel = MethodChannel('flutter_tts');
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ttsChannel, (call) async => 1);

  for (final size in _screenSizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('empty state renders without overflow at $label', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bloc = TestChatBloc();
      addTearDown(bloc.close);

      await _pumpChatScreen(tester, bloc);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'message list with markdown + attachments renders without overflow at $label',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bloc = TestChatBloc();
        addTearDown(bloc.close);

        await _pumpChatScreen(tester, bloc);
        await tester.pumpAndSettle();

        bloc.setTestState(ChatSuccess(_buildMessages()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Scroll the message list to make the rest of the content build too.
        final listFinder = find.byType(ListView).first;
        await tester.drag(listFinder, const Offset(0, -4000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'streaming with pending attachments renders without overflow at $label',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final bloc = TestChatBloc();
        addTearDown(bloc.close);

        await _pumpChatScreen(tester, bloc);
        await tester.pumpAndSettle();

        final messages = _buildMessages()
          ..add(
            ChatMessage(
              text: 'Streaming reply with a $_longWord unbroken token...',
              role: MessageRole.assistant,
              timestamp: DateTime(2024, 1, 1, 0, 3),
            ),
          );
        bloc.setTestState(
          ChatStreaming(
            messages,
            pendingAttachments: _buildPendingAttachments(),
          ),
        );
        // The streaming cursor blinks via a repeating animation, so
        // pumpAndSettle would never settle: pump a fixed number of frames.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        final listFinder = find.byType(ListView).first;
        await tester.drag(listFinder, const Offset(0, -4000));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
