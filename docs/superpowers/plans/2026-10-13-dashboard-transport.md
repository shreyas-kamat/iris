# Dashboard Transport (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Iris's hermes-webui transport with the native Hermes dashboard protocol, so Iris signs in through Cloudflare Access plus the dashboard login, holds a live JSON-RPC WebSocket that heals itself, and shows that state on screen.

**Architecture:** REST (Dio + a per-server cookie jar) handles discovery, password login and minting a single-use WebSocket ticket. A `dart:io` WebSocket behind a `WireSocket` seam carries JSON-RPC 2.0. `RpcClient` matches responses to requests, forwards events and declines server requests. `DashboardSession` owns the link lifecycle: a fresh ticket per connect, re-login on expiry, backoff on drops, and a hard stop on access-proxy or TLS failures. `ServerRepository` owns servers, secrets, connections and sessions. Riverpod providers expose the link state to a new Phase 1 home screen.

**Tech Stack:** Flutter 3.41.6 / Dart 3.11, flutter_riverpod 3.3, dio 5.11 + dio_cookie_manager, drift 2.34, flutter_secure_storage 11, `dart:io` WebSocket (no new dependency).

**Spec:** `docs/superpowers/specs/2026-10-13-dashboard-transport-design.md` (protocol facts, decisions, scope). Reference implementation: `github.com/kaishi00/hermes-conduit` (MIT), files `Conduit/Services/HermesClient.swift`, `NativeAuthClient.swift`, `CloudflareAccess.swift`.

## Global Constraints

- Mobile only: Android and iOS. `dart:io` is allowed everywhere in `lib/data`.
- Nothing throws past `lib/data`: public data-layer APIs return `Result<T>` / `IrisFailure`, except `Future<void>` lifecycle methods (`dispose`, `close`, `release`).
- All wire reads go through `Json` (`lib/core/json.dart`); never cast decoded JSON directly.
- No secret ever reaches a log, an exception message or `toString()`: passwords, cookies, Access client secrets, WebSocket tickets.
- Cloudflare Access headers (`CF-Access-Client-Id`, `CF-Access-Client-Secret`) are sent **only** over `https`/`wss`.
- Mint a fresh WebSocket ticket for **every** connect; never reuse one.
- WebSocket frames are **text** frames; JSON-RPC `params` is omitted when empty.
- Reconnect backoff: `min(5, 2^attempt)` seconds; never retry `accessGate` or `tls` failures automatically.
- `flutter analyze` must print `No issues found!` and `flutter test` must print `All tests passed!` at the end of every task.
- Match the existing code style: library doc comment at the top of each file, `///` docs explaining *why*, single quotes, relative imports inside `lib/`, `package:iris/...` imports in `test/`.
- Commit messages end with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Re-selecting the same server must not restart the link.** A capability refresh writes to the `servers` table, which re-emits `serversProvider`. If `activeServerProvider` notified on that, the session would be torn down and rebuilt in a loop. Pinned by the Task 10 test "a capability refresh does not reopen the socket".
2. **A token that Cloudflare rejects must read as "token rejected", not "token needed".** The probe returns `accessGate` in both cases. Pinned by the Task 11 test "a rejected token says so".
3. **A dropped socket must never reuse its ticket.** Pinned by the Task 8 test "a dropped socket reconnects with a new ticket".
4. **Access secrets must never go over cleartext**, including the WebSocket upgrade to an `http://` LAN dashboard. Pinned by Task 4 "the Access token is never sent over http" and Task 8 "never sends the Access token over ws://".
5. **A server answering for a different session store must not throw.** An unreadable or HTML 200 body from discovery has to classify as `notHermes`, not crash. Pinned by the Task 5 test "an HTML page is not a dashboard".

## Executor protocol (read before Task 0)

**Environment.** Windows 11, project root `D:\Projects\Flutter\iris`. The commands in this plan are POSIX `sh`. Run them with the **Bash** tool (Git Bash), using `/d/Projects/Flutter/iris` or `D:/Projects/Flutter/iris` paths. Do not use PowerShell for them. `flutter` and `git` are on PATH. Run every `flutter` command from the project root.

**How to work through a task.**
1. Do the steps in order. Copy code blocks **exactly**: same names, same doc comments, same file paths. Do not rename, restructure, "improve", or add features, files or dependencies the plan does not list.
2. "Expected: FAIL" steps exist to prove the test is new. If such a test passes, or fails for a different reason than the one stated, note it in your report and carry on.
3. When a step says "replace X with Y", find X by its text, not its line number. Line numbers are hints. If X is not found verbatim, use **Read** on the file, apply the obvious equivalent edit, and record it as a deviation.
4. Before each commit, run `flutter analyze` and `flutter test` and read the output. The summary lines must be `No issues found!` and `All tests passed!`. **Never** pipe these commands through `tail` or `head`, because a pipe hides the exit code. To shorten long output, use `flutter test 2>&1 | grep -E "All tests passed|Some tests failed|\[E\]|Error:" ; echo EXIT=${PIPESTATUS[0]}`.

**When something goes wrong.**
- *Analyzer lint or warning* in code you just wrote or touched (unused import, `prefer_const`, missing doc comment, and so on): fix it minimally. This is expected. For example, removing a class can leave an unused import behind.
- *Analyzer error or failing test* caused by the plan's own code: diagnose it, then make the **smallest** fix that keeps the plan's interfaces (the **Interfaces** block of each task) unchanged. Record the fix as a deviation in your report: the file, what you changed and why.
- *The fix would change a public name, signature or behaviour that a later task uses*, or you have tried two fixes and both failed: **stop**. Do not commit, leave the files as they are, and report exactly what fails (the error text plus the relevant code).
- Never weaken, skip or delete a test just to make the suite pass. Never use `// ignore:` to silence an analyzer error.
- Never run `git reset --hard`, `git checkout -- .`, `git clean`, `rm -rf`, or `flutter clean`.

**Commits.** One commit per task, with exactly the message the task gives, including the `Co-Authored-By` trailer. Stage only the files the task names, plus any files you changed for a recorded deviation. Use a heredoc or `-m` with an embedded newline as shown. Do not amend earlier commits.

**Secrets.** Never print, log, write into the repo, or echo the contents of `~/.iris-live.json` or any credential.

**Report after each batch.** For each task: done or stopped; the commit hash (`git log --oneline -1`); the final `flutter analyze` and `flutter test` summary lines; and every deviation from the plan (the file, what changed and why). Be terse and factual, and paste no full files.

---

### Task 0: Put the project under version control

The project is not a git repository. Every later task commits, so create the baseline first.

**Files:**
- Modify: none (repository metadata only)

- [ ] **Step 1: Check what would be committed**

Run: `git -C D:/Projects/Flutter/iris status 2>&1 | head -3`
Expected: `fatal: not a git repository`

Run: `cat D:/Projects/Flutter/iris/.gitignore`
Expected: contains `/build/` and `.dart_tool/`. If either is missing, append it before committing.

- [ ] **Step 2: Initialise and commit the baseline**

```bash
cd D:/Projects/Flutter/iris
git init -b main
git add -A
git status --short | grep -E '^A.*(build/|\.dart_tool/)' && echo "STOP: build output staged" || echo "ok"
git commit -m "chore: baseline before the dashboard transport

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: `ok`, then a root commit.

---

### Task 1: Access-gate failures and secret redaction

**Files:**
- Modify: `lib/core/failure.dart`
- Modify: `lib/core/logging.dart:107-122`
- Test: `test/core/logging_test.dart` (create)

**Interfaces:**
- Produces: `FailureKind.accessGate`; `IrisLog.redact` now also strips `ticket=` query values, `"ticket"` JSON fields and `CF-Access-Client-Secret` header values.

- [ ] **Step 1: Write the failing tests**

Create `test/core/logging_test.dart`:

```dart
/// Secrets the dashboard transport introduces must never reach a log.
///
/// A WebSocket ticket is a short-lived bearer credential embedded in a URL, and
/// an Access client secret is a long-lived one sent as a header. Both appear in
/// exception messages from the HTTP and socket layers, which are logged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/logging.dart';

