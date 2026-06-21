# Zenith AI — Full-Stack AI Chat Application

A production-style, ChatGPT-like AI chat product built end to end: a **cross-platform Flutter client** and a **FastAPI + Google Gemini backend** communicating over **Server-Sent Events (SSE)** for real-time, token-by-token streaming. Includes conversation persistence, multimodal (image/document) input, speech-to-text, and a hardened, deploy-ready backend.

> This document summarizes the **entire project** (frontend + backend) and is written to be reused directly on a resume / portfolio.

---

## 1. At a Glance

| | |
|---|---|
| **Product** | Zenith AI — streaming AI chat assistant |
| **Frontend** | Flutter (Dart) — Android, iOS, Web, Windows |
| **Backend** | Python, FastAPI, Google Gemini (`google-genai`) |
| **Streaming** | Server-Sent Events (SSE), token-by-token typewriter UX |
| **Persistence** | MongoDB (async via Motor) with automatic local-JSON fallback |
| **State management** | `flutter_bloc` (BLoC pattern), clean domain/data/presentation split |
| **Deployment** | Render (Docker-free, `render.yaml`), keep-alive cold-start mitigation |
| **Multimodal** | Image + PDF/TXT attachments → Gemini vision / document Q&A |

---

## 2. Architecture Overview

```
┌─────────────────────────────┐         SSE (text/event-stream)        ┌──────────────────────────────┐
│      Flutter Client          │  ───── POST /chat-stream ───────────▶ │     FastAPI Backend           │
│  (Android/iOS/Web/Windows)   │                                        │                               │
│                              │  ◀──── data: <token> chunks ────────── │  • Gemini streaming           │
│  • BLoC state management      │                                        │  • Conversation CRUD          │
│  • Typewriter rendering       │  ───── REST /conversations ─────────▶ │  • Rate limiting + security   │
│  • Attachments / STT / TTS    │                                        │  • MongoDB / JSON persistence │
└─────────────────────────────┘                                        └───────────────┬──────────────┘
                                                                                        │
                                                                          ┌─────────────▼─────────────┐
                                                                          │  Google Gemini API         │
                                                                          │  (2.5-flash → 2.0-flash)   │
                                                                          └────────────────────────────┘
```

The system is split into two independently deployable repositories:

- **Frontend** — `LLM-Front-end-Flutter` (this repo)
- **Backend** — `LLM-backend` (separate FastAPI service)

---

## 3. Frontend (Flutter)

A responsive, dark-themed chat UI following a strict **domain / data / presentation** architecture with `flutter_bloc`.

### Key Features
- **Real-time streaming UX** — a BLoC-level typewriter engine buffers raw SSE chunks and drains them at a variable rate via a `Timer.periodic`, so the response animates character-by-character regardless of network chunking.
- **Conversation history** — create, list, select, and delete past conversations; UI stays in sync with the backend's `/conversations` endpoints.
- **Multimodal attachments** — attach up to 4 images/documents per message, shown as preview thumbnails above the input. Images are auto-downscaled (longest side ≤ 1280px) and re-encoded to JPEG client-side; documents capped at 15MB.
- **Speech-to-text** input (`speech_to_text`) and **text-to-speech** playback (`flutter_tts`), both driven through BLoC events (no widget-local `setState`).
- **Markdown rendering** of completed responses (`flutter_markdown`) with a custom preprocessor, plus like/dislike/copy/speak actions per message.
- **Responsive layout** — desktop sidebar vs. mobile drawer at a 900px breakpoint, auto-scroll-to-bottom, empty-state suggestion cards.
- **Resilient networking** — inline retry loops with exponential backoff to survive backend cold-start handshake drops.

### Tech & Libraries
`Flutter` · `flutter_bloc` + `equatable` (state) · `http` (SSE/REST) · `file_picker` + `image` (attachments) · `speech_to_text` · `flutter_tts` · `flutter_markdown` · `google_fonts` · `shared_preferences` · `url_launcher`

### Structure
```
lib/
├── main.dart                         # DI wiring (RepositoryProvider + BlocProvider), theme
├── domain/
│   ├── models/                       # ChatMessage, MessageRole, MessageAttachment
│   └── repositories/                 # ChatRepository (abstract interface)
├── data/
│   └── repositories/                 # ChatRepositoryImpl (SSE parsing, REST, retries)
├── presentation/
│   ├── bloc/                         # ChatBloc + ChatEvent/ChatState (typewriter, attachments, STT)
│   ├── screens/                      # chat_screen.dart (responsive scaffold)
│   └── widgets/                      # message_bubble, chat_input, settings_sheet
├── core/security/                    # safe_link, screen_security, attachment_validator
└── theme/                            # app_theme.dart (single source of truth for styling)
```

---

## 4. Backend (FastAPI + Gemini)

A FastAPI service that bridges the client to Google Gemini, streams tokens over SSE, persists conversations, and is hardened for public deployment.

