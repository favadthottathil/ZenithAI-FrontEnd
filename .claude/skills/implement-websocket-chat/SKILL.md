/---
name: implement-websocket-chat
description: Implement the SSE-to-WebSocket migration for Zenith AI chat streaming, across both the Flutter frontend (this repo) and the FastAPI backend at C:\Users\Admin\Desktop\LLM-backend. Use when asked to add/implement/continue WebSocket chat streaming, replace SSE, or work on /ws/chat-stream.
---

# Implement WebSocket chat streaming

Full plan: `C:\Users\Admin\.claude\plans\create-plan-for-the-distributed-popcorn.md`. Read
it first if it still exists — it has the complete protocol spec and verification steps.
This skill is the condensed, actionable version for driving implementation.

## Scope

Replace SSE-on-POST (`POST /chat-stream`) with a real WebSocket (`WS /ws/chat-stream`)
for the streaming chat reply only. Conversation CRUD (`/conversations` GET/POST/DELETE)
stays plain REST — do not touch it. SSE is fully removed once WS works; no dual path.

## Protocol contract

Client → server (sent once, right after connect):
```json
{"action": "start", "messages": [...], "conversation_id": "uuid-or-omitted"}
```
Client may also send `{"action": "stop"}` to cancel generation.

Server → client (one JSON object per message):
```json
{"type": "conversation_id", "conversation_id": "uuid"}   // first frame, new chats only
{"type": "chunk", "data": "raw text, real \n preserved"}
{"type": "done"}
{"type": "error", "message": "friendly text"}
```
Newlines travel as real characters now — no SSE `\n\n` delimiter collision, so the old
`_encode_sse_chunk` (backend) and space-run→`\n\n` reconstruction (frontend) are deleted,
not ported.

## Backend — `C:\Users\Admin\Desktop\LLM-backend`

1. `main.py`: add `from fastapi import WebSocket, WebSocketDisconnect` and
   `from pydantic import ValidationError`; drop the now-unused `StreamingResponse` import.
2. Refactor `stream_genarator` into a transport-agnostic async generator that yields raw
   `(kind, payload)` tuples (or just words) instead of SSE-formatted strings — keep the
   word-buffer pacing (`asyncio.sleep(0.08)`), the model fallback
   (`gemini-2.5-flash` → `gemini-2.0-flash`), the 6-attempt 429 backoff, and the
   `save_conversation` call after a successful stream, all unchanged in logic.
3. Delete `_encode_sse_chunk` and the `@app.post("/chat-stream")` route entirely.
4. Add:
   ```python
   @app.websocket("/ws/chat-stream")
   async def ws_chat_stream(ws: WebSocket):
       await ws.accept()
       ...
   ```
   Validate `Origin` header against `_allowed_origins` before `accept()` when the list is
   non-empty (allow missing Origin for native clients). Receive the initial JSON, build a
   `ChatRequest` from it (reuse the Pydantic model — catch `ValidationError`), then drive
   the generation loop, sending `conversation_id` → `chunk`s → `done`/`error` frames.
5. Stop support: race the generation task against a concurrent `ws.receive_json()` using
   `asyncio.wait(..., return_when=asyncio.FIRST_COMPLETED)`; a `{"action":"stop"}` frame or
   `WebSocketDisconnect` cancels the generation task.
6. Rate limiting: `slowapi`'s decorator doesn't cover WS routes. Add a simple per-IP
   (`ws.client.host`) sliding-window counter (module-level dict) capped at 10 starts/min to
   mirror the old `@limiter.limit("10/minute")`.
7. `requirements.txt`: add `websockets` (uvicorn's WS protocol implementation).
8. Do not touch `models/chat_model.py`, `services/llm_services.py`,
   `services/db_services.py` — reuse their functions as-is.

## Frontend — this repo

1. `pubspec.yaml`: add `web_socket_channel: ^3.0.0`. Keep `http` (still used by REST CRUD).
2. `lib/data/repositories/chat_repository_impl.dart`:
   - Add a `wsBaseUrl` derived from `baseUrl` (scheme `https→wss`, `http→ws`) +
     `/ws/chat-stream`.
   - Rewrite `getChatStream` to open a `WebSocketChannel`, send
     `jsonEncode({"action": "start", ...bodyMap})` (keep the existing message-formatting
     block — role/content/attachments, the 100-message trim — verbatim), then `await for`
     over the channel decoding each JSON frame:
     - `conversation_id` → yield `"$_conversationIdSentinel${frame['conversation_id']}"`
       matching the exact sentinel string the BLoC already parses
       (`" CONV_ID:"` in `chat_bloc.dart`) — do not change the BLoC.
     - `chunk` → yield `frame['data']` raw, no space/newline post-processing.
     - `error` → throw `Exception(frame['message'])`.
     - `done` → close the channel and let the stream complete naturally.
   - Delete the SSE-specific parsing entirely (`\n\n` buffer loop, `pendingSpaces`,
     `RegExp(' {2,}')` reconstruction).
   - Keep the same cold-start retry shape (5 attempts, `attempt*3`s backoff) around
     connect+send, but only retry while zero chunks have been received yet — never replay
     a partially streamed answer.
   - On stream-subscription cancel (BLoC's `_cancelActiveStream`), send
     `{"action":"stop"}` before closing the channel, via an `onCancel` callback on the
     `async*`/`StreamController` — no BLoC changes required.
   - Leave all REST CRUD methods (`getConversations`, `getConversation`,
     `createConversation`, `deleteConversation`) and `_retryRequest` untouched.
3. `lib/presentation/bloc/chat_bloc.dart`: expect no changes — verify the sentinel,
   typewriter timer, and streaming events still work against the new transport.
4. Update `llm_fast_api_gemini_streaming_integration_guide.md` to document the WS protocol
   in place of the SSE section.
5. Update `CLAUDE.md`'s "Backend integration" / architecture notes once migration is
   complete (remove "in progress" framing, describe WS as current state).

## Verification

Run through the plan's verification section: backend boots locally, a raw WS client can
complete a `start`→`chunk*`→`done` round trip with real newlines preserved, `stop`
actually cancels generation, attachments still reach Gemini, conversations still persist
and list via REST, then `flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000`
end-to-end (typewriter animation, multi-paragraph formatting, new-chat id, stop button),
followed by `flutter analyze` and `flutter test`.