void main() {
  group('redaction', () {
    test('a websocket ticket in a URL is removed', () {
      final out = IrisLog.redact(
        "Connection to 'wss://h.example/api/ws?ticket=abc123def' failed",
      );
      expect(out, isNot(contains('abc123def')));
      expect(out, contains('ticket=<redacted>'));
    });

    test('a ticket in a JSON body is removed', () {
      expect(
        IrisLog.redact('{"ticket":"abc123def"}'),
        '{"ticket":"<redacted>"}',
      );
    });

    test('a Cloudflare Access secret header is removed', () {
      final out = IrisLog.redact('CF-Access-Client-Secret: s3cr3tvalue');
      expect(out, isNot(contains('s3cr3tvalue')));
    });
  });

  group('access gate failures', () {
    test('are connection level and not retryable', () {
      const failure = IrisFailure(FailureKind.accessGate);
      expect(failure.isConnectionLevel, isTrue);
      expect(failure.isRetryable, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/logging_test.dart`
Expected: compile error `Member not found: 'accessGate'`.

- [ ] **Step 3: Add the failure kind**

In `lib/core/failure.dart`, insert after the `unauthorized,` entry:

```dart
  /// An access proxy in front of the server — Cloudflare Access — turned the
  /// request away before Hermes saw it. Fixed with a service token, not a
  /// password, so it is kept apart from [unauthorized].
  accessGate,
```

In `isRetryable`, add `FailureKind.accessGate ||` to the `false` arm:

```dart
    FailureKind.tls ||
    FailureKind.unauthorized ||
    FailureKind.accessGate ||
    FailureKind.notFound ||
```

In `isConnectionLevel`, add it to the `true` arm:

```dart
    FailureKind.offline ||
    FailureKind.tls ||
    FailureKind.unauthorized ||
    FailureKind.accessGate => true,
```

- [ ] **Step 4: Extend the redaction table**

In `lib/core/logging.dart`, replace the JSON-field pattern string

```dart
        r'"(password|passwd|secret|token|api_?key|access_?key|authorization|client_secret|refresh_token|session_key)"\s*:\s*"[^"]*"',
```

with

```dart
        r'"(password|passwd|secret|token|ticket|api_?key|access_?key|authorization|client_secret|refresh_token|session_key)"\s*:\s*"[^"]*"',
```

Replace the query-parameter pattern string

```dart
        r'([?&](?:password|token|api_?key|key|secret)=)[^&\s]*',
```

with

```dart
        r"([?&](?:password|token|ticket|api_?key|key|secret)=)[^&\s']*",
```

Insert this entry directly after the cookie-header entry (after line 106):

```dart
    // Cloudflare Access service-token secret, as a header.
    (
      RegExp(r'(cf-access-client-secret)\s*[:=]\s*\S+', caseSensitive: false),
      r'$1: <secret>',
    ),
```

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test test/core/logging_test.dart`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/failure.dart lib/core/logging.dart test/core/logging_test.dart
git commit -m "feat(core): access-gate failure kind and ticket/Access-secret redaction

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Server secrets in the keystore

The keystore now holds a username, a password and an optional Access service token per server, written and erased as one unit.

**Files:**
- Modify: `lib/data/net/credentials.dart` (rewrite)
- Modify: `lib/data/repositories/server_repository.dart` (two call sites)
- Create: `test/support/fakes.dart`
- Modify: `test/data/server_repository_test.dart` (use the shared fake)
- Test: `test/data/credentials_test.dart` (create)

**Interfaces:**
- Produces:
  - `final class ServerSecrets { const ServerSecrets({String? username, String? password, String? accessClientId, String? accessClientSecret}); static const none; bool get hasLogin; bool get hasAccessToken; bool get isEmpty; Map<String, String> get accessHeaders; Map<String, Object?> toJson(); factory ServerSecrets.fromJson(Json json); }`
  - `abstract interface class CredentialStore { Future<Result<ServerSecrets>> read(String serverId); Future<Result<void>> write(String serverId, ServerSecrets secrets); Future<void> delete(String serverId); Future<void> deleteAll(); }`
  - Test fake `FakeCredentialStore` with `final Map<String, ServerSecrets> entries`.

- [ ] **Step 1: Write the failing tests**

Create `test/support/fakes.dart`:

```dart
/// In-memory stand-ins for platform services, shared across tests.
library;

import 'package:iris/core/result.dart';
import 'package:iris/data/net/credentials.dart';

/// An in-memory credential store, so tests never touch the real keystore.
final class FakeCredentialStore implements CredentialStore {
  final Map<String, ServerSecrets> entries = {};

  @override
  Future<Result<ServerSecrets>> read(String serverId) async =>
      Ok(entries[serverId] ?? ServerSecrets.none);

  @override
  Future<Result<void>> write(String serverId, ServerSecrets secrets) async {
    entries[serverId] = secrets;
    return const Ok(null);
  }

  @override
  Future<void> delete(String serverId) async {
    entries.remove(serverId);
  }

  @override
  Future<void> deleteAll() async => entries.clear();
}
```

Create `test/data/credentials_test.dart`:

```dart
/// What a server's secrets look like, and that they never print themselves.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/net/credentials.dart';

void main() {
  const full = ServerSecrets(
    username: 'me',
    password: 'pw',
    accessClientId: 'abc.access',
    accessClientSecret: 'shh',
  );

  test('round-trips through JSON', () {
    expect(ServerSecrets.fromJson(Json.of(full.toJson())), full);
  });

  test('toString never contains a value', () {
    final text = full.toString();
    for (final secret in ['me', 'pw', 'abc.access', 'shh']) {
      expect(text, isNot(contains(secret)));
    }
  });

  test('a login needs both a username and a password', () {
    expect(const ServerSecrets(username: 'me').hasLogin, isFalse);
    expect(const ServerSecrets(password: 'pw').hasLogin, isFalse);
    expect(full.hasLogin, isTrue);
  });

  test('an Access token needs both halves, and yields both headers', () {
    expect(const ServerSecrets(accessClientId: 'a').hasAccessToken, isFalse);
    expect(full.accessHeaders, {
      'CF-Access-Client-Id': 'abc.access',
      'CF-Access-Client-Secret': 'shh',
    });
    expect(ServerSecrets.none.accessHeaders, isEmpty);
  });
}
```

In `test/data/server_repository_test.dart`:
- Delete the whole `FakeSecureStorage` class (lines 19-39) and its doc comment.
- Add the import `import '../support/fakes.dart';` after the `package:iris/...` imports.
- Replace `late FakeSecureStorage credentials;` with `late FakeCredentialStore credentials;` and `credentials = FakeSecureStorage();` with `credentials = FakeCredentialStore();`.
- In `seedServer`, replace `if (password != null) await credentials.write(id, password);` with `if (password != null) await credentials.write(id, ServerSecrets(password: password));`.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/credentials_test.dart`
Expected: compile error `Type 'ServerSecrets' not found`.

- [ ] **Step 3: Rewrite `lib/data/net/credentials.dart`**

```dart
/// Where a server's secrets live.
///
/// Not in the database, not in shared preferences, and not a field on the
/// server config that gets passed around and logged. Secrets go to the platform
/// keystore and come back out only at the moment a request needs them.
///
/// The separation is deliberate: a server config is a value object that travels
/// freely through providers, gets printed in diagnostics, and may end up in a
/// crash report. If a password were a field on it, every one of those paths
/// would become a leak.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';

/// Everything secret about one server, kept together so it is written and
/// erased as a unit.
@immutable
final class ServerSecrets {
  const ServerSecrets({
    this.username,
    this.password,
    this.accessClientId,
    this.accessClientSecret,
  });

  factory ServerSecrets.fromJson(Json json) => ServerSecrets(
    username: json['username'].stringOrNull,
    password: json['password'].stringOrNull,
    accessClientId: json['access_client_id'].stringOrNull,
    accessClientSecret: json['access_client_secret'].stringOrNull,
  );

  /// Nothing stored: an open dashboard on a private network.
  static const none = ServerSecrets();

  /// The Hermes dashboard login.
  final String? username;
  final String? password;

  /// A Cloudflare Access service token, for a dashboard published behind
  /// Access. A native app cannot complete Access's browser login on its own
  /// requests, so the token is the only way through.
  final String? accessClientId;
  final String? accessClientSecret;

  bool get hasLogin => _filled(username) && _filled(password);

  bool get hasAccessToken =>
      _filled(accessClientId) && _filled(accessClientSecret);

  bool get isEmpty => !hasLogin && !hasAccessToken;

  static bool _filled(String? value) =>
      value != null && value.trim().isNotEmpty;

  /// The two headers Cloudflare Access reads, or none without a token.
  ///
  /// Callers decide whether the transport is encrypted; see
  /// `ServerConnection.accessHeadersFor`.
  Map<String, String> get accessHeaders => hasAccessToken
      ? {
          'CF-Access-Client-Id': accessClientId!.trim(),
          'CF-Access-Client-Secret': accessClientSecret!.trim(),
        }
      : const {};

  Map<String, Object?> toJson() => {
    'username': username,
    'password': password,
    'access_client_id': accessClientId,
    'access_client_secret': accessClientSecret,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerSecrets &&
          other.username == username &&
          other.password == password &&
          other.accessClientId == accessClientId &&
          other.accessClientSecret == accessClientSecret);

  @override
  int get hashCode =>
      Object.hash(username, password, accessClientId, accessClientSecret);

  /// Never prints a value: this object ends up in test failures and, through
  /// careless string interpolation, potentially in logs.
  @override
  String toString() =>
      'ServerSecrets(login: $hasLogin, accessToken: $hasAccessToken)';
}

/// Reads and writes server secrets.
///
/// An interface rather than a concrete class so tests can substitute an
/// in-memory store. The alternative - tests touching the real platform keystore
/// - either fails in CI where no keystore exists, or leaves credentials on the
/// machine that ran them.
abstract interface class CredentialStore {
  /// [serverId]'s secrets, or [ServerSecrets.none] if nothing is stored.
  Future<Result<ServerSecrets>> read(String serverId);

  /// Replaces [serverId]'s secrets. Writing [ServerSecrets.none] deletes them.
  Future<Result<void>> write(String serverId, ServerSecrets secrets);

  /// Removes [serverId]'s secrets.
  Future<void> delete(String serverId);

  /// Removes every Iris secret.
  Future<void> deleteAll();

  /// The platform keystore.
  factory CredentialStore.platform() = SecureCredentialStore.platform;
}

/// The real store, backed by the platform keystore.
final class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore(this._storage);

  /// Uses each platform's strongest backing.
  ///
  /// Android's defaults in flutter_secure_storage 11 are already AES-GCM with
  /// RSA-OAEP key wrapping in the hardware keystore, so no options are passed.
  ///
  /// iOS is pinned to `first_unlock_this_device`: the secret is readable after
  /// the first unlock following a boot, and never leaves this device. Without
  /// `ThisDevice` it would sync to iCloud Keychain, putting a password for a
  /// machine on the user's home network into Apple's cloud, which is the
  /// opposite of what a self-hosted app is for.
  const SecureCredentialStore.platform()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  static const _log = IrisLog('credentials');

  /// Every key Iris owns starts with this, including the pre-dashboard
  /// `iris.server.password.<id>` keys, so [deleteAll] clears those too.
  static const _prefix = 'iris.server.';

  final FlutterSecureStorage _storage;

  String _keyFor(String serverId) => '${_prefix}secrets.$serverId';

  @override
  Future<Result<ServerSecrets>> read(String serverId) async {
    try {
      final raw = await _storage.read(key: _keyFor(serverId));
      if (raw == null) return const Ok(ServerSecrets.none);
      return Ok(ServerSecrets.fromJson(Json.decode(raw)));
    } on Object catch (error, stackTrace) {
      // A keystore read can fail on a device whose secure hardware is in a bad
      // state. Reported rather than thrown, so the user is asked to sign in
      // again instead of being locked out of the app.
      _log.warn('keystore read failed for $serverId');
      return Err(
        IrisFailure(
          FailureKind.unknown,
          message: 'Could not read the saved sign-in.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> write(String serverId, ServerSecrets secrets) async {
    if (secrets.isEmpty) {
      await delete(serverId);
      return const Ok(null);
    }
    try {
      await _storage.write(
        key: _keyFor(serverId),
        value: jsonEncode(secrets.toJson()),
      );
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      _log.warn('keystore write failed for $serverId');
      return Err(
        IrisFailure(
          FailureKind.unknown,
          message: 'Could not save the sign-in securely.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Removes [serverId]'s secrets, and any pre-dashboard password key.
  ///
  /// Leaving a credential behind for a server the user has deleted is exactly
  /// the kind of residue that makes a privacy-first app untrustworthy.
  @override
  Future<void> delete(String serverId) async {
    try {
      await _storage.delete(key: _keyFor(serverId));
      await _storage.delete(key: '${_prefix}password.$serverId');
    } on Object {
      _log.warn('keystore delete failed for $serverId');
    }
  }

  /// Removes every Iris secret. Used by "forget everything" in Settings.
  @override
  Future<void> deleteAll() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
        await _storage.delete(key: key);
      }
    } on Object {
      _log.warn('keystore bulk delete failed');
    }
  }
}
```

- [ ] **Step 4: Update the repository's two call sites**

In `lib/data/repositories/server_repository.dart`, in `addServer`, replace

```dart
      final stored = await _credentials.write(config.id, password);
```

with

```dart
      final stored = await _credentials.write(
        config.id,
        ServerSecrets(password: password),
      );
```

In `refreshSession`, replace the whole `return switch (stored) { ... };` with

```dart
    return switch (stored) {
      Err(:final failure) => Err(failure),
      Ok(:final value) when value.password == null || value.password!.isEmpty =>
        const Err(
          IrisFailure(
            FailureKind.unauthorized,
            message: 'Sign in to this server again.',
          ),
        ),
      Ok(:final value) => await connectionFor(
        config,
      ).auth.signIn(value.password!),
    };
```

(Task 9 replaces this method entirely; this keeps the build green until then.)

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/net/credentials.dart lib/data/repositories/server_repository.dart test/support/fakes.dart test/data/credentials_test.dart test/data/server_repository_test.dart
git commit -m "feat(data): store login and Access token together as ServerSecrets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Schema v2 — Access token flag and server version

**Files:**
- Modify: `lib/data/db/database.dart`
- Regenerate: `lib/data/db/database.g.dart`
- Modify: `lib/data/net/server_config.dart`
- Modify: `lib/data/repositories/server_repository.dart` (`_toConfig`)
- Test: `test/data/database_migration_test.dart` (create)

**Interfaces:**
- Produces: `Servers.usesAccessToken` (bool, default false), `Servers.serverVersion` (text, nullable); `ServerConfig.usesAccessToken`; schema version 2. On upgrade, webui-era capability probes are cleared.

- [ ] **Step 1: Write the failing test**

Create `test/data/database_migration_test.dart`:

```dart
/// Upgrading a database written by the hermes-webui build.
///
/// Dev installs already hold a v1 `servers` table. The upgrade must add the new
/// columns without losing rows, and must drop the webui capability probe, whose
/// names mean nothing to a dashboard.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/db/database.dart';

void main() {
  test('a v1 database upgrades in place', () async {
    final db = IrisDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
CREATE TABLE servers (
  id TEXT NOT NULL,
  base_url TEXT NOT NULL,
  label TEXT NOT NULL,
  requires_password INTEGER NOT NULL DEFAULT 0 CHECK (requires_password IN (0, 1)),
  allow_self_signed INTEGER NOT NULL DEFAULT 0 CHECK (allow_self_signed IN (0, 1)),
  capabilities_json TEXT NOT NULL DEFAULT '[]',
  probed_at INTEGER NULL,
  last_connected_at INTEGER NULL,
  position INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id)
);''');
          raw.execute(
            "INSERT INTO servers (id, base_url, label, capabilities_json, probed_at) "
            "VALUES ('old', 'https://h.example', 'Old', '[\"crons\"]', 1700000000);",
          );
          raw.execute('PRAGMA user_version = 1;');
        },
      ),
    );
    addTearDown(db.close);

    final row = await db.select(db.servers).getSingle();
    expect(row.label, 'Old');
    expect(row.usesAccessToken, isFalse);
    expect(row.serverVersion, isNull);
    expect(row.capabilitiesJson, '[]');
    expect(row.probedAt, isNull);
  });

  test('a fresh database has the new columns', () async {
    final db = IrisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.servers)
        .insert(
          ServersCompanion.insert(
            id: 'new',
            baseUrl: 'https://h.example',
            label: 'New',
            usesAccessToken: const Value(true),
            serverVersion: const Value('0.9.1'),
          ),
        );
    final row = await db.select(db.servers).getSingle();
    expect(row.usesAccessToken, isTrue);
    expect(row.serverVersion, '0.9.1');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/database_migration_test.dart`
Expected: compile error `The getter 'usesAccessToken' isn't defined`.

- [ ] **Step 3: Add the columns and migration**

In `lib/data/db/database.dart`, in `class Servers`, insert after `allowSelfSigned`:

```dart
  /// Whether a Cloudflare Access service token is stored for this server. The
  /// token itself is in the keystore; this only drives what the UI shows.
  BoolColumn get usesAccessToken =>
      boolean().withDefault(const Constant(false))();

  /// What `/api/status` last reported, for display. Never used to gate a
  /// feature.
  TextColumn get serverVersion => text().nullable()();
```

Replace `int get schemaVersion => 1;` with `int get schemaVersion => 2;` and the `migration` getter with:

```dart
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(servers, servers.usesAccessToken);
        await migrator.addColumn(servers, servers.serverVersion);
        // v1 probed hermes-webui endpoints. Those names mean nothing to a
        // dashboard, so the probe is forgotten and re-run on next connect.
        await customStatement(
          "UPDATE servers SET capabilities_json = '[]', probed_at = NULL",
        );
      }
    },
    beforeOpen: (details) async {
      // Cascading deletes keep a removed server from leaving orphaned sessions
      // and messages behind, which would otherwise accumulate silently.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
```

- [ ] **Step 4: Regenerate drift code**

Run: `dart run build_runner build`
Expected: ends with `Built with build_runner` and `lib/data/db/database.g.dart` is rewritten.

- [ ] **Step 5: Carry the flag on `ServerConfig`**

In `lib/data/net/server_config.dart`:
- Change the library doc's first line to `/// How to reach one Hermes dashboard.`
- Add the constructor parameter `this.usesAccessToken = false,` after `this.requiresPassword = false,`.
- In `fromJson`, add `usesAccessToken: json['uses_access_token'].boolean(),`.
- Add the field after `requiresPassword`:

```dart
  /// Whether requests carry a Cloudflare Access service token.
  final bool usesAccessToken;
```

- In `toJson`, add `'uses_access_token': usesAccessToken,`.
- In `copyWith`, add the parameter `bool? usesAccessToken,` and the argument `usesAccessToken: usesAccessToken ?? this.usesAccessToken,`.
- Change the `requiresPassword` doc to `/// Whether the dashboard wants a username and password.`

In `lib/data/repositories/server_repository.dart`, `_toConfig`, add `usesAccessToken: row.usesAccessToken,`.

- [ ] **Step 6: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/data/db lib/data/net/server_config.dart lib/data/repositories/server_repository.dart test/data/database_migration_test.dart
git commit -m "feat(db): schema v2 with Access-token flag and server version

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: HTTP client for the dashboard

The client sends the Access headers over HTTPS only, does not follow redirects (an Access redirect *is* the answer), and classifies an Access bounce as `accessGate`. `ServerConnection` moves to its own file with an injectable adapter for tests. The old class in `session_auth.dart` stays until Task 12; nothing imports both files.

**Files:**
- Modify: `lib/data/net/api_client.dart`
- Create: `lib/data/net/server_connection.dart`
- Create: `test/support/fake_http.dart`
- Test: `test/data/api_client_test.dart` (create)

**Interfaces:**
- Consumes: `ServerSecrets` (Task 2), `FailureKind.accessGate` (Task 1).
- Produces:
  - `ApiClient({required ServerConfig server, Dio? dio, ServerSecrets secrets = ServerSecrets.none})`; `static bool ApiClient.isAccessGate(int status, {String? location, String? challenge})`. A non-gate 3xx yields `FailureKind.rejected` with `statusCode` 3xx.
  - `final class ServerConnection { factory ServerConnection.create(ServerConfig config, {ServerSecrets secrets = ServerSecrets.none, HttpClientAdapter? adapter}); final ServerConfig config; final ServerSecrets secrets; final ApiClient client; Map<String, String> accessHeadersFor(Uri uri); HttpClient socketHttpClient(); Future<void> clearSession(); void close(); }`
  - Test helpers `FakeHttp` (an `HttpClientAdapter` with `on(method, path, reply)` and `requests`) and `FakeReply` (`FakeReply.json(...)`, `FakeReply.cloudflareLogin()`, `FakeReply.html(...)`).

- [ ] **Step 1: Write the test support**

Create `test/support/fake_http.dart`:

```dart
/// A scripted HTTP server for Dio, so the auth and REST layers are tested
/// against exact responses without a network.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One canned response.
final class FakeReply {
  const FakeReply(
    this.status, {
    this.body = '',
    this.headers = const {},
    this.contentType = 'application/json',
  });

  factory FakeReply.json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => FakeReply(status, body: jsonEncode(body), headers: headers);

  factory FakeReply.html(String body, {int status = 200}) =>
      FakeReply(status, body: body, contentType: 'text/html');

  /// What Cloudflare Access answers to a request without a valid token.
  /// Copied from a real probe of an Access-protected host.
  factory FakeReply.cloudflareLogin() => const FakeReply(
    302,
    body: '<html><body>302 Found</body></html>',
    contentType: 'text/html',
    headers: {
      'location':
          'https://team.cloudflareaccess.com/cdn-cgi/access/login/h.example?kid=x&redirect_url=%2F',
      'www-authenticate':
          'Cloudflare-Access resource_metadata="https://h.example/.well-known/cloudflare-access-protected-resource/"',
    },
  );

  final int status;
  final String body;
  final Map<String, String> headers;
  final String contentType;
}

/// Routes requests by `METHOD /path` to scripted replies and records them.
final class FakeHttp implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, FakeReply Function(RequestOptions request)> _routes = {};

  /// Answers `method path` (path without query) with [reply].
  void on(
    String method,
    String path,
    FakeReply Function(RequestOptions request) reply,
  ) => _routes['$method $path'] = reply;

  /// Requests made to [path], in order.
  List<RequestOptions> to(String path) =>
      requests.where((r) => r.uri.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = _routes['${options.method} ${options.uri.path}'];
    final reply =
        handler?.call(options) ??
        FakeReply.json({'detail': 'Not Found'}, status: 404);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [reply.contentType],
        for (final entry in reply.headers.entries) entry.key: [entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Write the failing tests**

Create `test/data/api_client_test.dart`:

```dart
/// The REST boundary in front of a dashboard that may sit behind Cloudflare
/// Access.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/api_client.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;

  setUp(() => http = FakeHttp());

  ServerConnection connect(
    String baseUrl, {
    ServerSecrets secrets = ServerSecrets.none,
  }) {
    final connection = ServerConnection.create(
      ServerConfig(id: 's', baseUrl: baseUrl, label: 'S'),
      secrets: secrets,
      adapter: http,
    );
    addTearDown(connection.close);
    return connection;
  }

  const token = ServerSecrets(
    accessClientId: 'abc.access',
    accessClientSecret: 'shh',
  );

  test('the Access token rides every https request', () async {
    http.on('GET', '/api/status', (_) => FakeReply.json({'version': '1'}));
    await connect('https://h.example', secrets: token).client.get('/api/status');
    final headers = http.requests.single.headers;
    expect(headers['CF-Access-Client-Id'], 'abc.access');
    expect(headers['CF-Access-Client-Secret'], 'shh');
  });

  test('the Access token is never sent over http', () async {
    http.on('GET', '/api/status', (_) => FakeReply.json({'version': '1'}));
    await connect(
      'http://192.168.1.20:9119',
      secrets: token,
    ).client.get('/api/status');
    final headers = http.requests.single.headers;
    expect(headers.containsKey('CF-Access-Client-Id'), isFalse);
    expect(headers.containsKey('CF-Access-Client-Secret'), isFalse);
  });

  test('an Access login redirect is an access gate, not a success', () async {
    http.on('GET', '/api/status', (_) => FakeReply.cloudflareLogin());
    final result = await connect('https://h.example').client.get('/api/status');
    expect(result.failureOrNull?.kind, FailureKind.accessGate);
    expect(http.requests, hasLength(1), reason: 'redirects are not followed');
  });

  test('any other redirect is a rejection carrying its status', () async {
    http.on(
      'GET',
      '/api/status',
      (_) => const FakeReply(302, headers: {'location': '/login'}),
    );
    final result = await connect('https://h.example').client.get('/api/status');
    expect(result.failureOrNull?.kind, FailureKind.rejected);
    expect(result.failureOrNull?.statusCode, 302);
  });

  test('a FastAPI detail message is surfaced', () async {
    http.on(
      'POST',
      '/auth/password-login',
      (_) => FakeReply.json({'detail': 'Invalid credentials'}, status: 401),
    );
    final result = await connect(
      'https://h.example',
    ).client.post('/auth/password-login', body: {'username': 'x'});
    expect(result.failureOrNull?.kind, FailureKind.unauthorized);
    expect(result.failureOrNull?.message, 'Invalid credentials');
  });

  group('isAccessGate', () {
    test('recognises the challenge header on any status', () {
      expect(
        ApiClient.isAccessGate(401, challenge: 'Cloudflare-Access realm=x'),
        isTrue,
      );
    });

    test('recognises a cdn-cgi access path on a custom domain', () {
      expect(
        ApiClient.isAccessGate(
          302,
          location: 'https://auth.example.com/cdn-cgi/access/login/h',
        ),
        isTrue,
      );
    });

    test('ignores a same-origin redirect', () {
      expect(ApiClient.isAccessGate(302, location: '/login'), isFalse);
    });
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/data/api_client_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:iris/data/net/server_connection.dart'`.

- [ ] **Step 4: Update `lib/data/net/api_client.dart`**

Replace the library doc's first line with `/// The HTTP boundary between Iris and a Hermes dashboard.`

Add the import `import 'credentials.dart';` after `import '../../core/result.dart';`.

Replace the constructor with:

```dart
  ApiClient({
    required ServerConfig server,
    Dio? dio,
    ServerSecrets secrets = ServerSecrets.none,
  }) : _server = server,
       _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: server.baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 45),
      // Iris inspects the status itself so it can build a precise failure;
      // letting Dio throw would lose the response body that explains why.
      validateStatus: (_) => true,
      // A redirect is an answer, not a detour: Cloudflare Access answers an
      // unauthenticated request with a 302 to its login page, and following it
      // would turn "you need a token" into a confusing 200 of HTML.
      followRedirects: false,
      headers: const {'Accept': 'application/json'},
    );
    if (secrets.hasAccessToken) {
      final headers = secrets.accessHeaders;
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // Over cleartext the long-lived Access secret would be readable by
            // anyone on the path, so it is withheld; a LAN dashboard does not
            // need it anyway.
            if (options.uri.scheme == 'https') options.headers.addAll(headers);
            handler.next(options);
          },
        ),
      );
    }
  }
```

In `bytes`, replace `return Err(_failureForStatus(status, path, null));` with
`return Err(_failureForStatus(status, path, null, response.headers));`.

In `_send`, replace `return Err(_failureForStatus(status, path, body));` with
`return Err(_failureForStatus(status, path, body, response.headers));`.

Replace `_failureForStatus` with:

```dart
  IrisFailure _failureForStatus(
    int status,
    String path,
    Json? body,
    Headers headers,
  ) {
    if (isAccessGate(
      status,
      location: headers['location']?.first,
      challenge: headers['www-authenticate']?.first,
    )) {
      _log.warn('$path → stopped by an access proxy');
      return IrisFailure(
        FailureKind.accessGate,
        message: 'An access proxy in front of the server stopped the request.',
        statusCode: status,
        endpoint: path,
      );
    }
    // FastAPI reports errors as `detail`; older endpoints use `error` or
    // `message`.
    final message =
        body?['error'].stringOrNull ??
        body?['message'].stringOrNull ??
        body?['detail'].stringOrNull;
    final kind = switch (status) {
      401 || 403 => FailureKind.unauthorized,
      404 => FailureKind.notFound,
      >= 300 && < 400 => FailureKind.rejected,
      >= 400 && < 500 => FailureKind.rejected,
      >= 500 => FailureKind.server,
      _ => FailureKind.unknown,
    };
    _log.warn('$path → HTTP $status');
    return IrisFailure(
      kind,
      message: message == null ? null : IrisLog.redact(message),
      statusCode: status,
      endpoint: path,
    );
  }

  /// Whether a response is an access proxy turning the request away before it
  /// reached Hermes.
  ///
  /// Cloudflare Access marks its challenge with a `Www-Authenticate:
  /// Cloudflare-Access` header and redirects to `*.cloudflareaccess.com` or, on
  /// a custom team domain, to a `/cdn-cgi/access/` path. Any one is enough.
  static bool isAccessGate(int status, {String? location, String? challenge}) {
    if (challenge != null &&
        challenge.toLowerCase().startsWith('cloudflare-access')) {
      return true;
    }
    if (status < 300 || status >= 400 || location == null) return false;
    final target = Uri.tryParse(location);
    if (target == null) return false;
    return target.host.endsWith('.cloudflareaccess.com') ||
        target.path.contains('/cdn-cgi/access/');
  }
```

- [ ] **Step 5: Create `lib/data/net/server_connection.dart`**

```dart
/// One server's HTTP identity: its cookie jar, its secrets, and the client
/// built from them.
///
/// Each server gets its own jar. Sharing one across servers would send a
/// session cookie issued by a home server to a work server, which at best fails
/// and at worst leaks a token to a host that should never see it.
library;

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'api_client.dart';
import 'credentials.dart';
import 'server_config.dart';

final class ServerConnection {
  ServerConnection._(this.config, this.secrets, this.client, this._jar);

  /// Builds the connection. [adapter] replaces the network, for tests.
  factory ServerConnection.create(
    ServerConfig config, {
    ServerSecrets secrets = ServerSecrets.none,
    HttpClientAdapter? adapter,
  }) {
    final jar = CookieJar();
    final dio = Dio()..interceptors.add(CookieManager(jar));
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    } else if (config.allowSelfSignedCertificate) {
      final io = dio.httpClientAdapter;
      if (io is IOHttpClientAdapter) {
        io.createHttpClient = () => _trusting(config);
      }
    }
    return ServerConnection._(
      config,
      secrets,
      ApiClient(server: config, dio: dio, secrets: secrets),
      jar,
    );
  }

  final ServerConfig config;
  final ServerSecrets secrets;
  final ApiClient client;
  final CookieJar _jar;

  /// The Access headers for a request to [uri]: none over cleartext.
  Map<String, String> accessHeadersFor(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'wss')
      ? secrets.accessHeaders
      : const {};

  /// An `HttpClient` for the WebSocket upgrade, with the same certificate
  /// policy as REST, so a self-signed server that works for sign-in does not
  /// then fail on the live connection.
  HttpClient socketHttpClient() =>
      config.allowSelfSignedCertificate ? _trusting(config) : HttpClient();

  /// Accepts a certificate that does not chain to a trusted root, for this
  /// connection's host only. A global override would disable validation for
  /// every request the app makes.
  static HttpClient _trusting(ServerConfig config) => HttpClient()
    ..badCertificateCallback = (cert, host, port) => host == config.uri.host;

  Future<void> clearSession() => _jar.deleteAll();

  void close() => client.close();
}
```

- [ ] **Step 6: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/data/net/api_client.dart lib/data/net/server_connection.dart test/support/fake_http.dart test/data/api_client_test.dart
git commit -m "feat(net): Access headers over https, redirect-aware failures, ServerConnection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Dashboard discovery, sign-in and tickets

**Files:**
- Create: `lib/data/net/dashboard_auth.dart`
- Modify: `lib/data/net/server_connection.dart` (add `auth`)
- Test: `test/data/dashboard_auth_test.dart` (create)

**Interfaces:**
- Consumes: `ServerConnection`, `ApiClient` (Task 4).
- Produces:
  - `enum DashboardAccess { password, open, browserOnly, accessGate, notHermes, unreachable }`
  - `final class DashboardProbe { const DashboardProbe({required DashboardAccess access, String? version, IrisFailure? failure}); }`
  - `final class DashboardAuth { Future<DashboardProbe> probe(); Future<Result<void>> signIn({required String username, required String password}); Future<Result<String>> mintTicket(); }`
  - `ServerConnection.auth` → `DashboardAuth`.

- [ ] **Step 1: Write the failing tests**

Create `test/data/dashboard_auth_test.dart`:

```dart
/// Finding out what a dashboard wants, signing in, and minting tickets.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/dashboard_auth.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;
  late ServerConnection connection;

  setUp(() {
    http = FakeHttp();
    connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'H'),
      adapter: http,
    );
  });

  tearDown(() => connection.close());

  group('probe', () {
    test('a password provider means a login is needed', () async {
      http
        ..on(
          'GET',
          '/api/auth/providers',
          (_) => FakeReply.json({
            'providers': [
              {'name': 'basic', 'supports_password': true},
            ],
          }),
        )
        ..on('GET', '/api/status', (_) => FakeReply.json({'version': '0.9.1'}));
      final probe = await connection.auth.probe();
      expect(probe.access, DashboardAccess.password);
      expect(probe.version, '0.9.1');
    });

    test('Cloudflare Access in front reads as an access gate', () async {
      http.on('GET', '/api/auth/providers', (_) => FakeReply.cloudflareLogin());
      expect(
        (await connection.auth.probe()).access,
        DashboardAccess.accessGate,
      );
    });

    test('a same-origin redirect means browser-only sign-in', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => const FakeReply(302, headers: {'location': '/login'}),
      );
      expect(
        (await connection.auth.probe()).access,
        DashboardAccess.browserOnly,
      );
    });

    test('no providers means an open dashboard', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.json({'providers': <Object>[]}),
      );
      expect((await connection.auth.probe()).access, DashboardAccess.open);
    });

    test('OAuth-only providers mean browser-only sign-in', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.json({
          'providers': [
            {'name': 'google', 'supports_password': false},
          ],
        }),
      );
      expect(
        (await connection.auth.probe()).access,
        DashboardAccess.browserOnly,
      );
    });

    test('an HTML page is not a dashboard', () async {
      http.on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.html('<html>router admin</html>'),
      );
      expect((await connection.auth.probe()).access, DashboardAccess.notHermes);
    });

    test('an older dashboard without auth routes is open', () async {
      http.on('GET', '/api/status', (_) => FakeReply.json({'version': '0.7'}));
      final probe = await connection.auth.probe();
      expect(probe.access, DashboardAccess.open);
      expect(probe.version, '0.7');
    });

    test('a host answering 404 everywhere is not a dashboard', () async {
      final probe = await connection.auth.probe();
      expect(probe.access, DashboardAccess.notHermes);
    });
  });

  group('signIn', () {
    test('sends the basic provider with both fields', () async {
      http.on(
        'POST',
        '/auth/password-login',
        (_) => FakeReply.json({'ok': true}),
      );
      final result = await connection.auth.signIn(
        username: 'me',
        password: 'pw',
      );
      expect(result.isOk, isTrue);
      expect(http.requests.single.data, {
        'provider': 'basic',
        'username': 'me',
        'password': 'pw',
      });
    });

    test('a same-origin redirect after login is a success', () async {
      http.on(
        'POST',
        '/auth/password-login',
        (_) => const FakeReply(303, headers: {'location': '/'}),
      );
      expect(
        (await connection.auth.signIn(username: 'me', password: 'pw')).isOk,
        isTrue,
      );
    });

    test('a 401 is an unauthorized failure', () async {
      http.on(
        'POST',
        '/auth/password-login',
        (_) => FakeReply.json({'detail': 'Invalid credentials'}, status: 401),
      );
      final result = await connection.auth.signIn(
        username: 'me',
        password: 'no',
      );
      expect(result.failureOrNull?.kind, FailureKind.unauthorized);
    });

    test('the session cookie rides the ticket request', () async {
      http
        ..on(
          'POST',
          '/auth/password-login',
          (_) => FakeReply.json(
            {'ok': true},
            headers: {'set-cookie': 'hermes_session=abc; Path=/; HttpOnly'},
          ),
        )
        ..on(
          'POST',
          '/api/auth/ws-ticket',
          (_) => FakeReply.json({'ticket': 't1'}),
        );
      await connection.auth.signIn(username: 'me', password: 'pw');
      final ticket = await connection.auth.mintTicket();
      expect(ticket.valueOrNull, 't1');
      final cookie = http.to('/api/auth/ws-ticket').single.headers['cookie'];
      expect('$cookie', contains('hermes_session=abc'));
    });
  });

  group('mintTicket', () {
    test('an empty ticket is malformed', () async {
      http.on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => FakeReply.json({'ticket': '  '}),
      );
      expect(
        (await connection.auth.mintTicket()).failureOrNull?.kind,
        FailureKind.malformed,
      );
    });

    test('a redirect to the login page means the session expired', () async {
      http.on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => const FakeReply(302, headers: {'location': '/login'}),
      );
      expect(
        (await connection.auth.mintTicket()).failureOrNull?.kind,
        FailureKind.unauthorized,
      );
    });

    test('an access gate stays an access gate', () async {
      http.on('POST', '/api/auth/ws-ticket', (_) => FakeReply.cloudflareLogin());
      expect(
        (await connection.auth.mintTicket()).failureOrNull?.kind,
        FailureKind.accessGate,
      );
    });
  });
}
```

Note on the last probe test: the fake answers unknown routes with 404, so `/api/auth/providers` and `/api/status` are both 404. That is a reachable host that is not a dashboard, hence `notHermes`. A transport error (DNS, refused connection) gives `unreachable`.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/dashboard_auth_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:iris/data/net/dashboard_auth.dart'`.

- [ ] **Step 3: Create `lib/data/net/dashboard_auth.dart`**

```dart
/// Signing in to a Hermes dashboard.
///
/// The dashboard uses a cookie session for REST and a single-use ticket for the
/// live WebSocket. So signing in is two steps: exchange a username and password
/// for a session cookie, then exchange the cookie for a ticket each time a
/// socket opens. The cookie stays in the connection's jar; nothing else in the
/// app handles it.
///
/// Discovery comes first so the connect screen asks only for what this
/// dashboard actually wants, and can name the reason when it cannot proceed.
library;

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import 'api_client.dart';

/// What a dashboard needs before it will open a live connection.
enum DashboardAccess {
  /// A username and password, exchanged for a session cookie.
  password,

  /// Nothing: auth is not configured. Common on a private network.
  open,

  /// Only browser (OAuth) sign-in is offered. Not supported yet.
  browserOnly,

  /// An access proxy (Cloudflare Access) stands in front and wants a service
  /// token before anything reaches Hermes.
  accessGate,

  /// Something answered, but it is not a Hermes dashboard.
  notHermes,

  /// Nothing answered: wrong address, server down, or no route from here.
  unreachable,
}

/// The outcome of looking at a dashboard's front door.
@immutable
final class DashboardProbe {
  const DashboardProbe({required this.access, this.version, this.failure});

  final DashboardAccess access;

  /// What `/api/status` reported, for confirmation on screen.
  final String? version;

  /// The failure behind [DashboardAccess.unreachable] or
  /// [DashboardAccess.accessGate], for the explanation shown.
  final IrisFailure? failure;
}

/// Performs dashboard authentication over one connection's client.
final class DashboardAuth {
  const DashboardAuth(this._client);

  static const _log = IrisLog('auth');

  final ApiClient _client;

  /// Asks the dashboard what it needs, without sending a login.
  ///
  /// Never fails: every outcome, including no answer at all, is a
  /// [DashboardAccess] the connect screen can explain.
  Future<DashboardProbe> probe() async {
    final providers = await _client.get('/api/auth/providers');
    switch (providers) {
      case Err(:final failure) when failure.kind == FailureKind.accessGate:
        return DashboardProbe(
          access: DashboardAccess.accessGate,
          failure: failure,
        );
      case Err(:final failure) when _isRedirect(failure):
        return DashboardProbe(
          access: DashboardAccess.browserOnly,
          failure: failure,
        );
      case Err(:final failure) when failure.kind == FailureKind.notFound:
        // Dashboards from before auth providers existed have no such route but
        // still answer /api/status. A 404 there too means this is not Hermes.
        final status = await _client.get('/api/status');
        return switch (status) {
          Ok(:final value) when value.isMap => DashboardProbe(
            access: DashboardAccess.open,
            version: value['version'].stringOrNull,
          ),
          _ => DashboardProbe(
            access: DashboardAccess.notHermes,
            failure: failure,
          ),
        };
      case Err(:final failure):
        return DashboardProbe(
          access: failure.kind == FailureKind.unauthorized
              ? DashboardAccess.browserOnly
              : DashboardAccess.unreachable,
          failure: failure,
        );
      case Ok(:final value):
        // A 2xx only means "Hermes" when it carries the provider list. A router
        // admin page or a captive portal answers 200 too.
        if (!value['providers'].isList) {
          return const DashboardProbe(access: DashboardAccess.notHermes);
        }
        final list = value['providers'].list;
        final version = await _version();
        if (list.any((p) => p['supports_password'].boolean())) {
          return DashboardProbe(
            access: DashboardAccess.password,
            version: version,
          );
        }
        return DashboardProbe(
          access: list.isEmpty
              ? DashboardAccess.open
              : DashboardAccess.browserOnly,
          version: version,
        );
    }
  }

  Future<String?> _version() async => switch (await _client.get(
    '/api/status',
  )) {
    Ok(:final value) => value['version'].stringOrNull,
    Err() => null,
  };

  /// Exchanges a username and password for a session cookie.
  ///
  /// On success the cookie is in the connection's jar. Nothing here retains
  /// the password; the caller decides whether to keep it in the keystore.
  Future<Result<void>> signIn({
    required String username,
    required String password,
  }) async {
    const path = '/auth/password-login';
    final result = await _client.post(
      path,
      body: {'provider': 'basic', 'username': username, 'password': password},
    );
    switch (result) {
      case Ok():
        _log.info('signed in');
        return const Ok(null);
      // Some deployments answer a form-style login with a redirect home. The
      // cookie is already in the jar; minting a ticket proves it.
      case Err(:final failure) when _isRedirect(failure):
        return const Ok(null);
      case Err(:final failure)
          when failure.kind == FailureKind.unauthorized ||
              failure.statusCode == 400:
        return Err(
          IrisFailure(
            FailureKind.unauthorized,
            message:
                failure.message ?? 'That username or password was not accepted.',
            statusCode: failure.statusCode,
            endpoint: path,
          ),
        );
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// Mints a single-use ticket for one WebSocket connect.
  ///
  /// An expired session reads as [FailureKind.unauthorized], whether the
  /// dashboard says 401 or redirects to its login page, so the caller knows to
  /// sign in again rather than retry.
  Future<Result<String>> mintTicket() async {
    const path = '/api/auth/ws-ticket';
    final result = await _client.post(path);
    switch (result) {
      case Ok(:final value):
        final ticket = value['ticket'].stringOrNull?.trim();
        if (ticket == null || ticket.isEmpty) {
          return const Err(
            IrisFailure.malformed(
              message: 'The dashboard did not issue a connection ticket.',
              endpoint: path,
            ),
          );
        }
        return Ok(ticket);
      case Err(:final failure) when _isRedirect(failure):
        return Err(
          IrisFailure(
            FailureKind.unauthorized,
            message: 'Sign in to the dashboard again.',
            statusCode: failure.statusCode,
            endpoint: path,
          ),
        );
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// A plain 3xx: not an access gate, which keeps its own kind.
  static bool _isRedirect(IrisFailure failure) {
    final status = failure.statusCode;
    return failure.kind != FailureKind.accessGate &&
        status != null &&
        status >= 300 &&
        status < 400;
  }
}
```

- [ ] **Step 4: Expose it on the connection**

In `lib/data/net/server_connection.dart`, add `import 'dashboard_auth.dart';` after `import 'credentials.dart';` and this getter after `final CookieJar _jar;`:

```dart
  DashboardAuth get auth => DashboardAuth(client);
```

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/net/dashboard_auth.dart lib/data/net/server_connection.dart test/data/dashboard_auth_test.dart
git commit -m "feat(net): dashboard discovery, password sign-in and ticket minting

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: JSON-RPC frames

**Files:**
- Create: `lib/data/rpc/rpc_frame.dart`
- Test: `test/data/rpc_frame_test.dart` (create)

**Interfaces:**
- Produces:
  - `abstract final class RpcCodes { static const methodNotFound = -32601; static const invalidParams = -32602; }`
  - `final class RpcError { int? code; String message; String? reason; bool get isMethodNotFound; }`
  - `sealed class RpcFrame { factory RpcFrame.parse(String text); }` with `RpcResponse(id: int, result: Json, error: RpcError?)`, `RpcEvent(type: String, sessionId: String?, payload: Json, raw: Json)`, `RpcServerRequest(id: String, method: String, params: Json)`, `RpcUnreadable(reason: String)`.
  - `abstract final class RpcEncode { static String request(int id, String method, Map<String, Object?>? params); static String errorReply(String id, int code, String message); }`
  - `extension RpcFailure on IrisFailure { RpcError? get rpcError; }`

- [ ] **Step 1: Write the failing tests**

Create `test/data/rpc_frame_test.dart`:

```dart
/// Reading and writing the dashboard's JSON-RPC frames.
///
/// Frame shapes follow Hermes Conduit's client (`HermesClient.swift`), which
/// tracks the gateway in `tui_gateway/server.py`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

void main() {
  group('parse', () {
    test('a response carries its id and result', () {
      final frame = RpcFrame.parse(
        '{"jsonrpc":"2.0","id":7,"result":{"sessions":[]}}',
      );
      expect(frame, isA<RpcResponse>());
      final response = frame as RpcResponse;
      expect(response.id, 7);
      expect(response.error, isNull);
      expect(response.result['sessions'].isList, isTrue);
    });

    test('an error response keeps the machine-readable reason', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","id":3,"error":{"code":4090,'
                '"message":"session is owned elsewhere",'
                '"data":{"reason":"SESSION_NOT_OWNED"}}}',
              )
              as RpcResponse;
      expect(frame.error?.code, 4090);
      expect(frame.error?.reason, 'SESSION_NOT_OWNED');
    });

    test('an event has a type, a session and a payload', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","method":"event","params":{'
                '"type":"message.delta","session_id":"s1",'
                '"payload":{"text":"Hel"}}}',
              )
              as RpcEvent;
      expect(frame.type, 'message.delta');
      expect(frame.sessionId, 's1');
      expect(frame.payload['text'].stringOrNull, 'Hel');
    });

    test('gateway.ready needs no session', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready"}}',
              )
              as RpcEvent;
      expect(frame.type, 'gateway.ready');
      expect(frame.sessionId, isNull);
    });

    test('a server request has a string id', () {
      final frame =
          RpcFrame.parse(
                '{"jsonrpc":"2.0","id":"srq-1a2b","method":"clarify",'
                '"params":{"session_id":"s1","question":"Which?"}}',
              )
              as RpcServerRequest;
      expect(frame.id, 'srq-1a2b');
      expect(frame.method, 'clarify');
      expect(frame.params['question'].stringOrNull, 'Which?');
    });

    test('a server request with a numeric id is unreadable', () {
      // It could collide with one of our own request ids and settle the wrong
      // call, so it is never treated as a request or a response.
      expect(
        RpcFrame.parse('{"jsonrpc":"2.0","id":4,"method":"clarify"}'),
        isA<RpcUnreadable>(),
      );
    });

    test('an event without a type is unreadable', () {
      expect(
        RpcFrame.parse('{"jsonrpc":"2.0","method":"event","params":{}}'),
        isA<RpcUnreadable>(),
      );
    });

    test('garbage is unreadable, not an exception', () {
      expect(RpcFrame.parse('not json'), isA<RpcUnreadable>());
      expect(RpcFrame.parse('[1,2]'), isA<RpcUnreadable>());
    });
  });

  group('encode', () {
    test('a request omits empty params', () {
      final json = Json.decode(RpcEncode.request(1, 'ping', null));
      expect(json['jsonrpc'].stringOrNull, '2.0');
      expect(json['id'].intOrNull, 1);
      expect(json['method'].stringOrNull, 'ping');
      expect(json['params'].exists, isFalse);
      expect(Json.decode(RpcEncode.request(2, 'x', {}))['params'].exists, isFalse);
    });

    test('a request carries its params', () {
      final json = Json.decode(
        RpcEncode.request(3, 'session.resume', {'session_id': 's1'}),
      );
      expect(json['params']['session_id'].stringOrNull, 's1');
    });

    test('a decline echoes the string id', () {
      final json = Json.decode(
        RpcEncode.errorReply('srq-9', RpcCodes.methodNotFound, 'no handler'),
      );
      expect(json['id'].stringOrNull, 'srq-9');
      expect(json['error']['code'].intOrNull, -32601);
    });
  });

  group('method not found', () {
    test('is recognised by code', () {
      expect(
        const RpcError(code: -32601, message: 'x').isMethodNotFound,
        isTrue,
      );
    });

    test('is recognised by wording', () {
      expect(
        const RpcError(message: 'Unknown method: ping').isMethodNotFound,
        isTrue,
      );
      expect(const RpcError(message: 'busy').isMethodNotFound, isFalse);
    });

    test('is reachable from a failure', () {
      const failure = IrisFailure(
        FailureKind.rejected,
        cause: RpcError(code: -32601, message: 'x'),
      );
      expect(failure.rpcError?.isMethodNotFound, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/rpc_frame_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:iris/data/rpc/rpc_frame.dart'`.

- [ ] **Step 3: Create `lib/data/rpc/rpc_frame.dart`**

```dart
/// The dashboard's JSON-RPC 2.0 frames, as values.
///
/// Four things arrive on the socket: responses to Iris's requests (integer
/// ids), stream events (`method: "event"`), requests the gateway makes of Iris
/// (string ids such as `srq-1a2b`), and anything else. Parsing never throws:
/// a frame Iris cannot read becomes [RpcUnreadable] and is logged and dropped,
/// because one malformed frame must not take the connection down.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/json.dart';

/// Error codes Iris writes or recognises.
abstract final class RpcCodes {
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
}

/// An error the gateway returned for a request.
@immutable
final class RpcError {
  const RpcError({required this.message, this.code, this.reason});

  factory RpcError.fromJson(Json json) => RpcError(
    code: json['code'].intOrNull,
    message: json['message'].stringOrNull ?? 'The server reported an error.',
    reason: json['data']['reason'].stringOrNull,
  );

  final int? code;

  /// For people. Never parsed except by [isMethodNotFound].
  final String message;

  /// Machine-readable, from `data.reason` — for example `SESSION_NOT_OWNED`.
  final String? reason;

  /// Whether the gateway does not know the method. Older gateways phrase it
  /// differently, so the wording is matched as well as the code, as Hermes
  /// Desktop does.
  bool get isMethodNotFound {
    if (code == RpcCodes.methodNotFound) return true;
    final lowered = message.toLowerCase();
    return lowered.contains('method not found') ||
        lowered.contains('-32601') ||
        lowered.contains('unknown method') ||
        lowered.contains('no such method');
  }

  @override
  String toString() =>
      'RpcError($code, $message${reason == null ? '' : ', $reason'})';
}

/// Reads the [RpcError] behind a failure from an RPC call, if any.
extension RpcFailure on IrisFailure {
  RpcError? get rpcError => switch (cause) {
    final RpcError error => error,
    _ => null,
  };
}

/// One inbound frame.
sealed class RpcFrame {
  const RpcFrame();

  factory RpcFrame.parse(String text) {
    final json = Json.decode(text);
    if (!json.isMap) return const RpcUnreadable('not a JSON object');

    final method = json['method'].stringOrNull;
    final id = json['id'].raw;

    if (method == 'event') {
      final params = json['params'];
      final type = params['type'].stringOrNull;
      if (type == null || type.isEmpty) {
        return const RpcUnreadable('event without a type');
      }
      return RpcEvent(
        type: type,
        sessionId: params['session_id'].stringOrNull,
        payload: params['payload'],
        raw: params,
      );
    }

    if (method != null) {
      // Server requests carry string ids. An integer id could collide with one
      // of Iris's own requests, so such a frame is neither settled nor answered.
      if (id is String && id.isNotEmpty) {
        return RpcServerRequest(id: id, method: method, params: json['params']);
      }
      return RpcUnreadable('server request $method without a string id');
    }

    if (id is int) {
      final error = json['error'];
      return RpcResponse(
        id: id,
        result: json['result'],
        error: error.isMap ? RpcError.fromJson(error) : null,
      );
    }

    return const RpcUnreadable('neither a response, an event nor a request');
  }
}

/// The answer to one of Iris's requests.
final class RpcResponse extends RpcFrame {
  const RpcResponse({required this.id, required this.result, this.error});

  final int id;
  final Json result;
  final RpcError? error;
}

/// A stream event: agent output, tool progress, session changes.
final class RpcEvent extends RpcFrame {
  const RpcEvent({
    required this.type,
    required this.payload,
    required this.raw,
    this.sessionId,
  });

  /// For example `message.delta`, `tool.start`, `gateway.ready`.
  final String type;

  /// The session it belongs to, when it belongs to one.
  final String? sessionId;
  final Json payload;

  /// The whole `params` object, for fields this build does not read.
  final Json raw;
}

/// Something the gateway asks Iris: an approval, a clarifying question, a
/// secret. Answered by a frame echoing [id].
final class RpcServerRequest extends RpcFrame {
  const RpcServerRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  final String id;
  final String method;
  final Json params;
}

/// A frame Iris could not read, kept only to be logged.
final class RpcUnreadable extends RpcFrame {
  const RpcUnreadable(this.reason);

  final String reason;
}

/// Outbound frames.
abstract final class RpcEncode {
  /// A request. `params` is omitted when empty: the gateway's contract check
  /// treats an explicit empty object and an absent one differently on some
  /// methods.
  static String request(int id, String method, Map<String, Object?>? params) =>
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null && params.isNotEmpty) 'params': params,
      });

  /// Declines a server request.
  static String errorReply(String id, int code, String message) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/data/rpc_frame_test.dart`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/rpc/rpc_frame.dart test/data/rpc_frame_test.dart
git commit -m "feat(rpc): JSON-RPC frame parsing and encoding

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The socket seam and the RPC client

**Files:**
- Create: `lib/data/rpc/wire_socket.dart`
- Create: `lib/data/rpc/rpc_client.dart`
- Create: `test/support/fake_wire_socket.dart`
- Test: `test/data/rpc_client_test.dart` (create)

**Interfaces:**
- Consumes: `RpcFrame`, `RpcEncode`, `RpcCodes`, `RpcFailure` (Task 6).
- Produces:
  - `abstract interface class WireSocket { Stream<String> get frames; void send(String text); Future<void> close([int code = 1000]); int? get closeCode; }`
  - `typedef WireConnector = Future<WireSocket> Function(Uri uri, Map<String, String> headers);`
  - `final class IoWireSocket implements WireSocket { static Future<WireSocket> connect(Uri uri, {required Map<String, String> headers, HttpClient? client, Duration timeout}); }`
  - `final class RpcClient { RpcClient(WireSocket socket, {Duration defaultTimeout}); Stream<RpcEvent> get events; Future<void> get done; bool get isOpen; Future<Result<Json>> call(String method, {Map<String, Object?>? params, Duration? timeout}); Future<Result<void>> ping({Duration timeout}); Future<void> close(); }`. An RPC error becomes `FailureKind.rejected` with `cause: RpcError`; a timeout becomes `FailureKind.timeout`; a closed socket becomes `FailureKind.offline`.
  - Test fake `FakeWireSocket` with `sent`, `serverSends(Object)`, `serverCloses()`, `replyToLast({result, error})`.

- [ ] **Step 1: Write the test support**

Create `test/support/fake_wire_socket.dart`:

```dart
/// A scripted WebSocket, so RPC behaviour is tested frame by frame.
library;

import 'dart:async';
import 'dart:convert';

import 'package:iris/core/json.dart';
import 'package:iris/data/rpc/wire_socket.dart';

final class FakeWireSocket implements WireSocket {
  final _incoming = StreamController<String>();
  final List<String> sent = [];
  int? _closeCode;

  @override
  Stream<String> get frames => _incoming.stream;

  @override
  void send(String text) {
    if (_closeCode != null) throw StateError('socket closed');
    sent.add(text);
  }

  @override
  Future<void> close([int code = 1000]) async {
    _closeCode ??= code;
    // Not awaited: once the client has cancelled its subscription, the done
    // future of a single-subscription controller may never complete.
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  int? get closeCode => _closeCode;

  /// Delivers [frame] (a JSON-encodable value or a raw string) to the client.
  void serverSends(Object frame) =>
      _incoming.add(frame is String ? frame : jsonEncode(frame));

  /// Simulates the server or the network dropping the connection.
  Future<void> serverCloses() => close(1006);

  Json get lastSent => Json.decode(sent.last);

  /// Answers the most recent request.
  void replyToLast({Object? result, Map<String, Object?>? error}) =>
      serverSends({
        'jsonrpc': '2.0',
        'id': lastSent['id'].raw,
        if (error != null) 'error': error else 'result': result,
      });
}
```

- [ ] **Step 2: Write the failing tests**

Create `test/data/rpc_client_test.dart`:

```dart
/// Request/response matching, events, declines, timeouts and shutdown.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/rpc/rpc_client.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

import '../support/fake_wire_socket.dart';

void main() {
  late FakeWireSocket socket;
  late RpcClient client;

  setUp(() {
    socket = FakeWireSocket();
    client = RpcClient(socket);
  });

  tearDown(() => client.close());

  test('a request is a JSON-RPC text frame with an integer id', () {
    client.call('session.list');
    final frame = socket.lastSent;
    expect(frame['jsonrpc'].stringOrNull, '2.0');
    expect(frame['method'].stringOrNull, 'session.list');
    expect(frame['id'].raw, isA<int>());
    expect(frame['params'].exists, isFalse);
  });

  test('a response settles its own request', () async {
    final call = client.call('session.list');
    socket.replyToLast(result: {'sessions': <Object>[]});
    final result = await call;
    expect(result.valueOrNull?['sessions'].isList, isTrue);
  });

  test('responses are matched by id, not by order', () async {
    final first = client.call('a');
    final firstId = socket.lastSent['id'].raw;
    final second = client.call('b');
    socket.replyToLast(result: 'B');
    socket.serverSends({'jsonrpc': '2.0', 'id': firstId, 'result': 'A'});
    expect((await first).valueOrNull?.stringOrNull, 'A');
    expect((await second).valueOrNull?.stringOrNull, 'B');
  });

  test('an error response is a rejected failure carrying the RpcError', () async {
    final call = client.call('prompt.submit');
    socket.replyToLast(
      error: {
        'code': 4090,
        'message': 'owned elsewhere',
        'data': {'reason': 'SESSION_NOT_OWNED'},
      },
    );
    final failure = (await call).failureOrNull!;
    expect(failure.kind, FailureKind.rejected);
    expect(failure.rpcError?.reason, 'SESSION_NOT_OWNED');
    expect(failure.endpoint, 'prompt.submit');
  });

  test('an unanswered request times out', () async {
    final result = await client.call(
      'slow',
      timeout: const Duration(milliseconds: 20),
    );
    expect(result.failureOrNull?.kind, FailureKind.timeout);
  });

  test('a closed socket fails pending calls and completes done', () async {
    final call = client.call('session.list');
    await socket.serverCloses();
    expect((await call).failureOrNull?.kind, FailureKind.offline);
    await client.done;
    expect(client.isOpen, isFalse);
    expect(
      (await client.call('again')).failureOrNull?.kind,
      FailureKind.offline,
    );
  });

  test('events are forwarded', () async {
    final next = client.events.first;
    socket.serverSends({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': 'gateway.ready'},
    });
    expect((await next).type, 'gateway.ready');
  });

  test('a server request is declined at once, echoing its id', () async {
    socket.serverSends({
      'jsonrpc': '2.0',
      'id': 'srq-1',
      'method': 'clarify',
      'params': {'session_id': 's1'},
    });
    await Future<void>.delayed(Duration.zero);
    final reply = socket.lastSent;
    expect(reply['id'].stringOrNull, 'srq-1');
    expect(reply['error']['code'].intOrNull, RpcCodes.methodNotFound);
  });

  test('ping treats method-not-found as alive', () async {
    final ping = client.ping();
    socket.replyToLast(error: {'code': -32601, 'message': 'Method not found'});
    expect((await ping).isOk, isTrue);
  });

  test('ping reports a real failure', () async {
    final ping = client.ping(timeout: const Duration(milliseconds: 20));
    expect((await ping).failureOrNull?.kind, FailureKind.timeout);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/data/rpc_client_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:iris/data/rpc/rpc_client.dart'`.

- [ ] **Step 4: Create `lib/data/rpc/wire_socket.dart`**

```dart
/// The seam between the RPC layer and a real WebSocket.
///
/// Small on purpose: text frames in, text frames out, and close. Everything the
/// RPC client does is tested through a fake of this, so no test needs a server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class WireSocket {
  /// Text frames from the server. Single-subscription; ends when the socket
  /// closes, for any reason.
  Stream<String> get frames;

  /// Sends one text frame. Throws if the socket is already closed.
  void send(String text);

  Future<void> close([int code = 1000]);

  /// Null while open.
  int? get closeCode;
}

/// Opens a socket to [uri] with extra handshake [headers].
typedef WireConnector =
    Future<WireSocket> Function(Uri uri, Map<String, String> headers);

/// The production socket, over `dart:io`.
final class IoWireSocket implements WireSocket {
  IoWireSocket._(this._socket);

  static Future<WireSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
    HttpClient? client,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      customClient: client,
    ).timeout(timeout);
    // A transport-level ping finds a half-open connection — a phone that
    // changed networks — without spending an RPC on it.
    socket.pingInterval = const Duration(seconds: 20);
    return IoWireSocket._(socket);
  }

  final WebSocket _socket;

  @override
  Stream<String> get frames => _socket
      .map<String>(
        (Object? message) => switch (message) {
          final String text => text,
          final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
          _ => '',
        },
      )
      .where((text) => text.isNotEmpty);

  @override
  void send(String text) => _socket.add(text);

  @override
  Future<void> close([int code = 1000]) async {
    await _socket.close(code);
  }

  @override
  int? get closeCode => _socket.closeCode;
}
```

- [ ] **Step 5: Create `lib/data/rpc/rpc_client.dart`**

```dart
/// JSON-RPC over one open socket.
///
/// Deliberately thin: it correlates requests with responses, forwards events,
/// and declines requests the gateway makes that Iris has no screen for. It
/// does not reconnect — one client lives exactly as long as one socket, and
/// `DashboardSession` replaces it when the socket dies.
library;

import 'dart:async';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import 'rpc_frame.dart';
import 'wire_socket.dart';

final class RpcClient {
  RpcClient(
    this._socket, {
    this.defaultTimeout = const Duration(seconds: 30),
  }) {
    _subscription = _socket.frames.listen(
      _onFrame,
      onError: (Object _) => _shutdown(),
      onDone: _shutdown,
      cancelOnError: true,
    );
  }

  static const _log = IrisLog('rpc');

  final WireSocket _socket;
  final Duration defaultTimeout;
  late final StreamSubscription<String> _subscription;
  final Map<int, _Pending> _pending = {};
  final _events = StreamController<RpcEvent>.broadcast();
  final _closed = Completer<void>();
  int _nextId = 0;

  /// Stream events, in arrival order. Closes with the socket.
  Stream<RpcEvent> get events => _events.stream;

  /// Completes when the socket has closed, for whatever reason.
  Future<void> get done => _closed.future;

  bool get isOpen => !_closed.isCompleted;

  /// Calls [method]. Never throws.
  Future<Result<Json>> call(
    String method, {
    Map<String, Object?>? params,
    Duration? timeout,
  }) {
    if (!isOpen) return Future.value(Err(_closedFailure(method)));
    final id = ++_nextId;
    final completer = Completer<Result<Json>>();
    final timer = Timer(timeout ?? defaultTimeout, () {
      if (_pending.remove(id) != null) {
        completer.complete(
          Err(
            IrisFailure(
              FailureKind.timeout,
              message: 'No answer to $method in time.',
              endpoint: method,
            ),
          ),
        );
      }
    });
    _pending[id] = _Pending(method, completer, timer);
    try {
      _socket.send(RpcEncode.request(id, method, params));
    } on Object catch (error, stackTrace) {
      _pending.remove(id);
      timer.cancel();
      return Future.value(
        Err(
          IrisFailure(
            FailureKind.offline,
            endpoint: method,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
    _log.debug('→ $method #$id');
    return completer.future;
  }

  /// Proves the socket is alive.
  ///
  /// A gateway without `ping` answers "method not found" — and that answer
  /// travelled over this socket just as a pong would.
  Future<Result<void>> ping({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = await call('ping', timeout: timeout);
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final failure) when failure.rpcError?.isMethodNotFound ?? false =>
        const Ok(null),
      Err(:final failure) => Err(failure),
    };
  }

  void _onFrame(String text) {
    switch (RpcFrame.parse(text)) {
      case RpcResponse(:final id, :final result, :final error):
        final pending = _pending.remove(id);
        if (pending == null) {
          _log.debug('unmatched response #$id');
          return;
        }
        pending.timer.cancel();
        pending.completer.complete(
          error == null
              ? Ok(result)
              : Err(
                  IrisFailure(
                    FailureKind.rejected,
                    message: IrisLog.redact(error.message),
                    endpoint: pending.method,
                    cause: error,
                  ),
                ),
        );
      case final RpcEvent event:
        _events.add(event);
      case RpcServerRequest(:final id, :final method):
        // Phase 1 has no approval or clarify cards. Declining at once makes the
        // tool fail fast instead of waiting out its deadline.
        _log.info('declined server request $method');
        _trySend(
          RpcEncode.errorReply(
            id,
            RpcCodes.methodNotFound,
            'Iris has no handler for $method',
          ),
        );
      case RpcUnreadable(:final reason):
        _log.warn('dropped frame: $reason');
    }
  }

  void _trySend(String text) {
    try {
      _socket.send(text);
    } on Object {
      // The socket is closing; the gateway withdraws the request itself.
    }
  }

  void _shutdown() {
    if (_closed.isCompleted) return;
    _closed.complete();
    for (final pending in _pending.values) {
      pending.timer.cancel();
      pending.completer.complete(Err(_closedFailure(pending.method)));
    }
    _pending.clear();
    unawaited(_events.close());
  }

  static IrisFailure _closedFailure(String method) => IrisFailure(
    FailureKind.offline,
    message: 'The live connection closed.',
    endpoint: method,
  );

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
    _shutdown();
  }
}

final class _Pending {
  _Pending(this.method, this.completer, this.timer);

  final String method;
  final Completer<Result<Json>> completer;
  final Timer timer;
}
```

- [ ] **Step 6: Run the tests and the analyzer**

Run: `flutter test test/data/rpc_client_test.dart`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/data/rpc/wire_socket.dart lib/data/rpc/rpc_client.dart test/support/fake_wire_socket.dart test/data/rpc_client_test.dart
git commit -m "feat(rpc): WireSocket seam and RpcClient

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The live session

**Files:**
- Create: `lib/data/rpc/dashboard_session.dart`
- Test: `test/data/dashboard_session_test.dart` (create)

**Interfaces:**
- Consumes: `ServerConnection` (`auth`, `secrets`, `config`, `accessHeadersFor`, `socketHttpClient`), `RpcClient`, `WireConnector`, `IoWireSocket`.
- Produces:
  - `enum LinkPhase { idle, connecting, live, retrying, needsSignIn, blocked }`
  - `final class LinkState { const LinkState(LinkPhase phase, {int attempt = 0, IrisFailure? failure, Duration? retryIn}); }`
  - `final class DashboardSession { DashboardSession({required ServerConnection http, WireConnector? connector, Duration Function(int attempt)? backoff}); LinkState get state; Stream<LinkState> get states; Stream<RpcEvent> get events; bool get isLive; Future<void> start(); Future<void> reconnectNow(); Future<Result<Json>> call(String method, {Map<String, Object?>? params, Duration? timeout}); Future<void> dispose(); static Uri socketUri(Uri base, String ticket); static Duration defaultBackoff(int attempt); }`

- [ ] **Step 1: Write the failing tests**

Create `test/data/dashboard_session_test.dart`:

```dart
/// The live link: ticket, socket, re-login, backoff and the cases that must
/// not retry.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';

/// Polls [condition] for up to a second.
Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition never became true');
}

void main() {
  late FakeHttp http;
  late List<(Uri, Map<String, String>)> opened;
  late List<FakeWireSocket> sockets;

  setUp(() {
    http = FakeHttp();
    opened = [];
    sockets = [];
  });

  DashboardSession sessionFor({
    ServerSecrets secrets = ServerSecrets.none,
    String baseUrl = 'https://h.example',
  }) {
    final connection = ServerConnection.create(
      ServerConfig(id: 's', baseUrl: baseUrl, label: 'H'),
      secrets: secrets,
      adapter: http,
    );
    final session = DashboardSession(
      http: connection,
      backoff: (_) => Duration.zero,
      connector: (uri, headers) async {
        opened.add((uri, headers));
        final socket = FakeWireSocket();
        sockets.add(socket);
        return socket;
      },
    );
    addTearDown(() async {
      await session.dispose();
      connection.close();
    });
    return session;
  }

  void ticketsInOrder(List<String> tickets) {
    var next = 0;
    http.on(
      'POST',
      '/api/auth/ws-ticket',
      (_) => FakeReply.json({'ticket': tickets[next++]}),
    );
  }

  test('connects over wss with a fresh ticket', () async {
    ticketsInOrder(['t1']);
    final session = sessionFor();
    await session.start();
    expect(session.state.phase, LinkPhase.live);
    expect(
      opened.single.$1,
      Uri.parse('wss://h.example/api/ws?ticket=t1'),
    );
  });

  test('sends the Access token on the socket', () async {
    ticketsInOrder(['t1']);
    await sessionFor(
      secrets: const ServerSecrets(
        accessClientId: 'id.access',
        accessClientSecret: 'shh',
      ),
    ).start();
    expect(opened.single.$2['CF-Access-Client-Id'], 'id.access');
    expect(opened.single.$2['CF-Access-Client-Secret'], 'shh');
  });

  test('never sends the Access token over ws://', () async {
    ticketsInOrder(['t1']);
    await sessionFor(
      baseUrl: 'http://192.168.1.20:9119',
      secrets: const ServerSecrets(
        accessClientId: 'id.access',
        accessClientSecret: 'shh',
      ),
    ).start();
    expect(
      opened.single.$1,
      Uri.parse('ws://192.168.1.20:9119/api/ws?ticket=t1'),
    );
    expect(opened.single.$2, isEmpty);
  });

  test('an expired session signs in again with the stored login', () async {
    var signedIn = false;
    http
      ..on('POST', '/auth/password-login', (_) {
        signedIn = true;
        return FakeReply.json({'ok': true});
      })
      ..on(
        'POST',
        '/api/auth/ws-ticket',
        (_) => signedIn
            ? FakeReply.json({'ticket': 't2'})
            : FakeReply.json({'detail': 'Not authenticated'}, status: 401),
      );
    final session = sessionFor(
      secrets: const ServerSecrets(username: 'me', password: 'pw'),
    );
    await session.start();
    expect(session.state.phase, LinkPhase.live);
    expect(opened.single.$1.queryParameters['ticket'], 't2');
    expect(http.to('/auth/password-login').single.data, {
      'provider': 'basic',
      'username': 'me',
      'password': 'pw',
    });
  });

  test('without a stored login an expired session asks to sign in', () async {
    http.on(
      'POST',
      '/api/auth/ws-ticket',
      (_) => FakeReply.json({'detail': 'Not authenticated'}, status: 401),
    );
    final session = sessionFor();
    await session.start();
    expect(session.state.phase, LinkPhase.needsSignIn);
    expect(opened, isEmpty);
  });

  test('an access proxy blocks without retrying', () async {
    http.on('POST', '/api/auth/ws-ticket', (_) => FakeReply.cloudflareLogin());
    final session = sessionFor();
    await session.start();
    expect(session.state.phase, LinkPhase.blocked);
    expect(session.state.failure?.kind, FailureKind.accessGate);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(http.to('/api/auth/ws-ticket'), hasLength(1));
  });

  test('a dropped socket reconnects with a new ticket', () async {
    ticketsInOrder(['t1', 't2']);
    final session = sessionFor();
    await session.start();
    await sockets.single.serverCloses();
    await eventually(
      () => opened.length == 2 && session.state.phase == LinkPhase.live,
    );
    expect(opened.last.$1.queryParameters['ticket'], 't2');
  });

  test('events are forwarded from the live socket', () async {
    ticketsInOrder(['t1']);
    final session = sessionFor();
    await session.start();
    final next = session.events.first;
    sockets.single.serverSends({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': 'gateway.ready'},
    });
    expect((await next).type, 'gateway.ready');
  });

  test('a call before the link is live fails as offline', () async {
    final result = await sessionFor().call('ping');
    expect(result.failureOrNull?.kind, FailureKind.offline);
  });

  test('dispose closes the socket and stops reconnecting', () async {
    ticketsInOrder(['t1', 't2']);
    final session = sessionFor();
    await session.start();
    await session.dispose();
    expect(sockets.single.closeCode, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(opened, hasLength(1));
  });

  test('backoff doubles to a five second ceiling', () {
    expect(DashboardSession.defaultBackoff(0), const Duration(seconds: 1));
    expect(DashboardSession.defaultBackoff(2), const Duration(seconds: 4));
    expect(DashboardSession.defaultBackoff(9), const Duration(seconds: 5));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/dashboard_session_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:iris/data/rpc/dashboard_session.dart'`.

- [ ] **Step 3: Create `lib/data/rpc/dashboard_session.dart`**

```dart
/// The live link to one dashboard.
///
/// A phone loses its connection constantly while the agent keeps working, so a
/// dropped socket is a normal event here, not an error. This object owns the
/// whole cycle: mint a fresh single-use ticket, open the socket, and when it
/// dies, do it again after a short backoff — signing in again first if the
/// session cookie has expired.
///
/// Two failures are never retried automatically: an access proxy turning Iris
/// away, and an untrusted certificate. Retrying either would only repeat the
/// same refusal until the user changes something.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import '../net/server_connection.dart';
import 'rpc_client.dart';
import 'rpc_frame.dart';
import 'wire_socket.dart';

/// Where the link is.
enum LinkPhase {
  /// Not started, or disposed.
  idle,

  /// Minting a ticket and opening the socket.
  connecting,

  /// The socket is open.
  live,

  /// Waiting to try again after a drop or a transient failure.
  retrying,

  /// The saved login no longer works, or none was saved.
  needsSignIn,

  /// Stopped by something only the user can fix: an access proxy or an
  /// untrusted certificate.
  blocked,
}

@immutable
final class LinkState {
  const LinkState(this.phase, {this.attempt = 0, this.failure, this.retryIn});

  final LinkPhase phase;

  /// How many consecutive attempts have failed.
  final int attempt;
  final IrisFailure? failure;

  /// When [phase] is [LinkPhase.retrying], how long until the next attempt.
  final Duration? retryIn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinkState &&
          other.phase == phase &&
          other.attempt == attempt &&
          other.failure?.kind == failure?.kind);

  @override
  int get hashCode => Object.hash(phase, attempt, failure?.kind);

  @override
  String toString() =>
      'LinkState(${phase.name}, attempt $attempt'
      '${failure == null ? '' : ', ${failure!.kind.name}'})';
}

final class DashboardSession {
  DashboardSession({
    required ServerConnection http,
    WireConnector? connector,
    Duration Function(int attempt)? backoff,
  }) : _http = http,
       _connector = connector ?? _ioConnector(http),
       _backoff = backoff ?? defaultBackoff;

  static const _log = IrisLog('link');

  /// `min(5, 2^attempt)` seconds, as Hermes Conduit does: quick enough to
  /// recover from a blip, slow enough not to hammer a server that is down.
  static Duration defaultBackoff(int attempt) => Duration(
    milliseconds: (math.min(5, math.pow(2, attempt)) * 1000).round(),
  );

  static WireConnector _ioConnector(ServerConnection http) =>
      (uri, headers) => IoWireSocket.connect(
        uri,
        headers: headers,
        client: http.socketHttpClient(),
      );

  /// The socket URL for [ticket] on the dashboard at [base].
  static Uri socketUri(Uri base, String ticket) {
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$path/api/ws',
      queryParameters: {'ticket': ticket},
    );
  }

  final ServerConnection _http;
  final WireConnector _connector;
  final Duration Function(int attempt) _backoff;
  final _states = StreamController<LinkState>.broadcast();
  final _events = StreamController<RpcEvent>.broadcast();

  LinkState _state = const LinkState(LinkPhase.idle);
  RpcClient? _client;
  StreamSubscription<RpcEvent>? _eventSubscription;
  Timer? _retry;
  int _attempt = 0;
  int _generation = 0;
  bool _connecting = false;
  bool _disposed = false;

  LinkState get state => _state;

  Stream<LinkState> get states => _states.stream;

  /// Events from whichever socket is current, across reconnects.
  Stream<RpcEvent> get events => _events.stream;

  bool get isLive => _state.phase == LinkPhase.live && (_client?.isOpen ?? false);

  /// Connects. Completes once the first attempt has settled.
  Future<void> start() => _run();

  /// Skips the backoff — for returning to the foreground, or a "try again" tap.
  Future<void> reconnectNow() async {
    if (_disposed || isLive) return;
    _retry?.cancel();
    _attempt = 0;
    await _run();
  }

  /// Calls [method] on the live socket. Never throws.
  Future<Result<Json>> call(
    String method, {
    Map<String, Object?>? params,
    Duration? timeout,
  }) {
    final client = _client;
    if (client == null || !client.isOpen) {
      return Future.value(
        Err(
          IrisFailure(
            FailureKind.offline,
            message: 'Not connected to the dashboard.',
            endpoint: method,
          ),
        ),
      );
    }
    return client.call(method, params: params, timeout: timeout);
  }

  Future<void> _run() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _retry?.cancel();
    _set(LinkState(LinkPhase.connecting, attempt: _attempt));
    final outcome = await _connectOnce();
    _connecting = false;
    if (_disposed) {
      await outcome.valueOrNull?.close();
      return;
    }
    switch (outcome) {
      case Ok(:final value):
        _adopt(value);
      case Err(:final failure):
        _onFailure(failure);
    }
  }

  Future<Result<RpcClient>> _connectOnce() async {
    final auth = _http.auth;
    var ticket = await auth.mintTicket();
    if (ticket case Err(:final failure)
        when failure.kind == FailureKind.unauthorized) {
      final secrets = _http.secrets;
      if (!secrets.hasLogin) return Err(failure);
      _log.info('session expired; signing in again');
      final signedIn = await auth.signIn(
        username: secrets.username!.trim(),
        password: secrets.password!,
      );
      if (signedIn case Err(failure: final signInFailure)) {
        return Err(signInFailure);
      }
      ticket = await auth.mintTicket();
    }
    switch (ticket) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final uri = socketUri(_http.config.uri, value);
        try {
          final socket = await _connector(uri, _http.accessHeadersFor(uri));
          return Ok(RpcClient(socket));
        } on Object catch (error, stackTrace) {
          return Err(_socketFailure(error, stackTrace));
        }
    }
  }

  static IrisFailure _socketFailure(Object error, StackTrace stackTrace) {
    final kind = switch (error) {
      TimeoutException() => FailureKind.timeout,
      TlsException() => FailureKind.tls,
      SocketException() => FailureKind.offline,
      WebSocketException() => FailureKind.rejected,
      _ => FailureKind.unknown,
    };
    // The exception text includes the URL, and the URL includes the ticket.
    _log.warn('socket open failed: ${kind.name}', data: IrisLog.redact('$error'));
    return IrisFailure(
      kind,
      message: kind == FailureKind.rejected
          ? 'The dashboard refused the live connection.'
          : null,
      endpoint: '/api/ws',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  void _adopt(RpcClient client) {
    final generation = ++_generation;
    _client = client;
    _attempt = 0;
    _eventSubscription = client.events.listen(_events.add);
    unawaited(client.done.then((_) => _onDropped(generation)));
    _set(const LinkState(LinkPhase.live));
    _log.info('live');
  }

  void _onDropped(int generation) {
    if (_disposed || generation != _generation) return;
    _client = null;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    _scheduleRetry(
      const IrisFailure(
        FailureKind.offline,
        message: 'The live connection dropped.',
      ),
    );
  }

  void _onFailure(IrisFailure failure) {
    switch (failure.kind) {
      case FailureKind.accessGate || FailureKind.tls:
        _set(LinkState(LinkPhase.blocked, failure: failure));
      case FailureKind.unauthorized:
        _set(LinkState(LinkPhase.needsSignIn, failure: failure));
      default:
        _scheduleRetry(failure);
    }
  }

  void _scheduleRetry(IrisFailure failure) {
    final delay = _backoff(_attempt);
    _attempt++;
    _set(
      LinkState(
        LinkPhase.retrying,
        attempt: _attempt,
        failure: failure,
        retryIn: delay,
      ),
    );
    _retry = Timer(delay, () => unawaited(_run()));
  }

  void _set(LinkState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _retry?.cancel();
    await _eventSubscription?.cancel();
    await _client?.close();
    _client = null;
    _set(const LinkState(LinkPhase.idle));
    await _states.close();
    await _events.close();
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/data/dashboard_session_test.dart`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/rpc/dashboard_session.dart test/data/dashboard_session_test.dart
git commit -m "feat(rpc): DashboardSession with fresh tickets, re-login and backoff

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Capabilities and the server repository

**Files:**
- Modify: `lib/data/net/capabilities.dart` (enum and probe)
- Modify: `lib/data/repositories/server_repository.dart` (rewrite)
- Modify: `test/data/server_repository_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2–8.
- Produces:
  - `enum ServerCapability { profiles, sessionSearch, cronJobs, skills, toolsets, kanban, conduitPlugin }`, each with `probePath` and `label`.
  - `enum ServerHealth { unknown, checking, online, unauthorized, gated, offline, untrusted; static ServerHealth fromLink(LinkState link); }`
  - `typedef ServerConnectionFactory = ServerConnection Function(ServerConfig config, {required ServerSecrets secrets});`
  - `ServerRepository({required IrisDatabase database, required CredentialStore credentials, ServerConnectionFactory? connect, WireConnector? connector})` with
    - `Future<DashboardProbe> testConnection(String baseUrl, {bool allowSelfSigned = false, ServerSecrets secrets = ServerSecrets.none})`
    - `Future<Result<ServerConfig>> addServer({required String baseUrl, required String label, ServerSecrets secrets = ServerSecrets.none, bool allowSelfSigned = false})`
    - `Future<Result<ServerConnection>> connectionFor(ServerConfig config)`
    - `Future<Result<DashboardSession>> sessionFor(ServerConfig config)`
    - `Future<void> release(String serverId)`
    - `Future<void> refreshCapabilities(ServerConfig config)`
    - `Stream<ServerCapabilities> watchCapabilities(String serverId)`
    - `Future<ServerCapabilities> cachedCapabilities(String serverId)`
    - `watchServers`, `listServers`, `rename`, `forget`, `dispose` as before.
  - `ConnectionAttempt` and `refreshSession`/`refresh` are removed.

- [ ] **Step 1: Rewrite the repository tests**

In `test/data/server_repository_test.dart`:

Add imports:

```dart
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';
```

Replace the `setUp` with:

```dart
  late FakeHttp http;

  setUp(() {
    db = IrisDatabase(NativeDatabase.memory());
    credentials = FakeCredentialStore();
    http = FakeHttp();
    repository = ServerRepository(
      database: db,
      credentials: credentials,
      connect: (config, {required secrets}) =>
          ServerConnection.create(config, secrets: secrets, adapter: http),
    );
  });
```

Add to the end of `group('adding', ...)`:

```dart
    test('a rejected login is never saved', () async {
      http.on(
        'POST',
        '/auth/password-login',
        (_) => FakeReply.json({'detail': 'Invalid credentials'}, status: 401),
      );
      final result = await repository.addServer(
        baseUrl: 'https://h.example',
        label: 'H',
        secrets: const ServerSecrets(username: 'me', password: 'wrong'),
      );
      expect(result.failureOrNull?.kind, FailureKind.unauthorized);
      expect(credentials.entries, isEmpty);
      expect(await repository.listServers(), isEmpty);
    });

    test('secrets are saved only after a ticket proves them', () async {
      http
        ..on(
          'POST',
          '/auth/password-login',
          (_) => FakeReply.json(
            {'ok': true},
            headers: {'set-cookie': 'hermes_session=abc; Path=/'},
          ),
        )
        ..on(
          'POST',
          '/api/auth/ws-ticket',
          (_) => FakeReply.json({'ticket': 't1'}),
        );
      const secrets = ServerSecrets(
        username: 'me',
        password: 'right',
        accessClientId: 'id.access',
        accessClientSecret: 'shh',
      );
      final result = await repository.addServer(
        baseUrl: 'https://h.example',
        label: 'H',
        secrets: secrets,
      );
      final config = result.valueOrNull!;
      expect(credentials.entries[config.id], secrets);
      expect(config.requiresPassword, isTrue);
      expect(config.usesAccessToken, isTrue);
    });

    test('an access-gated server without a token is refused as gated', () async {
      http.on('POST', '/api/auth/ws-ticket', (_) => FakeReply.cloudflareLogin());
      final result = await repository.addServer(
        baseUrl: 'https://h.example',
        label: 'H',
      );
      expect(result.failureOrNull?.kind, FailureKind.accessGate);
      expect(await repository.listServers(), isEmpty);
    });
```

Delete the tests `refreshing without a stored password asks for sign-in` and `an open server needs no session refresh`. Rename the remaining test `forgetting a server removes its password` to `forgetting a server removes its secrets`.

In `group('capabilities', ...)`, replace `ServerCapability.crons` with `ServerCapability.cronJobs`, `ServerCapability.memory` with `ServerCapability.kanban`, and the stored JSON strings `'["crons","skills"]'` with `'["cronJobs","skills"]'` and `'["crons","time_travel"]'` with `'["cronJobs","time_travel"]'`. Then add:

```dart
    test('a probe stores names, version and time', () async {
      http
        ..on(
          'GET',
          '/api/status',
          (_) => FakeReply.json({'version': '0.9.1'}),
        )
        ..on('GET', '/api/profiles', (_) => FakeReply.json({'profiles': []}))
        ..on('GET', '/api/skills', (_) => FakeReply.json({'skills': []}));
      await seedServer();
      final config = (await repository.listServers()).single;

      await repository.refreshCapabilities(config);

      final capabilities = await repository.cachedCapabilities(config.id);
      expect(capabilities.serverVersion, '0.9.1');
      expect(capabilities.confirmed(ServerCapability.profiles), isTrue);
      expect(capabilities.confirmed(ServerCapability.skills), isTrue);
      expect(
        capabilities.confirmed(ServerCapability.kanban),
        isFalse,
        reason: 'the fake answers 404 for routes it was not given',
      );
    });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/server_repository_test.dart`
Expected: compile errors (`connect` parameter, `cronJobs`, `refreshCapabilities` not defined).

- [ ] **Step 3: Update `lib/data/net/capabilities.dart`**

Replace the library doc's opening paragraph with:

```dart
/// What one particular dashboard can actually do.
///
/// Hermes ships fast and users self-host, so no two dashboards Iris talks to
/// are guaranteed to be the same build, and plugins such as Kanban are
/// optional. Iris asks the dashboard what it supports and adapts, rather than
/// pinning a version and declaring a user's own machine unsupported.
```

Replace the enum with:

```dart
enum ServerCapability {
  /// Named agent configurations, including bots.
  profiles('/api/profiles', 'Profiles'),

  /// Full-text search across sessions.
  sessionSearch('/api/sessions/search', 'Search'),

  /// Scheduled jobs and their runs.
  cronJobs('/api/cron/jobs', 'Scheduled jobs'),

  /// Installed skills.
  skills('/api/skills', 'Skills'),

  /// Toolsets, including speech providers.
  toolsets('/api/tools/toolsets', 'Tools'),

  /// The Kanban plugin's board.
  kanban('/api/plugins/kanban', 'Kanban'),

  /// Hermes Conduit's notifier plugin: push, live voice tokens, calls.
  conduitPlugin('/api/plugins/conduit_push/capabilities', 'Notifier plugin');

  const ServerCapability(this.probePath, this.label);

  /// A GET path whose response proves the capability exists.
  final String probePath;

  /// What the UI calls it.
  final String label;
}
```

In `ServerCapabilities`, change the `serverVersion` doc to `/// What /api/status reported, for display. Never used to gate a feature.`

In `CapabilityProbe.run`, replace the doc's first line with `/// Probes /api/status and every capability endpoint concurrently.` and replace the health block

```dart
    final health = await _client.get('/health');
    final version = switch (health) {
      Ok(:final value) => value.any([
        'version',
        'server_version',
        'build',
      ]).stringOrNull,
      Err() => null,
    };
    final challenged = health.failureOrNull?.kind == FailureKind.unauthorized;
```

with

```dart
    final status = await _client.get('/api/status');
    final version = switch (status) {
      Ok(:final value) => value['version'].stringOrNull,
      Err() => null,
    };
    final challenged = switch (status.failureOrNull?.kind) {
      FailureKind.unauthorized || FailureKind.accessGate => true,
      _ => false,
    };
```

- [ ] **Step 4: Rewrite `lib/data/repositories/server_repository.dart`**

```dart
/// Managing the servers Iris knows about.
///
/// One repository owns the whole lifecycle: adding a dashboard, keeping its
/// secrets, its HTTP connection and its live link, discovering what it
/// supports, and forgetting it completely. Splitting these across several
/// objects would mean several places that each know a little about
/// credentials, and the one that forgets to clear them is the bug.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/logging.dart';
import '../../core/result.dart';
import '../db/database.dart';
import '../net/capabilities.dart';
import '../net/credentials.dart';
import '../net/dashboard_auth.dart';
import '../net/server_config.dart';
import '../net/server_connection.dart';
import '../rpc/dashboard_session.dart';
import '../rpc/wire_socket.dart';

/// How a server is doing, right now.
enum ServerHealth {
  /// Not contacted since the app started.
  unknown,

  /// Connecting.
  checking,

  /// The live link is open.
  online,

  /// The saved login no longer works.
  unauthorized,

  /// An access proxy wants a (different) service token.
  gated,

  /// Not reachable at the moment; Iris keeps trying.
  offline,

  /// Reachable, but the certificate is not trusted.
  untrusted;

  /// What a live-link state means for the status shown beside a server.
  static ServerHealth fromLink(LinkState link) => switch (link.phase) {
    LinkPhase.idle => ServerHealth.unknown,
    LinkPhase.connecting => ServerHealth.checking,
    LinkPhase.live => ServerHealth.online,
    LinkPhase.retrying => ServerHealth.offline,
    LinkPhase.needsSignIn => ServerHealth.unauthorized,
    LinkPhase.blocked =>
      link.failure?.kind == FailureKind.tls
          ? ServerHealth.untrusted
          : ServerHealth.gated,
  };
}

/// A server plus everything currently known about it.
@immutable
final class ServerState {
  const ServerState({
    required this.config,
    this.health = ServerHealth.unknown,
    this.capabilities = const ServerCapabilities.unknown(),
    this.lastError,
    this.lastSeen,
  });

  final ServerConfig config;
  final ServerHealth health;
  final ServerCapabilities capabilities;
  final IrisFailure? lastError;
  final DateTime? lastSeen;

  bool get isUsable => health == ServerHealth.online;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerState &&
          other.config == config &&
          other.health == health &&
          other.lastSeen == lastSeen);

  @override
  int get hashCode => Object.hash(config, health, lastSeen);
}

/// Builds the HTTP side of a server. Replaced in tests.
typedef ServerConnectionFactory =
    ServerConnection Function(
      ServerConfig config, {
      required ServerSecrets secrets,
    });

/// Owns the set of known servers.
final class ServerRepository {
  ServerRepository({
    required IrisDatabase database,
    required CredentialStore credentials,
    ServerConnectionFactory? connect,
    WireConnector? connector,
  }) : _db = database,
       _credentials = credentials,
       _connect =
           connect ??
           ((config, {required secrets}) =>
               ServerConnection.create(config, secrets: secrets)),
       _connector = connector;

  static const _log = IrisLog('servers');

  final IrisDatabase _db;
  final CredentialStore _credentials;
  final ServerConnectionFactory _connect;
  final WireConnector? _connector;

  /// HTTP connections, one per server, kept because each carries a cookie
  /// jar: rebuilding one would discard the session and force a new login.
  final Map<String, ServerConnection> _connections = {};

  /// Live links, one per server that something is currently watching.
  final Map<String, DashboardSession> _sessions = {};
  final Map<String, StreamSubscription<LinkState>> _watchers = {};

  /// Every known server, in switcher order, as a live query.
  Stream<List<ServerConfig>> watchServers() =>
      (_db.select(_db.servers)..orderBy([
            (s) => OrderingTerm(expression: s.position),
            (s) => OrderingTerm(
              expression: s.lastConnectedAt,
              mode: OrderingMode.desc,
            ),
          ]))
          .watch()
          .map((rows) => rows.map(_toConfig).toList(growable: false));

  Future<List<ServerConfig>> listServers() async {
    final rows = await (_db.select(
      _db.servers,
    )..orderBy([(s) => OrderingTerm(expression: s.position)])).get();
    return rows.map(_toConfig).toList(growable: false);
  }

  static ServerConfig _toConfig(Server row) => ServerConfig(
    id: row.id,
    baseUrl: row.baseUrl,
    label: row.label,
    requiresPassword: row.requiresPassword,
    usesAccessToken: row.usesAccessToken,
    allowSelfSignedCertificate: row.allowSelfSigned,
  );

  /// Looks at [baseUrl] without saving anything, so the connect screen asks
  /// only for what this dashboard wants.
  Future<DashboardProbe> testConnection(
    String baseUrl, {
    bool allowSelfSigned = false,
    ServerSecrets secrets = ServerSecrets.none,
  }) async {
    final normalised = ServerConfig.normaliseBaseUrl(baseUrl);
    if (normalised.isEmpty) {
      return const DashboardProbe(
        access: DashboardAccess.unreachable,
        failure: IrisFailure(
          FailureKind.rejected,
          message: 'Enter a server address.',
        ),
      );
    }
    final probe = _connect(
      ServerConfig(
        id: 'probe',
        baseUrl: normalised,
        label: 'probe',
        allowSelfSignedCertificate: allowSelfSigned,
      ),
      secrets: secrets,
    );
    try {
      return await probe.auth.probe();
    } finally {
      probe.close();
    }
  }

  /// Saves a dashboard once its whole sign-in chain is proven.
  ///
  /// A server row the user cannot actually reach is worse than no row: it
  /// appears in the switcher and fails every time it is selected. So the login
  /// and a ticket mint both have to succeed first, and secrets are written only
  /// after that.
  Future<Result<ServerConfig>> addServer({
    required String baseUrl,
    required String label,
    ServerSecrets secrets = ServerSecrets.none,
    bool allowSelfSigned = false,
  }) async {
    final normalised = ServerConfig.normaliseBaseUrl(baseUrl);
    if (normalised.isEmpty) {
      return const Err(
        IrisFailure(FailureKind.rejected, message: 'Enter a server address.'),
      );
    }

    final existing = await listServers();
    if (existing.any((s) => s.baseUrl == normalised)) {
      return const Err(
        IrisFailure(
          FailureKind.rejected,
          message: 'That server has already been added.',
        ),
      );
    }

    final config = ServerConfig(
      id: _newId(),
      baseUrl: normalised,
      label: label.trim().isEmpty ? _labelFromUrl(normalised) : label.trim(),
      requiresPassword: secrets.hasLogin,
      usesAccessToken: secrets.hasAccessToken,
      allowSelfSignedCertificate: allowSelfSigned,
    );

    final connection = _connect(config, secrets: secrets);
    final proven = await _prove(connection, secrets);
    if (proven case Err(:final failure)) {
      connection.close();
      return Err(failure);
    }
    if (!secrets.isEmpty) {
      final stored = await _credentials.write(config.id, secrets);
      if (stored case Err(:final failure)) {
        connection.close();
        return Err(failure);
      }
    }

    await _db
        .into(_db.servers)
        .insert(
          ServersCompanion.insert(
            id: config.id,
            baseUrl: config.baseUrl,
            label: config.label,
            requiresPassword: Value(config.requiresPassword),
            usesAccessToken: Value(config.usesAccessToken),
            allowSelfSigned: Value(config.allowSelfSignedCertificate),
            lastConnectedAt: Value(DateTime.now()),
            position: Value(existing.length),
          ),
        );

    _connections[config.id] = connection;
    _log.info('added ${config.label}');
    return Ok(config);
  }

  /// Signs in if a login was given, then mints a ticket: the one request that
  /// proves the whole chain — access proxy, login, and the dashboard's
  /// willingness to open a live connection.
  static Future<Result<void>> _prove(
    ServerConnection connection,
    ServerSecrets secrets,
  ) async {
    if (secrets.hasLogin) {
      final signedIn = await connection.auth.signIn(
        username: secrets.username!.trim(),
        password: secrets.password!,
      );
      if (signedIn case Err(:final failure)) return Err(failure);
    }
    return (await connection.auth.mintTicket()).map((_) {});
  }

  /// The HTTP side of [config], built once with its stored secrets.
  Future<Result<ServerConnection>> connectionFor(ServerConfig config) async {
    if (_connections[config.id] case final existing?) return Ok(existing);
    final secrets = await _credentials.read(config.id);
    switch (secrets) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        // Checked again after the await: two callers can race to here.
        return Ok(
          _connections.putIfAbsent(config.id, () {
            _log.info('opening ${config.label}');
            return _connect(config, secrets: value);
          }),
        );
    }
  }

  /// The live link to [config], created once and kept until [release].
  ///
  /// Each time the link goes live the capability probe re-runs, so a plugin
  /// installed on the server since last time shows up without a restart.
  Future<Result<DashboardSession>> sessionFor(ServerConfig config) async {
    if (_sessions[config.id] case final existing?) return Ok(existing);
    final connection = await connectionFor(config);
    switch (connection) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        if (_sessions[config.id] case final raced?) return Ok(raced);
        final session = DashboardSession(http: value, connector: _connector);
        _sessions[config.id] = session;
        _watchers[config.id] = session.states.listen((state) {
          if (state.phase == LinkPhase.live) {
            unawaited(refreshCapabilities(config));
          }
        });
        return Ok(session);
    }
  }

  /// Stops [serverId]'s live link. Its sign-in is kept for next time.
  Future<void> release(String serverId) async {
    await _watchers.remove(serverId)?.cancel();
    await _sessions.remove(serverId)?.dispose();
  }

  /// Re-probes what [config] supports and records it.
  Future<void> refreshCapabilities(ServerConfig config) async {
    final connection = await connectionFor(config);
    if (connection case Ok(:final value)) {
      final capabilities = await CapabilityProbe(value.client).run();
      await (_db.update(
        _db.servers,
      )..where((s) => s.id.equals(config.id))).write(
        ServersCompanion(
          capabilitiesJson: Value(
            jsonEncode(capabilities.available.map((c) => c.name).toList()),
          ),
          probedAt: Value(capabilities.probedAt),
          serverVersion: Value(capabilities.serverVersion),
          lastConnectedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// What [serverId] was last found to support, as a live query.
  Stream<ServerCapabilities> watchCapabilities(String serverId) =>
      (_db.select(_db.servers)..where((s) => s.id.equals(serverId)))
          .watchSingleOrNull()
          .map(_capabilitiesOf);

  /// Reads back the last probe, so navigation renders before the network
  /// answers.
  Future<ServerCapabilities> cachedCapabilities(String serverId) async =>
      _capabilitiesOf(
        await (_db.select(
          _db.servers,
        )..where((s) => s.id.equals(serverId))).getSingleOrNull(),
      );

  static ServerCapabilities _capabilitiesOf(Server? row) {
    if (row == null || row.probedAt == null) {
      return const ServerCapabilities.unknown();
    }
    final names = {
      for (final name in Json.decode(row.capabilitiesJson).list)
        ?name.stringOrNull,
    };
    return ServerCapabilities(
      available: {
        for (final capability in ServerCapability.values)
          if (names.contains(capability.name)) capability,
      },
      probedAt: row.probedAt,
      serverVersion: row.serverVersion,
      requiresAuth: row.requiresPassword,
    );
  }

  Future<void> rename(ServerConfig config, String label) =>
      (_db.update(_db.servers)..where((s) => s.id.equals(config.id))).write(
        ServersCompanion(label: Value(label.trim())),
      );

  /// Removes a server and everything belonging to it.
  ///
  /// The secrets go first: if the database write fails halfway, the worst
  /// outcome should be an orphaned row, never an orphaned password.
  Future<void> forget(ServerConfig config) async {
    await _credentials.delete(config.id);
    await release(config.id);
    _connections.remove(config.id)?.close();
    await _db.forgetServer(config.id);
    _log.info('forgot ${config.label}');
  }

  void dispose() {
    for (final watcher in _watchers.values) {
      unawaited(watcher.cancel());
    }
    _watchers.clear();
    for (final session in _sessions.values) {
      unawaited(session.dispose());
    }
    _sessions.clear();
    for (final connection in _connections.values) {
      connection.close();
    }
    _connections.clear();
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// A default name derived from the address, so the user does not have to
  /// invent one to get started.
  static String _labelFromUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.isEmpty ? 'Server' : host;
  }
}
```

`?name.stringOrNull` in a set literal is Dart 3.8's null-aware element; the project already uses it in `failure.dart` (`?endpoint`).

- [ ] **Step 5: Keep the connect screen compiling**

The connect screen still calls the removed `testConnection` result fields until Task 11 rewrites it. To keep this task green, make the minimal edits in `lib/features/servers/connect_screen.dart`:
- Replace `import '../../data/net/session_auth.dart';` with `import '../../data/net/dashboard_auth.dart';`.
- In `_probe`, replace the body after `if (!mounted) return;` with:

```dart
    switch (attempt.access) {
      case DashboardAccess.password:
        setState(() {
          _serverVersion = attempt.version;
          _step = _Step.password;
        });
      case DashboardAccess.open:
        setState(() => _serverVersion = attempt.version);
        await _join();
      case _:
        setState(() {
          _step = _Step.address;
          _failure =
              attempt.failure ??
              const IrisFailure(
                FailureKind.rejected,
                message: 'Iris cannot connect to this dashboard yet.',
              );
        });
    }
```

- In `_join`, replace `password: _password.text.isEmpty ? null : _password.text,` with `secrets: ServerSecrets(password: _password.text.isEmpty ? null : _password.text),` and add `import '../../data/net/credentials.dart';`.

- [ ] **Step 6: Keep the providers compiling**

In `lib/app/providers.dart`, replace the whole `activeServerStateProvider` / `ActiveServerState` block (from the `/// Live health and capabilities` comment to the end of the file) with this interim version, which Task 10 replaces:

```dart
/// Health and capabilities for the active server. Interim: reads the cached
/// probe only, until the live link is wired in.
final activeServerStateProvider = FutureProvider<ServerState?>((ref) async {
  final config = ref.watch(activeServerProvider);
  if (config == null) return null;
  final capabilities = await ref
      .watch(serverRepositoryProvider)
      .cachedCapabilities(config.id);
  return ServerState(config: config, capabilities: capabilities);
});
```

Remove `import 'dart:async';`: its only users (`Timer`, `unawaited`) were in the replaced block. Task 10 adds it back.

In `lib/features/servers/server_switcher.dart`, add a `ServerHealth.gated` arm to both switches in `_HealthDot`:

```dart
      ServerHealth.gated => 'Access token needed',
```

and

```dart
      ServerHealth.unauthorized || ServerHealth.gated => AgentState.waiting,
```

(replacing the existing `ServerHealth.unauthorized => AgentState.waiting,` line).

- [ ] **Step 7: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/data/net/capabilities.dart lib/data/repositories/server_repository.dart lib/features/servers/connect_screen.dart lib/features/servers/server_switcher.dart lib/app/providers.dart test/data/server_repository_test.dart
git commit -m "feat(data): repository owns dashboard connections, sessions and probes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Providers for the live link

**Files:**
- Modify: `lib/app/providers.dart`
- Test: `test/app/providers_test.dart` (create)

**Interfaces:**
- Consumes: `ServerRepository.sessionFor/release/watchCapabilities`, `ServerHealth.fromLink`.
- Produces:
  - `activeSessionProvider`: `FutureProvider<DashboardSession?>`. Starts the session and releases it when the active server changes.
  - `activeLinkProvider`: `StreamProvider<LinkState>`.
  - `activeCapabilitiesProvider`: `StreamProvider<ServerCapabilities>`.
  - `activeServerStateProvider`: `Provider<AsyncValue<ServerState?>>` (the switcher reads `.value`, unchanged).

- [ ] **Step 1: Write the failing test**

Create `test/app/providers_test.dart`:

```dart
/// The provider graph around the live link.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/repositories/server_repository.dart';
import 'package:iris/data/rpc/dashboard_session.dart';

import '../support/fake_http.dart';
import '../support/fake_wire_socket.dart';
import '../support/fakes.dart';

void main() {
  test('a capability refresh does not reopen the socket', () async {
    final db = IrisDatabase(NativeDatabase.memory());
    final http = FakeHttp()
      ..on('POST', '/api/auth/ws-ticket', (_) => FakeReply.json({'ticket': 't'}))
      ..on('GET', '/api/status', (_) => FakeReply.json({'version': '1'}));
    var opened = 0;
    final repository = ServerRepository(
      database: db,
      credentials: FakeCredentialStore(),
      connect: (config, {required secrets}) =>
          ServerConnection.create(config, secrets: secrets, adapter: http),
      connector: (uri, headers) async {
        opened++;
        return FakeWireSocket();
      },
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        serverRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() async {
      container.dispose();
      repository.dispose();
      await db.close();
    });

    final added = await repository.addServer(
      baseUrl: 'https://h.example',
      label: 'H',
    );
    // The server list is a stream; until its first emission the active server
    // resolves to null and no session is created. Riverpod 3 pauses a provider
    // nobody listens to, so listen as a screen would before awaiting it.
    final servers = container.listen(serversProvider, (_, _) {});
    addTearDown(servers.close);
    await container.read(serversProvider.future);
    container.read(activeServerIdProvider.notifier).select(added.valueOrNull!.id);
    // Keep the link alive the way a screen would.
    final link = container.listen(activeLinkProvider, (_, _) {});
    addTearDown(link.close);

    final session = await container.read(activeSessionProvider.future);
    for (var i = 0; i < 100 && session?.state.phase != LinkPhase.live; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // Wait for the probe triggered by going live to write the servers row.
    for (var i = 0; i < 100; i++) {
      final caps = await repository.cachedCapabilities(added.valueOrNull!.id);
      if (caps.hasProbed) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(session?.state.phase, LinkPhase.live);
    expect(opened, 1, reason: 'rewriting the servers row must not restart the link');
    expect(
      container.read(activeServerStateProvider).value?.health,
      ServerHealth.online,
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/app/providers_test.dart`
Expected: compile error `Undefined name 'activeSessionProvider'`.

- [ ] **Step 3: Replace the interim provider in `lib/app/providers.dart`**

Add imports:

```dart
import 'dart:async';

import '../core/result.dart';
import '../data/net/capabilities.dart';
import '../data/rpc/dashboard_session.dart';
```

(keep the import list sorted per `directives_ordering`.)

Replace the interim `activeServerStateProvider` from Task 9 with:

```dart
/// The live link to the active server.
///
/// Started on first read and released when another server is chosen, so only
/// the server on screen holds a socket open. [activeServerProvider] compares
/// configs by id, so a rewrite of the same server's row — which every
/// capability probe makes — does not restart the link.
final activeSessionProvider = FutureProvider<DashboardSession?>((ref) async {
  final config = ref.watch(activeServerProvider);
  if (config == null) return null;
  final repository = ref.watch(serverRepositoryProvider);
  switch (await repository.sessionFor(config)) {
    case Err(:final failure):
      throw failure;
    case Ok(:final value):
      ref.onDispose(() => unawaited(repository.release(config.id)));
      unawaited(value.start());
      return value;
  }
});

/// Where the active server's live link is.
final activeLinkProvider = StreamProvider<LinkState>((ref) async* {
  final session = await ref.watch(activeSessionProvider.future);
  if (session == null) {
    yield const LinkState(LinkPhase.idle);
    return;
  }
  yield session.state;
  yield* session.states;
});

/// What the active server was last found to support.
final activeCapabilitiesProvider = StreamProvider<ServerCapabilities>((ref) {
  final config = ref.watch(activeServerProvider);
  if (config == null) return Stream.value(const ServerCapabilities.unknown());
  return ref.watch(serverRepositoryProvider).watchCapabilities(config.id);
});

/// Health and capabilities for the active server, together.
final activeServerStateProvider = Provider<AsyncValue<ServerState?>>((ref) {
  final config = ref.watch(activeServerProvider);
  if (config == null) return const AsyncData(null);
  final capabilities =
      ref.watch(activeCapabilitiesProvider).value ??
      const ServerCapabilities.unknown();
  return switch (ref.watch(activeLinkProvider)) {
    AsyncData(:final value) => AsyncData(
      ServerState(
        config: config,
        health: ServerHealth.fromLink(value),
        capabilities: capabilities,
        lastError: value.failure,
      ),
    ),
    AsyncError(:final error, :final stackTrace) => AsyncError(
      error,
      stackTrace,
    ),
    _ => const AsyncLoading(),
  };
});
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/app/providers.dart test/app/providers_test.dart
git commit -m "feat(app): providers for the active live link and capabilities

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Connect screen and the Phase 1 home

**Files:**
- Modify: `lib/features/servers/connect_screen.dart` (rewrite)
- Create: `lib/features/home/link_status_screen.dart`
- Modify: `lib/app/iris_app.dart` (home after connect)
- Test: `test/features/connect_screen_test.dart` (create)
- Test: `test/features/link_status_screen_test.dart` (create)

**Interfaces:**
- Consumes: `ServerRepository.testConnection/addServer`, `DashboardAccess`, `ServerSecrets`, `activeLinkProvider`, `activeCapabilitiesProvider`, `activeSessionProvider`, `showServerSwitcher`.
- Produces: `ConnectScreen` (same constructor); `LinkStatusScreen`; `(AgentState, String, String) describeLink(LinkState link)`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/connect_screen_test.dart`:

```dart
/// The connect flow asks for exactly what the dashboard wants.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/repositories/server_repository.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/servers/connect_screen.dart';

import '../support/fake_http.dart';
import '../support/fakes.dart';

void main() {
  late FakeHttp http;
  late IrisDatabase db;
  late ServerRepository repository;

  setUp(() {
    http = FakeHttp();
    db = IrisDatabase(NativeDatabase.memory());
    repository = ServerRepository(
      database: db,
      credentials: FakeCredentialStore(),
      connect: (config, {required secrets}) =>
          ServerConnection.create(config, secrets: secrets, adapter: http),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  Widget harness() {
    final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        serverRepositoryProvider.overrideWithValue(repository),
      ],
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: theme.materialTheme,
          home: Material(
            type: MaterialType.transparency,
            child: IrisTheme(data: theme, child: const ConnectScreen()),
          ),
        ),
      ),
    );
  }

  Future<void> submitAddress(WidgetTester tester, String address) async {
    await tester.enterText(find.byType(EditableText).first, address);
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets('an access-gated address asks for a service token', (
    tester,
  ) async {
    http.on('GET', '/api/auth/providers', (_) => FakeReply.cloudflareLogin());
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    expect(find.text('CLIENT ID'), findsOneWidget);
    expect(find.text('CLIENT SECRET'), findsOneWidget);
    expect(find.textContaining('did not accept'), findsNothing);
  });

  testWidgets('a rejected token says so', (tester) async {
    http.on('GET', '/api/auth/providers', (_) => FakeReply.cloudflareLogin());
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    await tester.enterText(find.byType(EditableText).at(1), 'id.access');
    await tester.enterText(find.byType(EditableText).at(2), 'wrong');
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('did not accept'), findsOneWidget);
  });

  testWidgets('a password dashboard asks for a username and password', (
    tester,
  ) async {
    http
      ..on(
        'GET',
        '/api/auth/providers',
        (_) => FakeReply.json({
          'providers': [
            {'name': 'basic', 'supports_password': true},
          ],
        }),
      )
      ..on('GET', '/api/status', (_) => FakeReply.json({'version': '0.9.1'}));
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    expect(find.text('USERNAME'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.textContaining('0.9.1'), findsOneWidget);
  });

  testWidgets('a non-Hermes address explains the port', (tester) async {
    http.on('GET', '/api/auth/providers', (_) => FakeReply.html('<html/>'));
    await tester.pumpWidget(harness());
    await submitAddress(tester, 'https://h.example');
    // IrisLabel renders titles in capitals.
    expect(find.text('NOT A HERMES DASHBOARD'), findsOneWidget);
  });
}
```

Create `test/features/link_status_screen_test.dart`:

```dart
/// The Phase 1 home tells the truth about the link.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/data/net/capabilities.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/home/link_status_screen.dart';

void main() {
  Widget harness(LinkState link, {ServerCapabilities? capabilities}) {
    final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
    return ProviderScope(
      overrides: [
        activeServerProvider.overrideWithValue(
          const ServerConfig(
            id: 's',
            baseUrl: 'https://h.example',
            label: 'Home',
          ),
        ),
        activeLinkProvider.overrideWith((ref) => Stream.value(link)),
        activeCapabilitiesProvider.overrideWith(
          (ref) => Stream.value(
            capabilities ?? const ServerCapabilities.unknown(),
          ),
        ),
      ],
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: theme.materialTheme,
          home: Material(
            type: MaterialType.transparency,
            child: IrisTheme(data: theme, child: const LinkStatusScreen()),
          ),
        ),
      ),
    );
  }

  testWidgets('live shows connected and the version', (tester) async {
    await tester.pumpWidget(
      harness(
        const LinkState(LinkPhase.live),
        capabilities: ServerCapabilities(
          available: const {ServerCapability.profiles},
          probedAt: DateTime(2026),
          serverVersion: '0.9.1',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('0.9.1'), findsOneWidget);
    expect(find.text('Profiles'), findsOneWidget);
  });

  testWidgets('an access gate is named', (tester) async {
    await tester.pumpWidget(
      harness(
        const LinkState(
          LinkPhase.blocked,
          failure: IrisFailure(FailureKind.accessGate),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Blocked by Cloudflare Access'), findsOneWidget);
    expect(find.text('Try again now'), findsOneWidget);
  });
}
```

Only `IrisLabel` (field labels, section labels, failure titles) renders in capitals; `IrisChip`, `IrisButton` and plain `Text` keep their case.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features`
Expected: compile errors: `link_status_screen.dart` does not exist, and `CLIENT ID` is not found.

- [ ] **Step 3: Rewrite `lib/features/servers/connect_screen.dart`**

```dart
/// Connecting to a Hermes dashboard.
///
/// This is the first screen anyone sees, and the one most likely to fail: the
/// person is typing an address for a machine on their own network or behind
/// Cloudflare Access, possibly with a certificate they signed themselves. Every
/// one of those has a distinct failure, and a single "could not connect" would
/// leave them guessing which.
///
/// So the flow probes before it commits: find out whether the address answers,
/// whether an access proxy stands in front, and whether the dashboard wants a
/// login, then ask for exactly what is missing. Nothing is saved until the
/// dashboard has issued a live-connection ticket.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../core/result.dart';
import '../../data/net/credentials.dart';
import '../../data/net/dashboard_auth.dart';
import '../../data/net/server_config.dart';
import '../../design/components/aperture.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';

/// Where the flow is.
enum _Step {
  /// Typing an address.
  address,

  /// Contacting it.
  probing,

  /// Cloudflare Access is in front; asking for a service token.
  accessToken,

  /// The dashboard wants a username and password.
  login,

  /// Signing in, proving a ticket, saving.
  joining,
}

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({this.onConnected, super.key});

  /// Called once a server is saved and reachable.
  final ValueChanged<ServerConfig>? onConnected;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _address = TextEditingController();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();

  _Step _step = _Step.address;
  IrisFailure? _failure;
  String? _version;
  bool _allowSelfSigned = false;

  @override
  void dispose() {
    for (final controller in [
      _address,
      _clientId,
      _clientSecret,
      _username,
      _password,
      _label,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _busy => _step == _Step.probing || _step == _Step.joining;

  static String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  /// What has been typed so far. The password is not trimmed: a leading or
  /// trailing space can be part of it.
  ServerSecrets get _secrets => ServerSecrets(
    username: _text(_username),
    password: _password.text.isEmpty ? null : _password.text,
    accessClientId: _text(_clientId),
    accessClientSecret: _text(_clientSecret),
  );

  Future<void> _probe() async {
    setState(() {
      _step = _Step.probing;
      _failure = null;
    });

    final probe = await ref
        .read(serverRepositoryProvider)
        .testConnection(
          _address.text,
          allowSelfSigned: _allowSelfSigned,
          secrets: _secrets,
        );
    if (!mounted) return;

    switch (probe.access) {
      case DashboardAccess.accessGate:
        setState(() {
          _step = _Step.accessToken;
          // A token was entered and still bounced: say it was rejected, not
          // that one is needed.
          _failure = _secrets.hasAccessToken
              ? const IrisFailure(
                  FailureKind.accessGate,
                  message: 'Cloudflare did not accept this service token.',
                )
              : null;
        });
      case DashboardAccess.password:
        setState(() {
          _version = probe.version;
          _step = _Step.login;
        });
      case DashboardAccess.open:
        setState(() => _version = probe.version);
        await _join();
      case DashboardAccess.browserOnly:
        setState(() {
          _step = _Step.address;
          _failure = const IrisFailure(
            FailureKind.rejected,
            message:
                'This dashboard only offers browser sign-in, which Iris does '
                'not support yet. Turn on password login for the dashboard to '
                'connect.',
          );
        });
      case DashboardAccess.notHermes:
        setState(() {
          _step = _Step.address;
          _failure = const IrisFailure(FailureKind.notFound);
        });
      case DashboardAccess.unreachable:
        setState(() {
          _step = _Step.address;
          _failure = probe.failure;
        });
    }
  }

  Future<void> _join() async {
    setState(() {
      _step = _Step.joining;
      _failure = null;
    });

    final result = await ref
        .read(serverRepositoryProvider)
        .addServer(
          baseUrl: _address.text,
          label: _label.text,
          secrets: _secrets,
          allowSelfSigned: _allowSelfSigned,
        );
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        ref.read(activeServerIdProvider.notifier).select(value.id);
        widget.onConnected?.call(value);
      case Err(:final failure):
        setState(() {
          // Back to whichever step can actually fix this.
          _step = switch (failure.kind) {
            FailureKind.unauthorized => _Step.login,
            FailureKind.accessGate => _Step.accessToken,
            _ => _Step.address,
          };
          _failure = failure;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final window = context.window;

    return IrisScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: window.gutter),
        child: ReadableColumn(
          maxWidth: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: window.isCramped ? IrisSpace.lg : IrisSpace.huge),
              Aperture(
                state: switch (_step) {
                  _Step.address => AgentState.idle,
                  _Step.probing => AgentState.thinking,
                  _Step.accessToken || _Step.login => AgentState.waiting,
                  _Step.joining => AgentState.working,
                },
                size: 40,
              ),
              const SizedBox(height: IrisSpace.lg),
              Text('Connect to your agent', style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                'Iris talks directly to the Hermes dashboard on your own '
                'hardware. Nothing goes through anyone else.',
                style: theme.typography.body.copyWith(
                  color: theme.palette.inkMuted,
                ),
              ),
              const SizedBox(height: IrisSpace.xl),
              ..._fields(context),
              if (_failure case final failure?) ...[
                const SizedBox(height: IrisSpace.lg),
                _FailureNote(
                  failure: failure,
                  onAllowSelfSigned: failure.kind == FailureKind.tls
                      ? () {
                          setState(() => _allowSelfSigned = true);
                          unawaited(_probe());
                        }
                      : null,
                ),
              ],
              const SizedBox(height: IrisSpace.xl),
              _primaryAction(),
              const SizedBox(height: IrisSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressField({bool autofocus = false}) => IrisField(
    label: 'Server address',
    controller: _address,
    mono: true,
    hint: 'https://hermes.example.com',
    keyboardType: TextInputType.url,
    autofocus: autofocus,
    onSubmitted: autofocus ? (_) => _probe() : null,
  );

  List<Widget> _fields(BuildContext context) => switch (_step) {
    _Step.address || _Step.probing => [
      _addressField(autofocus: true),
      const SizedBox(height: IrisSpace.md),
      _AddressHint(allowSelfSigned: _allowSelfSigned),
    ],
    // The address stays visible and editable on later steps, because "wrong
    // token" and "right token, wrong server" look identical from here.
    _Step.accessToken => [
      _addressField(),
      const SizedBox(height: IrisSpace.md),
      Text(
        'Cloudflare Access protects this address. Iris needs a service token '
        'to pass it: in Cloudflare Zero Trust, create one under Access → '
        'Service credentials, then add a Service Auth policy for it on this '
        'application.',
        style: context.type.caption.copyWith(color: context.palette.inkMuted),
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Client ID',
        controller: _clientId,
        mono: true,
        hint: '….access',
        autofocus: true,
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Client secret',
        controller: _clientSecret,
        mono: true,
        obscure: true,
        onSubmitted: (_) => _probe(),
      ),
    ],
    _Step.login || _Step.joining => [
      _addressField(),
      const SizedBox(height: IrisSpace.sm),
      // Confirmation that the address reached a real dashboard before the
      // password is typed. Without it, a wrong address and a wrong password
      // produce the same dead end.
      IrisChip.state(
        _version == null
            ? 'Hermes dashboard found'
            : 'Hermes dashboard found, version $_version',
        AgentState.done,
        context.palette,
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Username',
        controller: _username,
        autofocus: _step == _Step.login,
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Password',
        controller: _password,
        obscure: true,
        onSubmitted: (_) => _join(),
      ),
      const SizedBox(height: IrisSpace.lg),
      IrisField(
        label: 'Name (optional)',
        controller: _label,
        hint: 'Home server',
      ),
    ],
  };

  Widget _primaryAction() => IrisButton(
    label: switch (_step) {
      _Step.address || _Step.accessToken => 'Continue',
      _Step.probing => 'Contacting the server',
      _Step.login => 'Sign in',
      _Step.joining => 'Connecting',
    },
    tone: IrisButtonTone.primary,
    expand: true,
    busy: _busy,
    onPressed: _busy
        ? null
        : switch (_step) {
            _Step.address || _Step.accessToken => _probe,
            _Step.login => _join,
            _ => null,
          },
  );
}

/// Guidance under the address field.
///
/// Written to answer the question people actually have at this moment, which is
/// "what do I type", not "what is a reverse proxy".
class _AddressHint extends StatelessWidget {
  const _AddressHint({required this.allowSelfSigned});

  final bool allowSelfSigned;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Use the address of the Hermes dashboard: the one you open in a '
          'browser, usually on port 9119. A tunnel, Tailscale or a local '
          'address on the same network all work.',
          style: theme.typography.caption.copyWith(
            color: theme.palette.inkMuted,
          ),
        ),
        if (allowSelfSigned) ...[
          const SizedBox(height: IrisSpace.sm),
          IrisChip.state(
            'Trusting this certificate',
            AgentState.waiting,
            theme.palette,
          ),
        ],
      ],
    );
  }
}

/// What went wrong, and what to do about it.
class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.failure, this.onAllowSelfSigned});

  final IrisFailure failure;
  final VoidCallback? onAllowSelfSigned;

  /// Plain-language cause and remedy per failure kind.
  ///
  /// The server's own message is appended rather than replacing this, because
  /// it is usually accurate but rarely actionable on its own.
  (String, String) get _advice => switch (failure.kind) {
    FailureKind.offline => (
      'No answer from that address',
      'Check the address, and that the server is running and reachable from '
          'this phone. A local address only works on the same network.',
    ),
    FailureKind.tls => (
      'The certificate is not trusted',
      'This is normal for a server using a self-signed certificate. Only '
          'continue if this is your own machine and you recognise the address.',
    ),
    FailureKind.timeout => (
      'The server took too long',
      'It may be waking up, or the tunnel may be slow. Try again.',
    ),
    FailureKind.unauthorized => (
      'That login was not accepted',
      'Use the username and password set for the Hermes dashboard. Some '
          'servers rate-limit repeated attempts for a minute.',
    ),
    FailureKind.accessGate => (
      'Cloudflare Access is in the way',
      'Check the service token’s Client ID and secret, and that this '
          'application has a Service Auth policy that includes the token.',
    ),
    FailureKind.notFound => (
      'Not a Hermes dashboard',
      'Check the address and port. Iris connects to the Hermes dashboard '
          '(usually port 9119), not to hermes-webui.',
    ),
    _ => (
      'Could not connect',
      failure.message ?? 'Something went wrong reaching that server.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final (title, detail) = _advice;

    return IrisCard(
      accent: palette.colorFor(AgentState.failed),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IrisLabel(title, color: palette.colorFor(AgentState.failed)),
          const SizedBox(height: IrisSpace.sm),
          Text(detail, style: theme.typography.body),
          if (failure.message case final message?
              when failure.kind != FailureKind.unknown && message != detail) ...[
            const SizedBox(height: IrisSpace.sm),
            Text(
              message,
              style: theme.typography.codeSmall.copyWith(
                color: palette.inkMuted,
              ),
            ),
          ],
          if (onAllowSelfSigned case final allow?) ...[
            const SizedBox(height: IrisSpace.md),
            IrisButton(label: 'Trust it and continue', onPressed: allow),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Create `lib/features/home/link_status_screen.dart`**

```dart
/// Phase 1's home: the state of the live link, and nothing else yet.
///
/// Chat replaces this in Phase 2. Until then it is the one place that shows
/// whether Iris actually holds a connection, which has to be verified on a
/// device before anything is built on top of it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/failure.dart';
import '../../data/net/capabilities.dart';
import '../../data/rpc/dashboard_session.dart';
import '../../design/components/aperture.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import '../servers/server_switcher.dart';

/// The aperture state, headline and explanation for [link].
(AgentState, String, String) describeLink(LinkState link) {
  final tls = link.failure?.kind == FailureKind.tls;
  return switch (link.phase) {
    LinkPhase.idle || LinkPhase.connecting => (
      AgentState.thinking,
      'Connecting',
      'Opening a live connection to the dashboard.',
    ),
    LinkPhase.live => (
      AgentState.done,
      'Connected',
      'Iris holds a live connection to your agent. Conversations arrive in the '
          'next update.',
    ),
    LinkPhase.retrying => (
      AgentState.waiting,
      'Reconnecting',
      'The connection dropped. Trying again in '
          '${link.retryIn?.inSeconds ?? 1}s.',
    ),
    LinkPhase.needsSignIn => (
      AgentState.failed,
      'Sign-in needed',
      'The dashboard no longer accepts the saved login. Remove this server and '
          'add it again with the current password.',
    ),
    LinkPhase.blocked => (
      AgentState.failed,
      tls ? 'Certificate not trusted' : 'Blocked by Cloudflare Access',
      tls
          ? 'The server’s certificate changed or is not trusted. Remove and '
                're-add the server to review it.'
          : 'The access proxy turned Iris away. Check the service token and the '
                'application’s Service Auth policy.',
    ),
  };
}

class LinkStatusScreen extends ConsumerWidget {
  const LinkStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(activeServerProvider);
    final link =
        ref.watch(activeLinkProvider).value ??
        const LinkState(LinkPhase.connecting);
    final capabilities =
        ref.watch(activeCapabilitiesProvider).value ??
        const ServerCapabilities.unknown();
    final theme = context.iris;
    final palette = theme.palette;
    final (state, headline, detail) = describeLink(link);
    final stuck = switch (link.phase) {
      LinkPhase.retrying || LinkPhase.needsSignIn || LinkPhase.blocked => true,
      _ => false,
    };

    return IrisScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: context.window.gutter),
        child: ReadableColumn(
          maxWidth: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: IrisSpace.huge),
              Aperture(state: state, size: 40),
              const SizedBox(height: IrisSpace.lg),
              Text(headline, style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                detail,
                style: theme.typography.body.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: IrisSpace.xl),
              IrisListRow(
                title: server?.label ?? 'No server',
                subtitle: server?.baseUrl,
                onTap: () => unawaited(showServerSwitcher(context)),
              ),
              if (capabilities.serverVersion case final version?) ...[
                const SizedBox(height: IrisSpace.sm),
                IrisChip.state('Hermes $version', AgentState.done, palette),
              ],
              const SizedBox(height: IrisSpace.lg),
              const IrisLabel('On this server'),
              const SizedBox(height: IrisSpace.sm),
              Wrap(
                spacing: IrisSpace.xs,
                runSpacing: IrisSpace.xs,
                children: [
                  for (final capability in ServerCapability.values)
                    IrisChip.state(
                      capability.label,
                      capabilities.confirmed(capability)
                          ? AgentState.done
                          : AgentState.idle,
                      palette,
                    ),
                ],
              ),
              if (stuck) ...[
                const SizedBox(height: IrisSpace.xl),
                IrisButton(
                  label: 'Try again now',
                  tone: IrisButtonTone.primary,
                  expand: true,
                  onPressed: () => unawaited(
                    ref.read(activeSessionProvider).value?.reconnectNow(),
                  ),
                ),
              ],
              const SizedBox(height: IrisSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Point the app at it**

In `lib/app/iris_app.dart`, replace `import '../features/design_gallery/design_gallery.dart';` with `import '../features/home/link_status_screen.dart';` (keep imports sorted) and `connected: (context) => const DesignGallery(),` with `connected: (context) => const LinkStatusScreen(),`.

- [ ] **Step 6: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!` (goldens are unaffected; the gallery is still rendered directly by its tests).

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features lib/app/iris_app.dart test/features
git commit -m "feat(ui): dashboard connect flow with Access token step, link status home

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Remove the hermes-webui transport

**Files:**
- Delete: `lib/data/net/session_auth.dart`, `lib/data/sse/sse_client.dart`, `lib/data/sse/sse_frame.dart`, `lib/data/sse/sse_parser.dart`, `lib/data/models/stream_event.dart`
- Delete: `test/data/sse_parser_test.dart`, `test/data/stream_event_test.dart`
- Modify: `README.md`, and doc comments mentioning hermes-webui in `lib/`

- [ ] **Step 1: Confirm nothing still imports them**

Run: `grep -rnE "session_auth|sse/|stream_event" lib test --include=*.dart`
Expected: matches only inside the files being deleted.

- [ ] **Step 2: Delete them**

```bash
git rm lib/data/net/session_auth.dart lib/data/sse/sse_client.dart lib/data/sse/sse_frame.dart lib/data/sse/sse_parser.dart lib/data/models/stream_event.dart test/data/sse_parser_test.dart test/data/stream_event_test.dart
```

- [ ] **Step 3: Update the remaining webui references**

Run: `grep -rn "webui\|WebUI" lib --include=*.dart`

For each hit outside `lib/data/models/` (which Phase 2 rewrites), change the wording to "the Hermes dashboard". Expected hits: `lib/core/json.dart` (library doc: "The Hermes WebUI server evolves quickly" → "The Hermes dashboard evolves quickly"), `lib/features/servers/pairing_payload.dart` ("hermes-webui does not define a pairing format" → "The Hermes dashboard does not define a pairing format").

In `README.md`:
- Replace the first paragraph's link text with: `A Flutter client for [Hermes Agent](https://github.com/NousResearch/hermes-agent), talking to your own Hermes dashboard (the agent's built-in web dashboard, default port 9119).`
- Replace the Status section with:

```markdown
## Status

Phases 0 (foundation), 1 (design system) and the dashboard transport are complete: Iris signs
in (through Cloudflare Access when the dashboard sits behind it), holds a live JSON-RPC
connection that reconnects by itself, and shows its state. Chat is next.
```

- In Architecture, replace the `sse/` line with `    rpc/      JSON-RPC over WebSocket: frames, client, live session`.
- Replace the "Reconnection is normal." paragraph with:

```markdown
**Reconnection is normal.** A phone loses its connection constantly while the agent keeps
working. `DashboardSession` mints a fresh single-use ticket and reopens the socket with backoff,
signing in again first if the session cookie expired. An access-proxy refusal or an untrusted
certificate stops it instead, because retrying cannot fix either.
```

- Add to Environment notes:

```markdown
- **Cloudflare Access.** A dashboard published behind Access needs a service token (Zero Trust
  → Access → Service credentials) and a *Service Auth* policy on the application. Iris sends it
  as `CF-Access-Client-Id` / `CF-Access-Client-Secret`, over HTTPS only.
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add -A lib test README.md
git commit -m "chore: remove the hermes-webui transport

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Verify against the real dashboard

Automated tests prove the logic against fakes. This task proves it against `https://hermes.shreyaskamat.in`. **The user supplies the secrets; they are never pasted into the chat or committed.**

**Files:**
- Create: `test/live/dashboard_live_test.dart`
- Modify: `dart_test.yaml` (create) to keep live tests out of the default run

- [ ] **Step 1: The user prepares access** (manual, by the user)

1. In Cloudflare Zero Trust → Access → Service credentials → *Create Service Token*. Copy the Client ID and Client Secret.
2. In Access → Applications → the `hermes.shreyaskamat.in` application → Policies → add a policy with **Action: Service Auth** that includes that token.
3. Create `%USERPROFILE%\.iris-live.json` (outside the repository) with an editor:

```json
{
  "base_url": "https://hermes.shreyaskamat.in",
  "username": "<dashboard username>",
  "password": "<dashboard password>",
  "cf_client_id": "<id>.access",
  "cf_client_secret": "<secret>"
}
```

Check: `curl -s -o /dev/null -w "%{http_code}\n" -H "CF-Access-Client-Id: <id>" -H "CF-Access-Client-Secret: <secret>" https://hermes.shreyaskamat.in/api/status`, run by the user, prints `200`.

- [ ] **Step 2: Write the live test**

Create `dart_test.yaml` at the project root:

```yaml
# Live tests reach a real server and need ~/.iris-live.json; run them with
#   flutter test --tags live --run-skipped test/live
tags:
  live:
    skip: "live: run explicitly with --tags live"
```

Create `test/live/dashboard_live_test.dart`:

```dart
/// The transport against a real dashboard.
///
/// Reads its target and secrets from `~/.iris-live.json`, outside the
/// repository, so nothing secret can be committed. Prints only shapes — event
/// types, response keys, the version — never content: the server holds real
/// conversations.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/net/credentials.dart';
import 'package:iris/data/net/dashboard_auth.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/data/rpc/rpc_frame.dart';

File get _configFile => File(
  '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}'
  '/.iris-live.json',
);

void main() {
  late ServerConfig config;
  late ServerSecrets secrets;

  setUpAll(() {
    final json = Json.decode(_configFile.readAsStringSync());
    config = ServerConfig(
      id: 'live',
      baseUrl: ServerConfig.normaliseBaseUrl(json['base_url'].string()),
      label: 'live',
    );
    secrets = ServerSecrets(
      username: json['username'].stringOrNull,
      password: json['password'].stringOrNull,
      accessClientId: json['cf_client_id'].stringOrNull,
      accessClientSecret: json['cf_client_secret'].stringOrNull,
    );
  });

  test('the dashboard is found behind its access proxy', () async {
    final connection = ServerConnection.create(config, secrets: secrets);
    addTearDown(connection.close);
    final probe = await connection.auth.probe();
    stdout.writeln('probe: ${probe.access.name}, version ${probe.version}');
    expect(
      probe.access,
      anyOf(DashboardAccess.password, DashboardAccess.open),
      reason: '${probe.failure}',
    );
  });

  test(
    'a live link opens, answers ping, and streams',
    () async {
      final connection = ServerConnection.create(config, secrets: secrets);
      final session = DashboardSession(http: connection);
      final types = <String>{};
      final subscription = session.events.listen((e) => types.add(e.type));
      addTearDown(() async {
        await subscription.cancel();
        await session.dispose();
        connection.close();
      });

      await session.start();
      expect(session.state.phase, LinkPhase.live, reason: '${session.state}');

      final ping = await session.call(
        'ping',
        timeout: const Duration(seconds: 10),
      );
      expect(
        ping.isOk || (ping.failureOrNull?.rpcError?.isMethodNotFound ?? false),
        isTrue,
        reason: '$ping',
      );

      final catalog = await session.call('commands.catalog');
      stdout.writeln(
        'commands.catalog: ${catalog.valueOrNull?.keys ?? catalog.failureOrNull}',
      );

      await Future<void>.delayed(const Duration(seconds: 3));
      stdout.writeln('event types seen: $types');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
```

- [ ] **Step 3: Confirm the default suite skips it**

Run: `flutter test`
Expected: `All tests passed!` with the two live tests reported as skipped.

- [ ] **Step 4: Run it against the real server**

Run: `flutter test --tags live --run-skipped test/live`
Expected: both pass. The output shows `probe: password` (or `open`), a version, `commands.catalog` keys, and an event-type set containing `gateway.ready`.

If the probe says `accessGate`, the token or its Service Auth policy is wrong (Step 1). If the link reaches `needsSignIn`, the username or password is wrong. **Record the actual version, the catalog keys and the event types in the commit message**; Phase 2 is written against them.

- [ ] **Step 5: Verify on a device**

The emulator was degraded at the last session (a stuck splash layer, PowerManager crashes after 22 hours of uptime). Cold-boot it first:

```bash
flutter emulators            # find the AVD id
flutter emulators --launch <id> --cold   # or: emulator -avd <id> -no-snapshot-load
flutter devices              # confirm it is listed
flutter run -d <device-id>
```

On the device:
1. Enter `https://hermes.shreyaskamat.in` → **Continue** → the Cloudflare Access step appears.
2. Enter the Client ID and secret → **Continue** → the login step shows "Hermes dashboard found, version …".
3. Enter the username and password → **Sign in** → the home shows **Connected** and the version, with capability chips lit.
4. Turn on airplane mode → within ~25s the home shows **Reconnecting**. Turn it off → it returns to **Connected** without any input.
5. Kill and relaunch the app → it goes straight to **Connected** (the secrets come back from the keystore; the session re-signs in).

Run `flutter build apk --debug 2>&1 | grep -iE "FAILURE|error:|Built"` and expect `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 6: Commit**

```bash
git add dart_test.yaml test/live/dashboard_live_test.dart
git commit -m "test(live): dashboard transport verified against the real server

Dashboard version: <from Step 4>
commands.catalog keys: <from Step 4>
Event types on connect: <from Step 4>
Device check: connect, Access step, login, airplane-mode reconnect, relaunch — all pass.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
