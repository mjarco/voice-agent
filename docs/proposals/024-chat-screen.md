# Proposal 024 — Chat Screen

## Status: Stub

## Prerequisites
- P020 (Navigation Restructure) — provides /chat route placeholder
- personal-agent chat + conversation endpoints — must be deployed

## Scope
- Tasks: ~5
- Layers: features/chat (new), core/models, core/network
- Risk: Medium — SSE streaming adds complexity; mic integration reuses recording infra

---

## Problem Statement

Voice-agent is input-only: users record voice, see a brief agent reply, but cannot have a persistent text conversation with the agent. The personal-agent web UI offers a full chat interface with streaming responses, model selection, and inline knowledge extraction display. Bringing chat to mobile lets users interact with their agent via text when voice isn't appropriate (meetings, public transport, late at night).

## Design Direction

### Conversation list (`/chat`)

```
[App Bar: "Chat"  | + new chat | gear]

[Conversation list]
  "Planning May trip"           3 messages    2h ago
  "Weekly groceries"            5 messages    yesterday
  "Q2 budget review"            12 messages   3d ago
```

### Conversation thread (`/chat/:id`)

```
[App Bar: "Planning May trip"  | model selector]

[Messages — scrollable]
  User: I need to plan the May trip to Italy
  Agent: I've noted some action items for the trip...
    [badge: action_item "Book flights"]  [star]
    [badge: question "Which dates?"]

  User: Dates are May 15-22
  Agent: Updated. Here's what I'm tracking:
    [badge: decision "May 15-22 trip dates"]  [star]

[Input bar: [text field] [mic btn] [send btn]]
```

### API endpoints consumed
- `GET /api/v1/conversations` — list conversations
- `GET /api/v1/conversations/{id}/events` — get messages
- `GET /api/v1/conversations/{id}/records` — get extracted knowledge
- `POST /api/v1/chat/stream` — send message, receive SSE stream
- `POST /api/v1/chat/cancel` — cancel in-progress response
- `GET /api/v1/chat/models` — available LLM models
- `POST /api/v1/records/{id}/endorse` — toggle star on extracted record

### Key interactions
- Tap conversation → open thread
- New chat button → create fresh conversation
- Mic button in input → voice recording (reuse RecordingController for STT)
- Send → SSE streaming response with real-time text rendering
- Extracted knowledge records shown inline as tappable badges
- Model selector dropdown in thread app bar
- Cancel button appears during streaming response
- Pull down to load older messages (if conversation is long)

### Technical notes
- SSE client for streaming (`POST /chat/stream` returns Server-Sent Events)
- Reuse `RecordingController` + `SttService` for mic-to-text in chat input
- Conversation state persisted server-side; client is a thin view
- Knowledge records fetched per-conversation for inline display

## Tasks (rough)
1. Core models: Conversation, ChatEvent, ChatMessage
2. API client: conversation + chat endpoint methods, SSE stream client
3. Conversation list: feature shell with list screen + controller
4. Conversation thread: message display + streaming + knowledge badges
5. Voice input in chat: integrate mic button with existing RecordingController
