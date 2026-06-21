# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A Flutter chat client ("Zenith AI") that talks to a separate FastAPI + Gemini backend over a WebSocket (`/ws/chat-stream`). The UI is a ChatGPT-style dark-themed chat interface with conversation history, streaming responses with a typewriter effect, speech-to-text input, and image/document attachments (shown as previews above the input before sending).

## Commands

This is a standard Flutter app (targets: android, ios, web, windows).

- Run the app: `flutter run` (pick a device/target, e.g. `flutter run -d windows`, `flutter run -d chrome`)
- Install dependencies: `flutter pub get`
- Static analysis / lint: `flutter analyze`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/widget_test.dart`
- Format code: `dart format .`

Flutter is installed at `C:\Users\Admin\flutter\bin` (may not be on PATH by default).

## Architecture

The app follows a domain/data/presentation split with `flutter_bloc` for state management.

- `lib/main.dart` — app entry point. Wires up `RepositoryProvider` (provides `ChatRepositoryImpl`) and `BlocProvider` (provides `ChatBloc`), and applies `AppTheme.darkTheme`.
- `lib/domain/models/message.dart` — `ChatMessage` (the canonical model, carries an `attachments` list) and `MessageRole` enum (`user`, `assistant`). Note: `lib/models/message.dart` is a leftover duplicate/older version of this model and is **not used** by any current code — don't import from it.
- `lib/domain/models/attachment.dart` — `MessageAttachment` (`type`, `filename`, `mimeType`, `bytes`) and the `AttachmentType` enum (`image`, `document`). Used both for pending (pre-send) attachments and attachments persisted on past messages.
- `lib/domain/repositories/chat_repository.dart` — abstract `ChatRepository` interface: `getChatStream`, `getConversations`, `getConversation`, `createConversation`, `deleteConversation`.
- `lib/data/repositories/chat_repository_impl.dart` — concrete implementation. Talks to the backend at a `baseUrl` (currently a deployed Render URL, overridable via `--dart-define=API_BASE_URL=...`). `getChatStream` opens a `WebSocketChannel` to `/ws/chat-stream` (derived via `_wsBaseUrl`, mapping `https→wss`/`http→ws`), sends a `{"action":"start",...}` frame, and decodes `conversation_id`/`chunk`/`done`/`error` JSON frames into the `Stream<String>` the BLoC consumes — cancelling the subscription sends `{"action":"stop"}`. Conversation CRUD hits `/conversations` REST endpoints (unchanged, plain HTTP via `_retryRequest`).
- `lib/presentation/bloc/` — `ChatBloc` + `ChatEvent`/`ChatState` (in `chat_state.dart`, exported from `chat_bloc.dart`).
  - `ChatState` is a single class hierarchy (`ChatInitial`, `ChatLoading`, `ChatStreaming`, `ChatSuccess`, `ChatError`) that all carry the full state (`messages`, `activeModel`, `isListening`, `inputText`, `conversationId`, `conversations`, `pendingAttachments`, transient `infoMessage`). Use `_copyStateWith(...)` in `ChatBloc` to update fields while preserving the current subclass.
  - Attachments are driven through bloc events (`AttachmentPicked`, `AttachmentRemoved`) and held in `state.pendingAttachments` (max 4). `_onAttachmentPicked` enforces a 15MB cap on documents and, for images, downscales/re-encodes to JPEG (longest side ≤ 1280px) via the `image` package in `_resizeImageAttachment` (wrapped in try/catch so a decode failure falls back to the original bytes rather than dropping the attachment). On send (`_onMessageSent`), `pendingAttachments` are attached to the outgoing `ChatMessage` and then cleared.
  - Streaming uses a **BLoC-level typewriter effect**: raw WS chunks are buffered (`_typewriterBuffer`) and a `Timer.periodic` (`_startTypewriterTimer`) drains the buffer at a variable rate (more chars/tick as the buffer grows) via private events `_UpdateStreamingMessages` / `_StreamingFinished` / `_StreamingError`, so the UI animates character-by-character regardless of network chunking. The new-chat conversation ID arrives as a sentinel-prefixed chunk (`_conversationIdSentinel = " CONV_ID:"`) rather than being mixed into the streamed text.
  - Speech-to-text (`speech_to_text` package) is also driven through bloc events (`ToggleSpeechListening`, `SetSpeechListening`, `UpdateInputText`) — no `setState` in widgets for this.
  - Conversation persistence (`LoadConversations`, `SelectConversation`, `CreateNewConversation`, `DeleteConversation`) talks to the repository's `/conversations` endpoints and keeps `state.conversations` in sync.
- `lib/presentation/screens/chat_screen.dart` — main scaffold: responsive layout (desktop sidebar vs mobile drawer at 900px breakpoint), message list (`ListView.builder` of `MessageBubble`), auto-scroll-to-bottom logic, conversation history list (`_HistoryList`), empty-state with suggestion cards.
- `lib/presentation/widgets/message_bubble.dart` — renders one message. While streaming/thinking it shows plain text with a blinking cursor (`_buildStreamingText`); once complete it renders full Markdown via `flutter_markdown` (`_buildMarkdownContent`), including a custom `_formatText` preprocessor that converts certain `*`/`**`-prefixed lines into Markdown headings. Also has like/dislike/copy/speak action buttons that dispatch bloc events.
- `lib/presentation/widgets/chat_input.dart` — input bar; syncs its `TextEditingController` from `state.inputText` via `BlocListener` (no local text state), dispatches `UpdateInputText`/`ChatMessageSent`/`ToggleSpeechListening`. Renders a horizontal row of pending-attachment thumbnails (`_buildAttachmentPreviews` / `_AttachmentPreviewItem`, each with a remove "x") **above** the text field when `state.pendingAttachments` is non-empty. The "+" button opens a bottom sheet ("Upload from library" / "Attach document") whose `onTap`s call `_pickImages()` / `_pickDocuments()` — these use the `State`'s own `context`/`mounted`, **not** the bottom-sheet builder's context. (Gotcha: using the sheet's context for the post-`await` `mounted` guard silently swallows the picked file, because that context is already unmounted after `Navigator.pop` — so always pop the sheet via its own context but do the file-picking against the State.)
- `lib/theme/app_theme.dart` — single source of truth for colors (`AppTheme.primaryColor`, `backgroundColor`, etc.) and the dark `ThemeData`. Reuse these constants instead of hardcoding colors when possible (though many widgets currently use ad-hoc `Color(0xFF...)` / `Colors.white.withValues(alpha: ...)`).

## Backend integration

See `llm_fast_api_gemini_streaming_integration_guide.md` for the WebSocket contract (`WS /ws/chat-stream`, frame shapes). The backend is a separate FastAPI service at `C:\Users\Admin\Desktop\LLM-backend` (not in this repo); `ChatRepositoryImpl.baseUrl` points to a deployed instance, and `_wsBaseUrl` derives the `ws(s)://` equivalent from it. For local backend testing, the platform-specific host differs (e.g. `10.0.2.2` for Android emulator vs `127.0.0.1` for desktop/web) — see the comment above `baseUrl`. Conversation CRUD (`/conversations`) is unaffected by the WS migration and remains plain REST.

