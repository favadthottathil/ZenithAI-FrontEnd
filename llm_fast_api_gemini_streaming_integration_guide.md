# Chat Stream API – Frontend Integration Guide

This document explains ONLY what frontend developers need to know to integrate the streaming chat UI.

---

# What Backend Does

The backend provides an AI chat streaming API using Gemini LLM.

Flow:

User message → FastAPI backend → Gemini LLM → tokens streamed → frontend receives text gradually

The backend:

1. Receives chat message from frontend over a WebSocket connection
2. Sends prompt to Gemini AI model
3. Receives response token-by-token
4. Streams words to the frontend as JSON frames over the WebSocket
5. Sends partial text continuously to frontend

The frontend should NOT wait for full response.
Instead, it should append incoming text chunks to the UI.

---

# Streaming Chat API Endpoint

## WS /ws/chat-stream

### URL

ws://127.0.0.1:8000/ws/chat-stream (wss:// in production)

---

# Client → Server Frames

After connecting, the client sends exactly one `start` frame:

```json
{
  "action": "start",
  "messages": [
    {
      "role": "user",
      "content": "Explain Flutter Bloc simply"
    }
  ],
  "conversation_id": "uuid-or-omitted"
}
```

`conversation_id` is omitted for a brand-new chat; the backend will generate one and
send it back (see below).

To cancel an in-flight generation, send:

```json
{ "action": "stop" }
```

The backend cancels the Gemini call and closes the socket.

---

# Server → Client Frames

Each WebSocket message is a single JSON object. Possible `type` values:

```json
{ "type": "conversation_id", "conversation_id": "uuid" }
```
Sent once, immediately, only for a brand-new chat (no `conversation_id` was sent by the
client). Use this to start tracking the conversation.

```json
{ "type": "chunk", "data": "Flutter Bloc is a state management\nsolution used in Flutter" }
```
Sent repeatedly as the model generates text. `data` contains the **raw** text — real
newlines are preserved (no escaping/munging needed, unlike the old SSE transport).

```json
{ "type": "done" }
```
Sent once generation completes successfully; the socket closes after this.

```json
{ "type": "error", "message": "friendly text" }
```
Sent if something goes wrong (rate limit, invalid input, generation failure); the socket
closes after this.

Frontend must:

• connect to the WebSocket
• send the `start` frame
• listen for `chunk` frames and append `data` to the message text
• stop listening on `done` or `error`
• update UI live as `chunk` frames arrive

---

# Expected Frontend Behaviour

1. Open a WebSocket connection to `/ws/chat-stream`
2. Send the `start` frame with the message history
3. Listen to incoming frames
4. Append each `chunk`'s `data` to message text
5. Display typing effect in chat UI
6. Close (or send `stop`) to cancel generation early

---

# Message Object Format

```json
{
  "role": "user",
  "content": "message text"
}
```

Currently supported roles:

user
assistant
system (optional)

---

# Attachments

The frontend can optionally attach images and documents to a user message
for Gemini Vision / document Q&A. When present, each message in `messages`
may include an `attachments` array:

```json
{
  "action": "start",
  "messages": [
    {
      "role": "user",
      "content": "What's in this image?",
      "attachments": [
        {
          "type": "image",
          "mime_type": "image/jpeg",
          "filename": "photo.jpg",
          "data": "<base64-encoded bytes>"
        }
      ]
    }
  ]
}
```

Fields:

- `type`: `"image"` or `"document"`
- `mime_type`: standard MIME type (e.g. `image/jpeg`, `image/png`, `application/pdf`, `text/plain`)
- `filename`: original filename, for display/reference
- `data`: base64-encoded file bytes

Frontend-enforced limits (so the backend can expect payloads within these bounds):

- Max 4 attachments per message
- Images are resized so their longest side is ≤ 1280px and re-encoded as JPEG at quality 80
- Documents are capped at 15MB
- Document picker only allows `.pdf` and `.txt` (`application/pdf` / `text/plain`) — `.doc`/`.docx`
  are not offered, since Gemini's inline `Part.from_bytes` document understanding doesn't
  reliably support Word mime types

Backend responsibility (implemented in `services/llm_services.py` via
`build_contents`): decode `data` from base64 and pass each attachment as a
`genai.types.Part.from_bytes(data=..., mime_type=...)` alongside the message's
`content` text.

---

# Example Flutter Flow

connect WS → send `start` frame → receive `chunk` frames → append text → rebuild UI → receive `done`

---

# Summary

Endpoint:
WS /ws/chat-stream

Protocol:
WebSocket, JSON frames

Frontend responsibility:
render text incrementally as `chunk` frames arrive; send `stop` to cancel

Backend responsibility:
stream AI generated text as JSON frames; persist conversation history via the existing
REST `/conversations` endpoints (unchanged, still plain HTTP)

---
