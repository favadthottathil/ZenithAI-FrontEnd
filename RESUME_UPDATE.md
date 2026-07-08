# Resume update — Zenith AI

A full-stack AI chat application: Flutter client + FastAPI/Gemini backend, deployed and tested end-to-end (including on a physical Android device over WebSocket against the hosted backend).

## Project bullet (short, for top-level entry)

- **Zenith AI** — A ChatGPT-style cross-platform chat app (Flutter + FastAPI) with real-time streaming responses, voice I/O, file/image attachments, and persistent conversation history, backed by Google Gemini. Deployed frontend (Android/iOS/Web/Windows) and backend (Render).

## Frontend (Flutter) — suggested bullets

- Built a cross-platform (Android, iOS, Web, Windows) AI chat client in **Flutter/Dart** using **flutter_bloc** for state management, with a ChatGPT-style dark UI, Markdown rendering, and conversation history.
- Implemented real-time token streaming from the backend over **WebSocket**, with a custom buffered typewriter effect (variable-rate character reveal) for smooth UI animation independent of network chunking.
- Added multi-modal message attachments (images/documents) with client-side image compression/re-encoding (downscale + JPEG re-encode) and file-size guardrails before upload.
- Integrated **speech-to-text** input and **text-to-speech** playback for hands-free interaction.
- Built resilient networking: automatic reconnect/retry with exponential backoff for WebSocket and REST calls to handle backend cold-starts and transient connection drops (Render free-tier sleep/wake cycle).
- Added a privacy feature using Android's `FLAG_SECURE` to block screenshots/screen-recording and app-switcher previews of chat content, with a user-facing toggle.
- Wrote widget/unit tests (`flutter_test`) covering chat screen behavior and attachment handling; validated release builds on a physical Android device via ADB/wireless debugging.

## Backend (FastAPI + Gemini) — suggested bullets

- Built a **FastAPI** backend integrating **Google Gemini** (`google-genai`) for streaming AI chat completions, exposed over both a `/chat` REST endpoint and a `/ws/chat-stream` WebSocket for real-time token streaming.
- Implemented word-by-word response pacing and a model-fallback retry strategy (primary/secondary Gemini models with exponential backoff) to handle rate limits and transient API errors gracefully.
- Designed conversation persistence with **MongoDB** (via `motor`, async driver), including full CRUD REST endpoints for conversation history.
- Hardened the API with **slowapi** rate limiting, request body size limits, CORS allow-listing, and security headers (HSTS, X-Frame-Options, X-Content-Type-Options).
- Deployed on **Render**, with a self-ping keep-alive background task to mitigate free-tier cold-start/idle spin-down behavior.

## Notable technical details (for interview talking points)

- WebSocket protocol: client sends `{"action":"start", messages, conversation_id}`; server streams `{"type":"chunk"|"conversation_id"|"done"|"error"}` frames; client can send `{"action":"stop"}` to cancel generation server-side mid-stream.
- Diagnosed and ruled out a suspected Flutter/Vulkan rendering bug on a real device (all-black screenshots) — root cause was the app's own `FLAG_SECURE` screen-privacy flag blocking ADB screen capture, not a rendering failure. Verified actual UI correctness via Android's accessibility/UI-hierarchy dump instead of pixel screenshots.
- Tech stack: Flutter/Dart, flutter_bloc, web_socket_channel, FastAPI, Python, google-genai (Gemini), MongoDB/motor, Render.
