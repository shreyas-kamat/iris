# Chat (Phase 2): design

**Date:** 2026-10-13
**Status:** approved direction; Phase 2 of the Conduit-parity roadmap. It builds on Phase 1's
dashboard transport (`docs/superpowers/specs/2026-10-13-dashboard-transport-design.md`).

## Goal

Iris becomes a usable chat client for the user's Hermes dashboard, at `https://hermes.shreyaskamat.in`:

- list the conversations on the server
- open one and read its stored transcript
- send a message and watch the reply stream in, including tool calls
- stop a running turn
- answer the agent's approval requests and clarifying questions

## What the server actually sends

Probed read-only against Hermes 0.18.2 on 2026-10-13. Only field names and types were printed.

**`session.list` (RPC).** Returns `{"sessions": [{id, title, preview, started_at, message_count, source}]}`,
with 200 rows. `id` is the stored session id. `started_at` is fractional epoch seconds. `source` is a
value such as `"telegram"`.

**`GET /api/sessions/{id}/messages?limit=120&offset=0&order=latest&include_compacted=true` (REST, uses the session
cookie).** Returns `{"session_id", "messages": [...], "pagination": {limit, offset, returned}}`. The rows come
in chronological order. Each row has:
- `id` (int), `role` (`user` | `assistant` | `tool`), `content` (**string**), `timestamp` (double)
- `tool_call_id` and `tool_name` (on `tool` rows)
- `tool_calls` (on `assistant` rows): a list of
  `{id, call_id, type: "function", function: {name, arguments: <JSON text>}}`
- `reasoning` / `reasoning_content` (strings or null)
- `active`, `compacted`, `observed` (ints)

**Live events.** These are not probed yet, because probing means sending a real prompt. Their shapes
follow Conduit's `StreamEventParser.swift`, which tracks every spelling Hermes has used. All of them
arrive as `{"method": "event", "params": {"type", "session_id", "payload"}}`, and `session_id` is
the **runtime** id:

| type | payload |
|---|---|
| `message.start` | (none) |
| `message.delta` | `text` |
| `reasoning.delta` (also `message.reasoning`, `message.reasoning.delta`) | `reasoning`, `reasoning_content`, `text` or `content` |
| `message.complete` | `content` / `text` / `rendered`, and `reasoning` |
| `tool.start` (also `tool_call`) | `tool_id` / `tool_call_id` / `call_id`, `name`, `args_text` / `context` / `input` / `arguments` / `args` |
| `tool.complete` (also `tool_result`) | the same ids, plus `name` and `output` / `result` |
| `error` | `message` |
| `message.interrupted`, `session.interrupted` | (none) |
| `session.busy` | `busy` |
| `session.title` | `title` |
| `approval.request` | `request_id`, `command`, `description`, `choices`, `allow_permanent` |
| `clarify.request` | `request_id`, `question`, `choices`, or `questions[]` |
| `clarify.expire` | `request_id` |
| `request.cancel` | `id`, `method`, `reason` |

**Server requests.** A client that sends `client.capabilities {"server_requests": true}` gets approvals and
clarifying questions as server requests (string id `srq-…`):
- `approval` has params `{session_id, request_id (queue id), command, description, choices, allow_permanent}`. It is
  answered with the RPC `approval.respond {choice, session_id, request_id}`. The gateway then withdraws the server
  request itself, so no response frame is written.
- `clarify` has params `{session_id, question, choices}` or `{session_id, questions: [{qid, question, choices}]}`.
  - A single question is answered with a **result frame** `{"id": "srq-…", "result": {"answer": …}}`.
  - Each question of a batch is answered with the RPC `clarify.lock {request_id, question_id, answer}`.
  - A legacy `clarify.request` event is answered with the RPC `clarify.respond {request_id, answer[, question_id]}`.
- Every other method stays declined (Phase 1 behaviour).

**Conversation lifecycle.**
- `session.resume {session_id: <stored>, cols: 96, source: "desktop", omit_messages: true}` attaches to a stored
  conversation. Its result carries the runtime `session_id`, `running`, and `open_requests: [{id, method, params}]`,
  which are the decisions still waiting.
- `session.create {cols: 96, source: "desktop"}` returns `{session_id, stored_session_id}`.
- `prompt.submit {session_id: <runtime>, text}` (180 s timeout) answers `{"status": "streaming"}`. The reply
  arrives as events.
- `session.interrupt {session_id: <runtime>}` stops a turn.

## Architecture

```
data/rpc/rpc_client.dart        + presented server requests, result replies
data/rpc/dashboard_session.dart + serverRequests stream, replyToServerRequest, client.capabilities on gateway.ready
data/chat/chat_models.dart      ConversationSummary, TranscriptItem (UserTurn, AssistantTurn, ToolCall, Notice),
                                ApprovalRequest, ClarifyRequest/Question/Choice
data/chat/history_parser.dart   session.list rows and /messages rows → models
data/chat/chat_event.dart       RpcEvent / RpcServerRequest → sealed ChatEvent
data/chat/chat_backend.dart     ChatBackend (the seam) + DashboardChat (RPC + REST)
features/chat/chat_state.dart   immutable ChatState + pure apply(ChatEvent)
features/chat/chat_controller.dart  ValueNotifier<ChatState>: open, send, stop, approve, answer
features/chat/relative_time.dart
features/chat/transcript_view.dart, decision_cards.dart, composer.dart
features/chat/chat_screen.dart
features/chat/conversation_list_screen.dart   the new home; its header opens the Phase 1 link status screen
app/providers.dart              + activeChatProvider, conversationsProvider
```

The transcript is in memory only. Nothing is cached in Drift yet.

## Out of scope (later phases)

- Markdown rendering. Text is shown as plain selectable text.
- Attachments, model switching, slash commands, steering, branching, renaming, archiving, profiles and search.
- Paging back past the newest 120 rows.
- Offline cache, push notifications, voice.

Two Phase 2 limitations to note:
- `sudo`, `secret` and other input prompts are still declined.
- Approvals for a conversation that has no open screen wait until another client answers them, or until the
  gateway's deadline.