### Endpoints
| Method | Route | Purpose |
|---|---|---|
| `GET` | `/` | Health check |
| `POST` | `/chat-stream` | **Streaming** chat (SSE), token-by-token |
| `POST` | `/chat` | Non-streaming structured (JSON) chat |
| `GET` | `/conversations` | List all conversations (metadata) |
| `GET` | `/conversations/{id}` | Fetch full message log |
| `POST` | `/conversations` | Create a new conversation |
| `DELETE` | `/conversations/{id}` | Delete a conversation |

### Key Features
- **SSE token streaming** — wraps `gemini.generate_content_stream`, emits word-boundary-aligned `data:` events with pacing delays for a smooth typing effect. Newlines are escaped so paragraph breaks never corrupt the `\n\n` SSE event framing.
- **Model fallback + retry** — attempts `gemini-2.5-flash`, then falls back to `gemini-2.0-flash`, with exponential backoff on `429 / RESOURCE_EXHAUSTED` rate limits (up to 6 attempts).
- **Conversation persistence** — async **MongoDB** (Motor) with a **transparent local-JSON-file fallback** when Mongo is unreachable, so the service runs anywhere with no infra.
- **Auto chat titles** — generates a concise 3–5 word conversation title from the first response via Gemini, with a word-truncation fallback.
- **Multimodal contents builder** — decodes base64 attachments and forwards them to Gemini as inline `Part.from_bytes` alongside text, for both `/chat` and `/chat-stream`.
- **Security hardening:**
  - Per-IP **rate limiting** (`slowapi`) to protect the paid Gemini quota.
  - **CORS allow-list** via env, **request body size cap** (25MB) middleware, and security headers (`X-Content-Type-Options`, `X-Frame-Options`, `HSTS`).
  - **Pydantic validation** with strict limits (content length, attachment count/size, allowed MIME types) and **UUID validation** that blocks path-traversal in the JSON-file store.
- **Render cold-start mitigation** — a `lifespan` background task pings the service's own public URL every 13 minutes to prevent free-tier spin-down.

### Tech & Libraries
`FastAPI` · `uvicorn` · `google-genai` (Gemini) · `motor` + `pymongo` (MongoDB) · `slowapi` (rate limiting) · `pydantic` (validation) · `python-dotenv`

### Structure
```
LLM-backend/
├── main.py                  # App, middleware, routes, SSE generator, keep-alive
├── models/chat_model.py     # Pydantic models + validation/size limits
├── services/
│   ├── llm_services.py       # Gemini calls, prompt + multimodal contents builder
│   └── db_services.py        # MongoDB / JSON persistence, auto-titling
├── requirements.txt
└── render.yaml               # Render deployment config
```

---

## 5. Notable Engineering Highlights

- **End-to-end real-time streaming** across an HTTP boundary — custom SSE protocol with word-boundary chunking on the server and an independent typewriter animation engine on the client, decoupling UX smoothness from network behavior.
- **Graceful degradation everywhere** — model fallback, rate-limit backoff, MongoDB→JSON fallback, and client-side retry on cold-start handshake drops.
- **Security-conscious by design** — input validation, rate limiting, CORS allow-listing, body-size limits, path-traversal protection, and security headers on a public-facing API.
- **Clean architecture** — clear separation of concerns (domain/data/presentation on the client; models/services/routing on the server) with dependency injection and an abstract repository interface.
- **Multimodal AI** — image and document understanding via Gemini, with client-side image optimization to keep payloads small.
- **True cross-platform** — one Flutter codebase targeting Android, iOS, Web, and Windows.

---

## 6. Resume Bullet Points (ready to paste)

**Zenith AI — Full-Stack Streaming AI Chat Application** · *Flutter, Python, FastAPI, Google Gemini, MongoDB*

- Built a cross-platform (Android/iOS/Web/Windows) AI chat client in **Flutter** with the **BLoC** pattern and a clean domain/data/presentation architecture, featuring real-time streaming responses, conversation history, and multimodal (image/PDF) input.
- Designed a **FastAPI** backend that streams Google **Gemini** responses **token-by-token over Server-Sent Events**, implementing word-boundary chunking and a client-side typewriter engine for a smooth, network-independent typing effect.
- Implemented **conversation persistence** with async **MongoDB (Motor)** plus a transparent local-JSON fallback, and **AI-generated conversation titles**.
- Hardened the public API with per-IP **rate limiting**, **CORS allow-listing**, request-size limits, security headers, **Pydantic validation**, and path-traversal protection.
- Added resilience via **model fallback** (Gemini 2.5→2.0), **exponential backoff** on rate limits, retry-on-cold-start handshake drops, and a keep-alive task to mitigate free-tier spin-down on **Render**.
- Integrated **speech-to-text** and **text-to-speech**, **Markdown** rendering, and client-side **image optimization** for multimodal AI requests.

---

*Generated as a project summary covering both the Flutter frontend and the FastAPI/Gemini backend.*
