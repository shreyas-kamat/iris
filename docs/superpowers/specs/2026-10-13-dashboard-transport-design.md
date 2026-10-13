# Dashboard transport — design

**Date:** 2026-10-13
**Status:** approved direction (user decisions below); Phase 1 of the Conduit-parity roadmap.

## Why

Iris was first built against hermes-webui (REST + SSE). The feature-parity target,
Hermes Conduit (github.com/kaishi00/hermes-conduit, MIT), talks to Hermes Agent's own
**native dashboard** instead, and nearly every Conduit feature — profiles, projects,
groups, bots, Kanban, cron runs, mid-turn steering, model switching, capabilities —
exists only there. The user decided:

1. Iris speaks **only** the native dashboard protocol. hermes-webui support is removed.
2. Iris targets **Android and iOS phones/tablets**. No Watch, Wear OS, CarPlay, Android Auto.
3. The reference server is `https://hermes.shreyaskamat.in`.

Phase 1 replaces the transport and sign-in. It ends when Iris holds a live, authenticated,
self-healing connection to that server and shows its state. Chat is Phase 2.

## What the reference server actually does (probed 2026-10-13)

Every path, including `/api/*` and `/api/ws`, answers an anonymous request with
`302` to `https://<team>.cloudflareaccess.com/cdn-cgi/access/login/...` and the header
`Www-Authenticate: Cloudflare-Access ...`. **Cloudflare Access sits in front of the whole
host.** A native client cannot complete Access's browser login on its own HTTP and
WebSocket requests, so Iris must send an Access **service token** on every request:

```
CF-Access-Client-Id: <id>.access
CF-Access-Client-Secret: <secret>
```

These are sent over HTTPS/WSS only, never cleartext (Conduit's rule). The server owner must
create a service token in Cloudflare Zero Trust and add a *Service Auth* policy for it to the
application. Without that, nothing below is reachable.

## Protocol (from Conduit's source, `Conduit/Services/{HermesClient,NativeAuthClient}.swift`)

### Discovery and sign-in (REST, cookie session)

| Step | Request | Answer |
|---|---|---|
| Provider discovery | `GET /api/auth/providers` | `{"providers":[{"name":"basic","supports_password":true}, ...]}`. `[]` = no auth configured. A 3xx = browser-only sign-in. Non-JSON 2xx = not a Hermes dashboard. |
| Version | `GET /api/status` (public) | `{"version": "...", "auth_flows": [...], "gateway_running": bool, ...}` |
| Password login | `POST /auth/password-login` `{"provider":"basic","username":u,"password":p}` | 2xx (or a same-origin redirect) plus a session `Set-Cookie` |
| WebSocket ticket | `POST /api/auth/ws-ticket` with the session cookie | `{"ticket":"..."}`. **Single-use: mint a fresh one for every connect.** 401/redirect = the session expired. |

Native OAuth (PKCE via `/auth/native/*`) exists but is **out of scope for Phase 1**. A
dashboard that offers only OAuth providers is reported as unsupported for now.

### Live connection (WebSocket, JSON-RPC 2.0)

- URL: `wss://<host>/api/ws?ticket=<ticket>` (`ws://` for an `http://` dashboard).
- **Text frames only.** The gateway does not dispatch binary JSON-RPC frames.
- Client → server request: `{"jsonrpc":"2.0","id":<int>,"method":"...","params":{...}}`;
  `params` is omitted when empty.
- Server → client response: `{"id":<int>,"result":...}` or
  `{"id":<int>,"error":{"code":<int>,"message":"...","data":{"reason":"..."}}}`.
  `data.reason` is machine-readable (for example `SESSION_NOT_OWNED`).
- Server → client event: `{"jsonrpc":"2.0","method":"event","params":{"type":"message.delta","session_id":"...","payload":{...}}}`.
  The first event on a socket is `gateway.ready`.
- Server → client request: has both `method` (≠ `"event"`) and a **string** id (`srq-<hex>`).
  Examples: `approval`, `clarify`, `sudo`, `secret`. A client with no UI for one declines it
  at once with `{"jsonrpc":"2.0","id":"srq-…","error":{"code":-32601,"message":"..."}}`, so
  the tool fails fast instead of waiting out its deadline. Phase 1 declines everything and
  does **not** send `client.capabilities {server_requests:true}`; Phase 2 adds both when it
  has approval and clarify cards.
- Liveness: RPC `ping`. A "method not found" error (code `-32601`, or a message containing
  "method not found" / "unknown method" / "no such method") also proves the socket alive.
- Default RPC timeout is 30s; `prompt.submit` is 180s (Phase 2).
- Reconnect backoff: `min(5, 2^attempt)` seconds, with a fresh ticket each time.

## Architecture

```
features/servers/connect_screen.dart    address → [access token] → [login] → join
features/home/link_status_screen.dart   Phase 1 home: link state, version, capabilities
app/providers.dart                      active session, link state, server state
data/repositories/server_repository.dart  servers, secrets, connections, sessions
data/net/
  api_client.dart        Dio; adds the Access headers on https; classifies redirects
  server_connection.dart one cookie jar + ApiClient per server
  dashboard_auth.dart    probe / signIn / mintTicket
  credentials.dart       ServerSecrets in the platform keystore
  capabilities.dart      dashboard REST feature probe
data/rpc/
  rpc_frame.dart         parse/encode JSON-RPC frames (pure Dart)
  wire_socket.dart       WebSocket seam (dart:io in production, fake in tests)
  rpc_client.dart        request/response matching, events, declines, timeouts
  dashboard_session.dart ticket → socket → live, re-login, backoff, fresh ticket each time
```

Unchanged rules: nothing throws past the data layer (`Result<T>` / `IrisFailure`), all wire
reads go through tolerant `Json`, and every secret stays out of logs (`IrisLog.redact`).

New failure kind: `FailureKind.accessGate`. An access proxy stopped the request before Hermes
saw it. The fix is a service token, not a password, so it is distinct from `unauthorized`.

## Removed

`data/net/session_auth.dart`, `data/sse/*`, `data/models/stream_event.dart` and their tests.
The webui wire models in `data/models/{session,catalog,cron_job}.dart` stay for Phase 2 to
rework.

## Out of scope (later phases)

Chat and transcript (Phase 2), approval/clarify UI, profiles, native OAuth, push, voice,
widgets, localisation.