### WebSocket protocol

`getChatStream` sends one `{"action":"start","messages":[...],"conversation_id":"...?"}` frame after connecting, and may later send `{"action":"stop"}` (on stream-subscription cancel) to abort generation server-side. The backend (`main.py`'s `ws_chat_stream` + `generate_reply_words`) replies with a sequence of JSON frames: an optional `{"type":"conversation_id",...}` first frame for new chats, then `{"type":"chunk","data":"..."}` per word (real newlines preserved — no SSE-style escaping), then `{"type":"done"}` or `{"type":"error","message":"..."}`. The repository translates these into the plain `Stream<String>` the BLoC already expects, including re-emitting the conversation ID as the `" CONV_ID:"`-prefixed sentinel string `chat_bloc.dart` parses.

### Render cold-start / connection-drop handling

The backend runs on Render's free tier, which spins the service down after ~15 minutes idle. The first request after that can take 30-50s to wake up, and during that window the connection gets dropped outright (handshake/connection-reset errors on the WS upgrade, or `HttpException: Connection closed before full header was received` on plain REST calls) rather than just timing out.

- `lib/data/repositories/chat_repository_impl.dart` retries both `getChatStream`'s WebSocket connect (its own inline retry loop, only before any chunk has been received) and the REST calls (`_retryRequest`, used by `getConversations`/`createConversation`/`getConversation`/`deleteConversation`) up to 5 times with `attempt * 3`s backoff (3/6/9/12s) whenever the error string matches `handshakeexception`, `connection terminated`, `socketexception`, `connection closed`, `timeoutexception`, `websocketchannelexception`, or is an `http.ClientException`.
- The backend's `main.py` also runs a `_keep_alive_loop()` background task (wired via FastAPI `lifespan`) that pings its own public URL (`RENDER_EXTERNAL_URL`, falling back to the deployed `onrender.com` URL) every 13 minutes to prevent Render from spinning it down in the first place. The frontend retries above are the fallback for when this doesn't catch it (e.g. right after a deploy/restart).
- If you see "Exception has occurred" for one of these error strings while debugging, it's likely VS Code pausing on a *caught* first-chance exception inside the retry loop, not an unhandled crash — confirm the app recovers after Resume before treating it as a bug.
