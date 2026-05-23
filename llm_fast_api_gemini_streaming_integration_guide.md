# Chat Stream API – Frontend Integration Guide

This document explains ONLY what frontend developers need to know to integrate the streaming chat UI.

---

# What Backend Does

The backend provides an AI chat streaming API using Gemini LLM.

Flow:

User message → FastAPI backend → Gemini LLM → tokens streamed → frontend receives text gradually

The backend:

1. Receives chat message from frontend
2. Sends prompt to Gemini AI model
3. Receives response token-by-token
4. Streams tokens using SSE (Server Sent Events)
5. Sends partial text continuously to frontend

The frontend should NOT wait for full response.
Instead, it should append incoming text chunks to the UI.

---

# Streaming Chat API Endpoint

## POST /chat-stream

### URL

http://127.0.0.1:8000/chat-stream

---

# Request Body

Content-Type: application/json

```
{
  "messages": [
    {
      "role": "user",
      "content": "Explain Flutter Bloc simply"
    }
  ]
}
```

---

# Response Type

Content-Type:

text/event-stream

The response is streamed incrementally.

Example stream received by frontend:

```
data: Flutter Bloc is 


data: a state management 


data: solution used in Flutter
```

Frontend must:

• listen to stream
• remove "data: " prefix
• append text continuously
• update UI live

---

# Expected Frontend Behaviour

1. Send POST request to /chat-stream
2. Keep connection open
3. Listen to incoming chunks
4. Append each chunk to message text
5. Display typing effect in chat UI

---

# Message Object Format

```
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

# Example Flutter Flow

send message → call /chat-stream → receive chunks → append text → rebuild UI

---

# Summary

Endpoint:
POST /chat-stream

Protocol:
SSE streaming

Frontend responsibility:
render text incrementally

Backend responsibility:
stream AI generated text

---

