# Welcome, connection modes and the demo: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A first-run welcome screen (Same Wi-Fi, Tailscale, Cloudflare, Try the demo), plain `http` for private
addresses only, and an offline scripted demo that runs every main screen without a server.

**Architecture:** A `ConnectionMode` saved with each server changes only the connect screen's wording. The demo is a
`DemoWorld` (in-memory conversations plus a `ScriptPlayer` that emits the same `ChatEvent`s the gateway sends) behind
the existing `ChatBackend` seam. A `demoSessionProvider` holds the world; the active server, link, capabilities,
session and chat providers return demo values first when it is set, so no screen below home changes.

**Tech Stack:** Flutter, Riverpod 3 (hand-written providers), Drift (schema 3 → 4, `build_runner`), Dio.

**Spec:** `docs/superpowers/specs/2026-10-15-welcome-and-demo-design.md`

## Global Constraints

- Branch `feat/welcome-and-demo`. Commits are under the user's name with **no `Co-Authored-By` trailer**.
- Format only files you touched: `dart format <file> ...`. Never run `dart format lib test`: the repo is not in default
  format and it rewrites about 60 files.
- `flutter analyze` must report no issues and `flutter test` must pass at the end of every task.
- Plain `http` is allowed only when `isPrivateHost` is true; any other `http` address is refused before a request,
  with exactly: `Use https for an address on the internet.`
- The demo never touches the network, the database, secure storage or preferences, and is never persisted.
- The fallback reply is exactly: `This is a demo, so replies are pre-written and I can't act on that. Try one of the
  suggestions, or [connect your own Hermes server](iris://leave-demo) to talk to your agent.`
- Demo content uses made-up hosts, names and keys only.
- Iris design rules: tokens from `lib/design/tokens`, `IrisPressable` or `IrisListRow` for tappable rows, reduced
  motion respected, a semantics label on every tappable thing.
- Riverpod 3 pauses providers nobody listens to: in container tests, `container.listen(provider, (_, _) {})` before
  awaiting `.future`.

## Review Focus

1. **A LAN or Tailscale address typed without a scheme** (`192.168.1.20:9119`) in Same Wi-Fi or Tailscale mode: a
   person expects it to work, so it must go out as `http`, not the `https` that `normaliseBaseUrl` adds. Pinned in
   Task 2 (`addressFor`) and Task 4 (a widget test checking the request's scheme).
2. **Leaving the demo from inside a chat** through the fallback reply's link: the person expects the welcome screen,
   not a chat screen left on top over a disposed demo. Pinned in Task 9.
3. **Pressing Stop while an approval or sudo card is waiting**: the card must go, the turn must end, and nothing may
   stay "running". Pinned in Task 6.
4. **Switching profile in the demo while a script runs in the other profile**: the list must swap and the running
   script must finish without an error. Pinned in Task 7.
5. **Tapping the connection line in the demo**: it must not offer the server switcher or "Add server", which would
   leave a real server selected under a demo that overrides it. Pinned in Task 9.

## File map

| File | Responsibility |
|---|---|
| `lib/data/net/connection_mode.dart` (new) | `ConnectionMode` enum and its stored name |
| `lib/data/net/private_host.dart` (new) | `isPrivateHost`, `plainHttpAllowed`, `addressFor` |
| `lib/data/net/server_config.dart` | adds `mode` |
| `lib/data/db/database.dart`, `database.g.dart` | `connection_mode` column, schema 4 |
| `lib/data/repositories/server_repository.dart` | saves and reads `mode` |
| `lib/features/servers/connection_mode_copy.dart` (new) | per-mode titles, lines, examples, help, icons |
| `lib/features/servers/connect_screen.dart` | takes a `mode`; wording, "Change", http refusal, default scheme |
| `lib/features/servers/welcome_screen.dart` (new) | the four choices |
| `lib/features/servers/server_gate.dart`, `server_switcher.dart` | open the welcome screen |
| `lib/features/home/link_status_screen.dart` | shows the mode; no switcher in demo |
| `lib/demo/demo_script.dart` (new) | script step types |
| `lib/demo/script_player.dart` (new) | plays steps as `ChatEvent`s |
| `lib/demo/demo_content.dart` (new) | seed conversations, profiles, models, scripts (data only) |
| `lib/demo/demo_world.dart` (new) | the demo's in-memory state and behaviour |
| `lib/demo/demo_chat_backend.dart` (new) | `ChatBackend` over a `DemoWorld` for one profile |
| `lib/demo/demo_mode.dart` (new) | `demoSessionProvider`, `demoModeProvider`, `demoServer`, `leaveDemo` |
| `lib/app/providers.dart` | demo branches |
| `lib/features/chat/conversation_list_screen.dart` | Demo pill; demo suggestions into chats |
| `lib/features/chat/chat_screen.dart` | optional `suggestions` |
| `lib/features/chat/transcript_view.dart` | `iris://leave-demo` |
| `lib/features/settings/settings_screen.dart` | "Leave demo" |
| `ios/Runner/Info.plist`, maybe `android/app/src/main/AndroidManifest.xml` | local network, cleartext |

---

### Task 1: Find out whether release builds can reach plain http

This decides whether Android needs `usesCleartextTraffic`. It produces a recorded finding, not code to keep, plus the
iOS Local Network string, which is needed regardless.

**Files:**
- Modify: `ios/Runner/Info.plist`
- Maybe modify: `android/app/src/main/AndroidManifest.xml`
- Create: `docs/superpowers/plans/2026-10-15-cleartext-check.md`

- [ ] **Step 1: Serve plain HTTP on the development machine.** In a scratch folder (not the repo):

```bash
mkdir -p "$TEMP/cleartext" && cd "$TEMP/cleartext" && echo '{"hello":"iris"}' > index.html
python -m http.server 8799
```

Leave it running (use the Bash tool's `run_in_background`). Stop it at the end of this task by killing **only that
process**: note its PID from `netstat -ano | grep 8799` and `taskkill //PID <pid> //F`. Never `taskkill //IM python.exe`.

- [ ] **Step 2: Build and install a release APK.**

```bash
flutter build apk --release
adb uninstall com.example.iris; adb uninstall com.iflotech.iris
adb install build/app/outputs/flutter-apk/app-release.apk
```

(One of the two uninstalls will report "not installed"; that is fine. The emulator's `/data` is nearly full, so the
old build must go first.)

- [ ] **Step 3: Point the app at the host machine.** Launch Iris, take a screenshot (`adb exec-out screencap -p >
"$SCRATCH/c1.png"`) and look at it before every tap. Type `http://10.0.2.2:8799` into the address field and press
Continue. Screenshot again.

Read the result:
- A failure note titled **"Not a Hermes dashboard"** means the request reached the server: cleartext is **allowed**.
- A note mentioning cleartext, or "No answer from that address" while the Python server logs no request, means it was
  **blocked**.

Confirm with the Python server's output: a `GET /api/...` line proves the request arrived.

- [ ] **Step 4: Only if blocked**, add to the `<application ...>` tag in `android/app/src/main/AndroidManifest.xml`:

```xml
        android:usesCleartextTraffic="true"
```

Rebuild, reinstall and repeat Step 3 until it reports "Not a Hermes dashboard".

- [ ] **Step 5: Add the Local Network string to iOS.** In `ios/Runner/Info.plist`, directly before
`<key>CFBundleName</key>`, add (tabs, matching the file):

```xml
	<key>NSLocalNetworkUsageDescription</key>
	<string>Iris connects to your Hermes server on your local network.</string>
```

- [ ] **Step 6: Record the finding** in `docs/superpowers/plans/2026-10-15-cleartext-check.md`:

```markdown
# Cleartext check (2026-10-15)

Release build on the Pixel 9 emulator, address `http://10.0.2.2:8799` (a Python HTTP server on the host).

- Result: <allowed | blocked>. Evidence: <the failure note's title, and the server's log line>.
- Android change: <none | android:usesCleartextTraffic="true">.
- iOS: NSLocalNetworkUsageDescription added. Not tested on a device: there is no Mac here. Dio uses dart:io sockets,
  which App Transport Security does not cover, so no ATS exception was added.
```

Fill in the angle-bracket parts with what you observed.

- [ ] **Step 7: Commit**

```bash
git add ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml docs/superpowers/plans/2026-10-15-cleartext-check.md
git commit -m "chore(platform): local network permission text; cleartext check recorded"
```

---

### Task 2: Connection modes and the private-address rules

**Files:**
- Create: `lib/data/net/connection_mode.dart`, `lib/data/net/private_host.dart`
- Test: `test/data/private_host_test.dart`

**Interfaces:**
- Produces: `enum ConnectionMode { lan, tailscale, cloudflare }` with `String get storedName` and
  `static ConnectionMode? fromStoredName(String? name)`; `bool isPrivateHost(String host)`;
  `bool plainHttpAllowed(Uri uri)`; `String addressFor(String input, ConnectionMode mode)`.

- [ ] **Step 1: Write the failing tests** in `test/data/private_host_test.dart`:

```dart
/// Which addresses may use plain http, and what scheme a bare address gets.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/net/connection_mode.dart';
import 'package:iris/data/net/private_host.dart';

void main() {
  group('isPrivateHost', () {
    for (final host in [
      '10.0.0.5',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.20',
      '127.0.0.1',
      '100.64.0.1',
      '100.127.255.254',
      'localhost',
      'nas.local',
      'box.tail1234.ts.net',
      'nas',
      '::1',
      '[::1]',
      'fd12:3456::1',
      'fc00::1',
    ]) {
      test('$host is private', () => expect(isPrivateHost(host), isTrue));
    }
    for (final host in [
      '8.8.8.8',
      '172.32.0.1',
      '100.128.0.1',
      '100.63.255.255',
      '192.169.0.1',
      'hermes.example.com',
      'example.local.evil.com',
      '2001:db8::1',
    ]) {
      test('$host is public', () => expect(isPrivateHost(host), isFalse));
    }
  });

  test('https is always allowed; http only for private hosts', () {
    expect(plainHttpAllowed(Uri.parse('https://hermes.example.com')), isTrue);
    expect(plainHttpAllowed(Uri.parse('http://192.168.1.20:9119')), isTrue);
    expect(plainHttpAllowed(Uri.parse('http://hermes.example.com')), isFalse);
  });

  group('addressFor', () {
    test('a bare private address in a LAN or Tailscale mode gets http', () {
      expect(
        addressFor('192.168.1.20:9119', ConnectionMode.lan),
        'http://192.168.1.20:9119',
      );
      expect(
        addressFor(' 100.101.102.103:9119/ ', ConnectionMode.tailscale),
        'http://100.101.102.103:9119',
      );
    });
    test('a bare .ts.net name gets https, which MagicDNS certificates serve', () {
      expect(
        addressFor('box.tail1234.ts.net', ConnectionMode.tailscale),
        'https://box.tail1234.ts.net',
      );
    });
    test('Cloudflare and public names default to https', () {
      expect(
        addressFor('hermes.example.com', ConnectionMode.cloudflare),
        'https://hermes.example.com',
      );
      expect(
        addressFor('192.168.1.20:9119', ConnectionMode.cloudflare),
        'https://192.168.1.20:9119',
      );
      expect(
        addressFor('hermes.example.com', ConnectionMode.lan),
        'https://hermes.example.com',
      );
    });
    test('a typed scheme is kept', () {
      expect(
        addressFor('https://192.168.1.20:9119', ConnectionMode.lan),
        'https://192.168.1.20:9119',
      );
    });
  });

  test('modes round-trip through their stored names', () {
    for (final mode in ConnectionMode.values) {
      expect(ConnectionMode.fromStoredName(mode.storedName), mode);
    }
    expect(ConnectionMode.fromStoredName(null), isNull);
    expect(ConnectionMode.fromStoredName('carrier-pigeon'), isNull);
  });
}
```

- [ ] **Step 2: Run them to see them fail.** `flutter test test/data/private_host_test.dart` → compile errors
(the files do not exist).

- [ ] **Step 3: Write `lib/data/net/connection_mode.dart`:**

```dart
/// How this phone reaches a Hermes server. It changes the connect screen's
/// wording, not how Iris connects: the probe works the same for all three.
library;

enum ConnectionMode {
  lan('lan'),
  tailscale('tailscale'),
  cloudflare('cloudflare');

  const ConnectionMode(this.storedName);

  /// What the database stores. Fixed strings, so renaming a case never
  /// orphans a saved server.
  final String storedName;

  /// The mode stored as [name], or null for none or an unknown name.
  static ConnectionMode? fromStoredName(String? name) {
    for (final mode in values) {
      if (mode.storedName == name) return mode;
    }
    return null;
  }
}
```

- [ ] **Step 4: Write `lib/data/net/private_host.dart`:**

```dart
/// Which addresses may be reached over plain http.
///
/// A home server on the same Wi-Fi or a tailnet usually has no certificate,
/// so http has to work there. Anywhere else it would put the password and the
/// conversation on the open internet in the clear, so it is refused.
library;

import 'connection_mode.dart';
import 'server_config.dart';

/// Whether [host] is on this device, the local network, or a tailnet.
bool isPrivateHost(String host) {
  var name = host.trim().toLowerCase();
  if (name.startsWith('[') && name.endsWith(']')) {
    name = name.substring(1, name.length - 1);
  }
  if (name.isEmpty) return false;
  if (name == 'localhost' || name.endsWith('.local') || name.endsWith('.ts.net')) {
    return true;
  }
  if (name.contains(':')) return _privateIpv6(name);
  final octets = name.split('.');
  if (octets.length == 4 && octets.every((part) => int.tryParse(part) != null)) {
    return _privateIpv4([for (final part in octets) int.parse(part)]);
  }
  // A single label, such as `nas`, only resolves on the local network.
  return !name.contains('.');
}

bool _privateIpv4(List<int> octets) {
  if (octets.any((octet) => octet < 0 || octet > 255)) return false;
  final [a, b, _, _] = octets;
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      // Tailscale's CGNAT range, 100.64.0.0/10.
      (a == 100 && b >= 64 && b <= 127);
}

bool _privateIpv6(String address) {
  if (address == '::1') return true;
  // Unique local addresses, fc00::/7.
  return address.startsWith('fc') || address.startsWith('fd');
}

/// Whether Iris may connect to [uri]: always over https, over http only to a
/// private host.
bool plainHttpAllowed(Uri uri) =>
    uri.scheme != 'http' || isPrivateHost(uri.host);

/// The address to use for what was typed in [mode].
///
/// A bare private address in a LAN or Tailscale mode gets http, because that
/// is what a home server without a certificate speaks; the general rule in
/// [ServerConfig.normaliseBaseUrl] would make it https and fail. A `.ts.net`
/// name keeps https, which Tailscale serves with real certificates.
String addressFor(String input, ConnectionMode mode) {
  final typed = input.trim();
  if (typed.isEmpty || typed.contains('://') || mode == ConnectionMode.cloudflare) {
    return ServerConfig.normaliseBaseUrl(typed);
  }
  final host = Uri.tryParse('http://$typed')?.host ?? '';
  final plain = isPrivateHost(host) && !host.endsWith('.ts.net');
  return ServerConfig.normaliseBaseUrl(plain ? 'http://$typed' : typed);
}
```

- [ ] **Step 5: Run the tests.** `flutter test test/data/private_host_test.dart` → all pass.

- [ ] **Step 6: Commit**

```bash
dart format lib/data/net/connection_mode.dart lib/data/net/private_host.dart test/data/private_host_test.dart
git add lib/data/net/connection_mode.dart lib/data/net/private_host.dart test/data/private_host_test.dart
git commit -m "feat(servers): connection modes, and which addresses may use plain http"
```

---

### Task 3: Save the mode with the server

**Files:**
- Modify: `lib/data/net/server_config.dart`, `lib/data/db/database.dart`, `lib/data/db/database.g.dart` (generated),
  `lib/data/repositories/server_repository.dart`
- Test: `test/data/database_migration_test.dart`, `test/data/server_repository_test.dart`

**Interfaces:**
- Consumes: `ConnectionMode` (Task 2).
- Produces: `ServerConfig.mode` (`ConnectionMode?`); `ServerRepository.addServer({..., ConnectionMode? mode})`.

- [ ] **Step 1: Write the failing tests.**

In `test/data/database_migration_test.dart`, in `'a v1 database upgrades in place'`, after
`expect(row.probedAt, isNull);` add:

```dart
    // v4 adds the connection mode; servers from before it have none.
    expect(row.connectionMode, isNull);
```

In `test/data/server_repository_test.dart`, add this test inside `main()` (it uses the file's existing `db`, and its
own `FakeHttp`; add `import 'package:iris/data/net/connection_mode.dart';` and, if missing,
`import '../support/fake_http.dart';`):

```dart
  test('the connection mode is saved with the server', () async {
    final http = FakeHttp()
      ..on('POST', '/api/auth/ws-ticket', (_) => FakeReply.json({'ticket': 't'}));
    final repository = ServerRepository(
      database: db,
      credentials: FakeCredentialStore(),
      connect: (config, {required secrets}) =>
          ServerConnection.create(config, secrets: secrets, adapter: http),
    );
    addTearDown(repository.dispose);

    final added = await repository.addServer(
      baseUrl: 'http://100.101.102.103:9119',
      label: 'Box',
      mode: ConnectionMode.tailscale,
    );
    expect(added, isA<Ok<ServerConfig>>());
    final saved = (await repository.listServers()).single;
    expect(saved.mode, ConnectionMode.tailscale);
  });
```

If `ServerConnection`, `Ok` or `ServerConfig` are not yet imported there, add
`import 'package:iris/data/net/server_connection.dart';`, `import 'package:iris/core/result.dart';` and
`import 'package:iris/data/net/server_config.dart';`.

- [ ] **Step 2: Run them to see them fail.**
`flutter test test/data/database_migration_test.dart test/data/server_repository_test.dart` → compile errors
(`connectionMode`, `mode` unknown).

- [ ] **Step 3: Add the column.** In `lib/data/db/database.dart`, in `class Servers`, after `usesAccessToken`:

```dart
  /// How the user said this phone reaches the server (`ConnectionMode`'s
  /// stored name). Null for servers added before modes existed.
  TextColumn get connectionMode => text().nullable()();
```

Change `int get schemaVersion => 3;` to `int get schemaVersion => 4;`, and in `onUpgrade`, after the `if (from < 3)`
block, add:

```dart
      if (from < 4) {
        await migrator.addColumn(servers, servers.connectionMode);
      }
```

Regenerate: `dart run build_runner build --delete-conflicting-outputs`. Check that only `database.g.dart` changed:
`git status --short`.

- [ ] **Step 4: Add `mode` to `ServerConfig`** in `lib/data/net/server_config.dart`:
  - import: `import 'connection_mode.dart';`
  - constructor parameter `this.mode,` after `this.allowSelfSignedCertificate = false,`
  - field, after `allowSelfSignedCertificate`:

```dart
  /// How the user said this phone reaches the server, or null for a server
  /// added before modes existed.
  final ConnectionMode? mode;
```

  - `fromJson`: add `mode: ConnectionMode.fromStoredName(json['connection_mode'].stringOrNull),`
  - `toJson`: add `'connection_mode': mode?.storedName,`
  - `copyWith`: add parameter `ConnectionMode? mode,` and `mode: mode ?? this.mode,`

- [ ] **Step 5: Save and read it** in `lib/data/repositories/server_repository.dart`:
  - import `../net/connection_mode.dart`
  - `_toConfig`: add `mode: ConnectionMode.fromStoredName(row.connectionMode),`
  - `addServer`: add the named parameter `ConnectionMode? mode,`; in the `ServerConfig(...)` it builds add
    `mode: mode,`; in `ServersCompanion.insert(...)` add `connectionMode: Value(mode?.storedName),`

- [ ] **Step 6: Run the tests.**
`flutter test test/data/database_migration_test.dart test/data/server_repository_test.dart` → pass. Then
`flutter analyze` → no issues.

- [ ] **Step 7: Commit**

```bash
dart format lib/data/net/server_config.dart lib/data/db/database.dart lib/data/repositories/server_repository.dart test/data/database_migration_test.dart test/data/server_repository_test.dart
git add lib/data test/data
git commit -m "feat(servers): remember how each server is reached (schema 4)"
```

---

### Task 4: The connect screen takes a mode

**Files:**
- Create: `lib/features/servers/connection_mode_copy.dart`
- Modify: `lib/features/servers/connect_screen.dart`
- Test: `test/features/connect_screen_test.dart`

**Interfaces:**
- Consumes: `ConnectionMode`, `addressFor`, `plainHttpAllowed` (Task 2); `addServer(mode:)` (Task 3).
- Produces: `ConnectScreen({required ConnectionMode mode, ValueChanged<ServerConfig>? onConnected})`;
  `extension ConnectionModeCopy on ConnectionMode` with `title`, `line`, `example`, `help`, `icon`.

- [ ] **Step 1: Write the failing tests.** In `test/features/connect_screen_test.dart`:
  - add `import 'package:iris/data/net/connection_mode.dart';`
  - change `Widget harness()` to `Widget harness({ConnectionMode mode = ConnectionMode.cloudflare})` and its
    `const ConnectScreen()` to `ConnectScreen(mode: mode)` (drop the `const`)
  - add these tests:

```dart
  testWidgets('each mode shows its own example and help', (tester) async {
    await tester.pumpWidget(harness(mode: ConnectionMode.lan));
    expect(find.text('Same Wi-Fi'), findsOneWidget);
    expect(find.text('http://192.168.1.20:9119'), findsOneWidget);
    expect(find.textContaining('ip addr'), findsOneWidget);

    await tester.pumpWidget(harness(mode: ConnectionMode.tailscale));
    expect(find.text('http://100.101.102.103:9119'), findsOneWidget);
    expect(find.textContaining('Tailscale app'), findsOneWidget);
  });

  testWidgets('a public address over plain http is refused before any request', (
    tester,
  ) async {
    await tester.pumpWidget(harness(mode: ConnectionMode.lan));
    await submitAddress(tester, 'http://hermes.example.com');
    expect(find.text('Use https for an address on the internet.'), findsOneWidget);
    expect(http.requests, isEmpty);
  });

  testWidgets('a bare LAN address goes out over http', (tester) async {
    await tester.pumpWidget(harness(mode: ConnectionMode.lan));
    await submitAddress(tester, '192.168.1.20:9119');
    expect(http.requests, isNotEmpty);
    expect(http.requests.first.uri.scheme, 'http');
    expect(http.requests.first.uri.host, '192.168.1.20');
  });

  testWidgets('Change goes back', (tester) async {
    final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          serverRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: theme.materialTheme,
          builder: (context, navigator) => IrisTheme(
            data: theme,
            child: Material(type: MaterialType.transparency, child: navigator),
          ),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const ConnectScreen(mode: ConnectionMode.lan),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Change how you connect'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectScreen), findsNothing);
  });
```

- [ ] **Step 2: Run them to see them fail.** `flutter test test/features/connect_screen_test.dart` → compile error
(`mode` is not a parameter).

- [ ] **Step 3: Write `lib/features/servers/connection_mode_copy.dart`:**

```dart
/// What each connection mode is called and how it is explained.
library;

import 'package:flutter/material.dart';

import '../../data/net/connection_mode.dart';

extension ConnectionModeCopy on ConnectionMode {
  String get title => switch (this) {
    ConnectionMode.lan => 'Same Wi-Fi',
    ConnectionMode.tailscale => 'Tailscale',
    ConnectionMode.cloudflare => 'Cloudflare',
  };

  /// One line under the title on the welcome screen.
  String get line => switch (this) {
    ConnectionMode.lan => 'Your phone and server are on the same network',
    ConnectionMode.tailscale => 'Reach your server from anywhere over your tailnet',
    ConnectionMode.cloudflare =>
      'Your dashboard is published through Cloudflare Access',
  };

  /// The address field's hint.
  String get example => switch (this) {
    ConnectionMode.lan => 'http://192.168.1.20:9119',
    ConnectionMode.tailscale => 'http://100.101.102.103:9119',
    ConnectionMode.cloudflare => 'https://hermes.example.com',
  };

  /// Guidance under the address field.
  String get help => switch (this) {
    ConnectionMode.lan =>
      "The server's address on your network and the dashboard's port, usually "
          "9119. Your router's device list, or ip addr on the server, shows it.",
    ConnectionMode.tailscale =>
      "Open the Tailscale app and copy your server's address, then add the "
          "dashboard's port, usually 9119. A https://….ts.net name works too.",
    ConnectionMode.cloudflare =>
      'The address you open in a browser. If Cloudflare Access protects it, '
          'Iris asks for a service token next.',
  };

  IconData get icon => switch (this) {
    ConnectionMode.lan => Icons.wifi,
    ConnectionMode.tailscale => Icons.hub_outlined,
    ConnectionMode.cloudflare => Icons.cloud_outlined,
  };
}
```

- [ ] **Step 4: Change `lib/features/servers/connect_screen.dart`.**
  - imports: add `import '../../data/net/connection_mode.dart';`, `import '../../data/net/private_host.dart';`,
    `import 'connection_mode_copy.dart';`
  - constructor: `const ConnectScreen({required this.mode, this.onConnected, super.key});` and the field

```dart
  /// How the user said they reach the server; it changes the wording only.
  final ConnectionMode mode;
```

  - add to `_ConnectScreenState`:

```dart
  /// The address to use, with the scheme this mode implies for a bare one.
  String get _addressText => addressFor(_address.text, widget.mode);

  /// Refuses plain http to anything but a private address. True if refused.
  bool _refusedPlainHttp() {
    final uri = Uri.tryParse(_addressText);
    if (uri == null || plainHttpAllowed(uri)) return false;
    setState(() {
      _step = _Step.address;
      _failure = const IrisFailure(
        FailureKind.rejected,
        message: 'Use https for an address on the internet.',
      );
    });
    return true;
  }
```

  - at the very start of `_probe()`: `if (_refusedPlainHttp()) return;`
  - in `_probe()`, `testConnection(_address.text, ...)` becomes `testConnection(_addressText, ...)`
  - in `_join()`, after its first `setState`, nothing new; change `baseUrl: _address.text,` to
    `baseUrl: _addressText,` and add `mode: widget.mode,` to the `addServer(...)` call
  - in `build`, replace the `IrisOrb(...)` line's preceding `SizedBox` and the orb with a row that names the mode and
    offers "Change":

```dart
              SizedBox(height: window.isCramped ? IrisSpace.lg : IrisSpace.huge),
              Row(
                children: [
                  IrisOrb(
                    state: switch (_step) {
                      _Step.address => AgentState.idle,
                      _Step.probing => AgentState.thinking,
                      _Step.accessToken || _Step.login => AgentState.waiting,
                      _Step.joining => AgentState.working,
                    },
                    size: 40,
                  ),
                  const Spacer(),
                  IrisChip(widget.mode.title),
                  const SizedBox(width: IrisSpace.xs),
                  IrisButton(
                    label: 'Change',
                    semanticLabel: 'Change how you connect',
                    tone: IrisButtonTone.ghost,
                    onPressed: _busy
                        ? null
                        : () => unawaited(Navigator.of(context).maybePop()),
                  ),
                ],
              ),
```

    Check `IrisButton` for a `semanticLabel` parameter (`grep -n "semanticLabel" lib/design/components/controls.dart`).
    If it has none, wrap the button in `Semantics(label: 'Change how you connect', button: true, excludeSemantics:
    true, child: ...)` instead.
  - `_addressField`: `hint: widget.mode.example,`
  - `_AddressHint`: give it a `required this.help` `String` field, pass `help: widget.mode.help`, and use `help` as
    the `Text` instead of the fixed sentence.

- [ ] **Step 5: Update the other callers so the app compiles.** `grep -rn "ConnectScreen(" lib test`. For now, in
`server_gate.dart` (two places) and `server_switcher.dart`, pass `mode: ConnectionMode.cloudflare` (Task 5 replaces
these with the welcome screen) and import `../../data/net/connection_mode.dart`.

- [ ] **Step 6: Run the tests.** `flutter test test/features/connect_screen_test.dart` → pass. Then `flutter test`;
if `test/design/screens_golden_test.dart` has a connect screen golden that now differs, regenerate it with
`flutter test --update-goldens test/design/screens_golden_test.dart`, open the new PNG with the Read tool, and check
the mode chip and "Change" sit on the orb's row and nothing else moved.

- [ ] **Step 7: Commit**

```bash
dart format lib/features/servers/connection_mode_copy.dart lib/features/servers/connect_screen.dart lib/features/servers/server_gate.dart lib/features/servers/server_switcher.dart test/features/connect_screen_test.dart
git add lib/features/servers test/features/connect_screen_test.dart test/design/goldens
git commit -m "feat(servers): the connect screen speaks to the chosen mode; refuses public http"
```

---

### Task 5: The welcome screen

**Files:**
- Create: `lib/features/servers/welcome_screen.dart`
- Modify: `lib/features/servers/server_gate.dart`, `lib/features/servers/server_switcher.dart`,
  `lib/features/home/link_status_screen.dart`
- Test: `test/features/welcome_screen_test.dart`

**Interfaces:**
- Consumes: `ConnectScreen(mode:)`, `ConnectionModeCopy` (Task 4).
- Produces: `WelcomeScreen({bool showDemo = true, ValueChanged<ServerConfig>? onConnected})`. This task renders
  only the three mode rows; Task 9 adds the demo row, shown when `showDemo` is true.

- [ ] **Step 1: Write the failing tests** in `test/features/welcome_screen_test.dart`:

```dart
/// First run: how the phone reaches the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/servers/connect_screen.dart';
import 'package:iris/features/servers/welcome_screen.dart';

import '../support/harness.dart';

void main() {
  testWidgets('offers the three ways to connect', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: themed(const WelcomeScreen(showDemo: false))),
    );
    expect(find.text('Same Wi-Fi'), findsOneWidget);
    expect(find.text('Tailscale'), findsOneWidget);
    expect(find.text('Cloudflare'), findsOneWidget);
    expect(find.text('Try the demo'), findsNothing);
  });

  for (final (row, example) in [
    ('Same Wi-Fi', 'http://192.168.1.20:9119'),
    ('Tailscale', 'http://100.101.102.103:9119'),
    ('Cloudflare', 'https://hermes.example.com'),
  ]) {
    testWidgets('$row opens the connect screen for it', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: themed(const WelcomeScreen(showDemo: false))),
      );
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectScreen), findsOneWidget);
      expect(find.text(example), findsOneWidget);
    });
  }
}
```

- [ ] **Step 2: Run them to see them fail.** `flutter test test/features/welcome_screen_test.dart` → compile error.

- [ ] **Step 3: Write `lib/features/servers/welcome_screen.dart`:**

```dart
/// The first screen: how this phone reaches the Hermes server, or a look at
/// Iris without one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/net/connection_mode.dart';
import '../../data/net/server_config.dart';
import '../../design/components/iris_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/components/sheet.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../../design/tokens/palette.dart';
import 'connect_screen.dart';
import 'connection_mode_copy.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({this.showDemo = true, this.onConnected, super.key});

  /// Whether to offer the demo. Off when adding a second server.
  final bool showDemo;

  /// Called once a server is saved and reachable.
  final ValueChanged<ServerConfig>? onConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.iris;
    final window = context.window;
    final palette = theme.palette;

    void open(ConnectionMode mode) => unawaited(
      Navigator.of(context).push<void>(
        IrisPageRoute<void>(
          builder: (_) => ConnectScreen(
            mode: mode,
            onConnected: (server) {
              // Back to the bottom of the stack, where the gate now shows home.
              Navigator.of(context).popUntil((route) => route.isFirst);
              onConnected?.call(server);
            },
          ),
        ),
      ),
    );

    return IrisScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: window.gutter),
        child: ReadableColumn(
          maxWidth: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: window.isCramped ? IrisSpace.lg : IrisSpace.huge),
              const IrisOrb(state: AgentState.idle, size: 40),
              const SizedBox(height: IrisSpace.lg),
              Text('Connect to your agent', style: theme.typography.display),
              const SizedBox(height: IrisSpace.sm),
              Text(
                'How does this phone reach your Hermes server?',
                style: theme.typography.body.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: IrisSpace.xl),
              for (final mode in ConnectionMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: IrisSpace.xs),
                  child: IrisListRow(
                    title: mode.title,
                    subtitle: mode.line,
                    leading: Icon(mode.icon, size: IrisSize.icon, color: palette.accent),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: palette.lineStrong,
                    ),
                    onTap: () => open(mode),
                  ),
                ),
              const SizedBox(height: IrisSpace.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
```

  (`IrisSize.icon` and `palette.lineStrong` are used the same way in `conversation_list_screen.dart`.)

- [ ] **Step 4: Open it from the gate and the switcher.**
  - `server_gate.dart`: `if (list.isEmpty) return const ConnectScreen(...)` → `if (list.isEmpty) return const
    WelcomeScreen();`; the "Add another" button's `pageBuilder` returns `const WelcomeScreen(showDemo: false)`. Import
    `welcome_screen.dart`; drop the `connect_screen.dart` and `connection_mode.dart` imports if now unused.
  - `server_switcher.dart` `_addServer`: `pageBuilder: (context, _, _) => const WelcomeScreen(showDemo: false),`
    (the welcome screen pops back to the first route itself). Same import changes.

- [ ] **Step 5: Show the mode on the link status screen.** In `lib/features/home/link_status_screen.dart`, import
`../servers/connection_mode_copy.dart` and change the server row's subtitle:

```dart
                subtitle: switch (server) {
                  null => null,
                  ServerConfig(:final mode?) => '${server.baseUrl} · ${mode.title}',
                  _ => server.baseUrl,
                },
```

(import `../../data/net/server_config.dart` if the file does not have it.)

- [ ] **Step 6: Run the tests.** `flutter test test/features/welcome_screen_test.dart`, then `flutter test` and
`flutter analyze`.

- [ ] **Step 7: Commit**

```bash
dart format lib/features/servers/welcome_screen.dart lib/features/servers/server_gate.dart lib/features/servers/server_switcher.dart lib/features/home/link_status_screen.dart test/features/welcome_screen_test.dart
git add lib/features test/features/welcome_screen_test.dart
git commit -m "feat(servers): a welcome screen that asks how the phone reaches the server"
```

---

### Task 6: Demo scripts and the player

**Files:**
- Create: `lib/demo/demo_script.dart`, `lib/demo/script_player.dart`
- Test: `test/demo/script_player_test.dart`

**Interfaces:**
- Produces:
  - `sealed class DemoStep` with `ThinkStep(String text)`, `ToolStep(String name, {required String input, required
    String output, Duration duration, bool failed})`, `ApprovalStep({required String command, required String
    description, required List<DemoStep> ifApproved, required List<DemoStep> ifDenied})`, `SecretStep(String
    command)`, `SayStep(String markdown)`, `ContextStep(double percent)`, `FailStep(String message)`
  - `final class DemoScript({required String prompt, required String title, required List<DemoStep> steps,
    List<DemoStep>? firstRun})`
  - `typedef Delay = Future<void> Function(Duration)`; `Future<void> realDelay(Duration)`
  - `ScriptPlayer({required String sessionId, required void Function(ChatEvent) emit, required void
    Function(TranscriptItem) record, Delay delay = realDelay})` with `Future<void> play(List<DemoStep>)`,
    `bool get running`, `void stop()`, `void answerApproval({required bool approved})`, `void answerSecret()`,
    `bool steer(String text)`, `void dispose()`

- [ ] **Step 1: Write the failing tests** in `test/demo/script_player_test.dart`:

```dart
/// The demo's scripts play as the events a real gateway sends.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/demo/demo_script.dart';
import 'package:iris/demo/script_player.dart';

Future<void> instant(Duration _) async {}

/// Lets queued microtasks run, so a script plays up to its next wait.
Future<void> drain() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<ChatEvent> events;
  late List<TranscriptItem> recorded;
  late ScriptPlayer player;

  setUp(() {
    events = [];
    recorded = [];
    player = ScriptPlayer(
      sessionId: 's',
      emit: events.add,
      record: recorded.add,
      delay: instant,
    );
  });

  test('a turn is busy, streams its parts, and ends idle', () async {
    await player.play(const [
      ThinkStep('Look at the disk first.'),
      ToolStep('terminal', input: 'df -h', output: '97% /'),
      SayStep('The disk is nearly full.'),
    ]);
    expect(events.first, isA<BusyChanged>().having((e) => e.busy, 'busy', isTrue));
    expect(events.last, isA<BusyChanged>().having((e) => e.busy, 'busy', isFalse));
    // Each think step ends with a newline, so two read as separate lines.
    expect(events.whereType<ReasoningDelta>().map((e) => e.text).join(), 'Look at the disk first.\n');
    expect(events.whereType<ToolStarted>().single.input, 'df -h');
    expect(events.whereType<ToolCompleted>().single.output, '97% /');
    expect(events.whereType<TextDelta>().map((e) => e.text).join(), 'The disk is nearly full.');
    expect(events.whereType<MessageCompleted>().single.content, 'The disk is nearly full.');
    expect(events.every((e) => e.sessionId == 's'), isTrue);
    expect(recorded.map((item) => item.runtimeType), [AssistantTurn, ToolCall, AssistantTurn]);
    expect(player.running, isFalse);
  });

  test('an approval waits, then plays the branch chosen', () async {
    const step = ApprovalStep(
      command: 'docker image prune -a',
      description: 'Remove old images',
      ifApproved: [SayStep('Freed 38 GB.')],
      ifDenied: [SayStep('Left them.')],
    );
    final done = player.play(const [step]);
    await drain();
    final asked = events.whereType<ApprovalAsked>().single.request;
    expect(asked.command, 'docker image prune -a');
    expect(player.running, isTrue);
    player.answerApproval(approved: false);
    await done;
    expect(events.whereType<MessageCompleted>().single.content, 'Left them.');
  });

  test('a secret is asked for, and the answer is not kept', () async {
    final done = player.play(const [SecretStep('sudo true'), SayStep('Done.')]);
    await drain();
    final request = events.whereType<InputAsked>().single.request;
    expect(request.kind, InputKind.sudo);
    player.answerSecret();
    await done;
    expect(events.whereType<MessageCompleted>().single.content, 'Done.');
  });

  test('stop during an approval clears the card and ends the turn', () async {
    final done = player.play(const [
      ApprovalStep(
        command: 'rm -rf /tmp/cache',
        description: 'Clear the cache',
        ifApproved: [SayStep('Cleared.')],
        ifDenied: [SayStep('Kept.')],
      ),
    ]);
    await drain();
    final id = events.whereType<ApprovalAsked>().single.request.queueId;
    player.stop();
    await done;
    expect(events.whereType<RequestWithdrawn>().single.requestId, id);
    expect(events.whereType<TurnInterrupted>(), hasLength(1));
    expect(events.whereType<MessageCompleted>(), isEmpty);
    expect(events.last, isA<BusyChanged>().having((e) => e.busy, 'busy', isFalse));
    expect(player.running, isFalse);
  });

  test('a steer is acknowledged in the reply', () async {
    final done = player.play(const [
      ApprovalStep(
        command: 'x',
        description: 'x',
        ifApproved: [SayStep('Done.')],
        ifDenied: [],
      ),
    ]);
    await drain();
    expect(player.steer('skip the cache'), isTrue);
    player.answerApproval(approved: true);
    await done;
    expect(
      events.whereType<MessageCompleted>().single.content,
      '_Noted: skip the cache._\n\nDone.',
    );
  });

  test('a steer after the last reply gets a reply of its own', () async {
    final done = player.play(const [
      SayStep('First.'),
      SecretStep('sudo true'),
    ]);
    await drain();
    player.steer('thanks');
    player.answerSecret();
    await done;
    expect(
      events.whereType<MessageCompleted>().map((e) => e.content),
      ['First.', '_Noted: thanks._'],
    );
  });

  test('a failure ends the turn as failed and is recorded for retry', () async {
    await player.play(const [
      FailStep('Port 8096 is already in use.'),
      SayStep('never'),
    ]);
    expect(events.whereType<TurnFailed>().single.message, 'Port 8096 is already in use.');
    expect(events.whereType<TextDelta>(), isEmpty);
    expect(recorded.whereType<Notice>().single.retryable, isTrue);
    expect(player.running, isFalse);
  });

  test('a context step fills the ring', () async {
    await player.play(const [ContextStep(31)]);
    expect(events.whereType<ContextChanged>().single.usage.percent, 31);
  });

  test('a steer when nothing runs is refused', () {
    expect(player.steer('hello'), isFalse);
  });
}
```

- [ ] **Step 2: Run them to see them fail.** `flutter test test/demo/script_player_test.dart` → compile errors.

- [ ] **Step 3: Write `lib/demo/demo_script.dart`:**

```dart
/// What a demo turn does, step by step. Data only; `ScriptPlayer` plays it.
library;

sealed class DemoStep {
  const DemoStep();
}

/// Visible thinking.
final class ThinkStep extends DemoStep {
  const ThinkStep(this.text);
  final String text;
}

/// A tool call that runs for [duration] and returns [output].
final class ToolStep extends DemoStep {
  const ToolStep(
    this.name, {
    required this.input,
    required this.output,
    this.duration = const Duration(milliseconds: 1500),
    this.failed = false,
  });
  final String name;
  final String input;
  final String output;
  final Duration duration;
  final bool failed;
}

/// Asks to run [command] and plays one branch or the other.
final class ApprovalStep extends DemoStep {
  const ApprovalStep({
    required this.command,
    required this.description,
    required this.ifApproved,
    required this.ifDenied,
  });
  final String command;
  final String description;
  final List<DemoStep> ifApproved;
  final List<DemoStep> ifDenied;
}

/// Asks for a sudo password. Any answer continues; none is kept.
final class SecretStep extends DemoStep {
  const SecretStep(this.command);
  final String command;
}

/// Reply text, in Markdown.
final class SayStep extends DemoStep {
  const SayStep(this.markdown);
  final String markdown;
}

/// How full the context window is, 0 to 100.
final class ContextStep extends DemoStep {
  const ContextStep(this.percent);
  final double percent;
}

/// Ends the turn as failed, so retry can be shown.
final class FailStep extends DemoStep {
  const FailStep(this.message);
  final String message;
}

/// A suggested prompt and what it plays.
final class DemoScript {
  const DemoScript({
    required this.prompt,
    required this.title,
    required this.steps,
    this.firstRun,
  });

  /// The text that triggers it, as shown on its suggestion.
  final String prompt;

  /// The new conversation's title.
  final String title;

  final List<DemoStep> steps;

  /// Played instead of [steps] the first time only, so a retry can succeed.
  final List<DemoStep>? firstRun;
}
```

- [ ] **Step 4: Write `lib/demo/script_player.dart`:**

```dart
/// Plays a demo script as the events a Hermes gateway sends.
///
/// The chat screen cannot tell the difference: it receives the same
/// `ChatEvent`s, in the same order, as from a real turn. Everything that
/// finishes is also handed to [ScriptPlayer.record], so the conversation's
/// stored history matches what was shown.
library;

import 'dart:async';
import 'dart:math' as math;

import '../data/chat/chat_event.dart';
import '../data/chat/chat_models.dart';
import 'demo_script.dart';

typedef Delay = Future<void> Function(Duration duration);

Future<void> realDelay(Duration duration) => Future<void>.delayed(duration);

final class ScriptPlayer {
  ScriptPlayer({
    required this.sessionId,
    required this.emit,
    required this.record,
    Delay delay = realDelay,
  }) : _delay = delay;

  final String sessionId;
  final void Function(ChatEvent event) emit;
  final void Function(TranscriptItem item) record;
  final Delay _delay;

  static const _textChunk = 40;
  static const _textTick = Duration(milliseconds: 30);
  static const _thinkChunk = 12;
  static const _thinkTick = Duration(milliseconds: 40);

  bool _running = false;
  bool _stopped = false;
  int _serial = 0;
  String _reasoning = '';
  final List<String> _steers = [];
  Completer<bool>? _approval;
  String? _approvalId;
  Completer<void>? _secret;
  String? _secretId;

  bool get running => _running;

  Future<void> play(List<DemoStep> steps) async {
    _running = true;
    _stopped = false;
    emit(BusyChanged(sessionId, busy: true));
    final finished = await _run(steps);
    if (_stopped) return;
    if (finished && _steers.isNotEmpty) await _say('');
    if (_stopped) return;
    _flushReasoning();
    _running = false;
    emit(BusyChanged(sessionId, busy: false));
  }

  /// Plays [steps]; false if the turn ended early, by a stop or a failure.
  Future<bool> _run(List<DemoStep> steps) async {
    for (final step in steps) {
      if (_stopped) return false;
      switch (step) {
        case ThinkStep(:final text):
          for (final chunk in _chunks('$text\n', _thinkChunk)) {
            if (_stopped) return false;
            _reasoning += chunk;
            emit(ReasoningDelta(sessionId, chunk));
            await _delay(_thinkTick);
          }
        case ToolStep():
          _flushReasoning();
          final id = '$sessionId-tool-${_serial++}';
          emit(
            ToolStarted(sessionId, name: step.name, toolId: id, input: step.input),
          );
          await _delay(step.duration);
          if (_stopped) return false;
          emit(
            ToolCompleted(
              sessionId,
              name: step.name,
              toolId: id,
              output: step.output,
              failed: step.failed,
            ),
          );
          record(
            ToolCall(
              id: id,
              name: step.name,
              arguments: step.input,
              output: step.output,
              status: step.failed ? ToolStatus.failed : ToolStatus.done,
            ),
          );
        case ApprovalStep():
          _flushReasoning();
          final id = '$sessionId-approval-${_serial++}';
          final answer = _approval = Completer<bool>();
          _approvalId = id;
          emit(
            ApprovalAsked(
              ApprovalRequest(
                sessionId: sessionId,
                command: step.command,
                description: step.description,
                choices: const ['once', 'deny'],
                queueId: id,
              ),
            ),
          );
          final approved = await answer.future;
          _approval = null;
          _approvalId = null;
          if (_stopped) return false;
          if (!await _run(approved ? step.ifApproved : step.ifDenied)) {
            return false;
          }
        case SecretStep(:final command):
          final id = '$sessionId-input-${_serial++}';
          final answer = _secret = Completer<void>();
          _secretId = id;
          emit(
            InputAsked(
              InputRequest(
                requestId: id,
                sessionId: sessionId,
                kind: InputKind.sudo,
                command: command,
              ),
            ),
          );
          await answer.future;
          _secret = null;
          _secretId = null;
          if (_stopped) return false;
        case SayStep(:final markdown):
          await _say(markdown);
          if (_stopped) return false;
        case ContextStep(:final percent):
          emit(
            ContextChanged(
              sessionId,
              ContextUsage(
                percent: percent,
                used: (percent / 100 * 200000).round(),
                max: 200000,
              ),
            ),
          );
        case FailStep(:final message):
          _flushReasoning();
          emit(TurnFailed(sessionId, message));
          record(
            Notice(
              id: '$sessionId-failed-${_serial++}',
              text: message,
              isError: true,
              retryable: true,
            ),
          );
          return false;
      }
    }
    return true;
  }

  Future<void> _say(String markdown) async {
    final notes = [for (final steer in _steers) '_Noted: $steer._'];
    _steers.clear();
    final text = [...notes, if (markdown.isNotEmpty) markdown].join('\n\n');
    if (text.isEmpty) return;
    emit(MessageStarted(sessionId));
    for (final chunk in _chunks(text, _textChunk)) {
      if (_stopped) return;
      emit(TextDelta(sessionId, chunk));
      await _delay(_textTick);
    }
    if (_stopped) return;
    final reasoning = _reasoning.trim();
    emit(
      MessageCompleted(
        sessionId,
        content: text,
        reasoning: reasoning.isEmpty ? null : reasoning,
      ),
    );
    record(
      AssistantTurn(
        id: '$sessionId-reply-${_serial++}',
        text: text,
        reasoning: reasoning,
      ),
    );
    _reasoning = '';
  }

  /// Thinking with no reply after it yet is kept as its own entry.
  void _flushReasoning() {
    final reasoning = _reasoning.trim();
    if (reasoning.isEmpty) return;
    record(
      AssistantTurn(
        id: '$sessionId-thought-${_serial++}',
        text: '',
        reasoning: reasoning,
      ),
    );
    _reasoning = '';
  }

  /// Stops the turn, as the Stop button does.
  void stop() {
    if (!_running || _stopped) return;
    _stopped = true;
    if (_approvalId case final id?) emit(RequestWithdrawn(sessionId, id));
    if (_secretId case final id?) emit(RequestWithdrawn(sessionId, id));
    _release();
    _reasoning = '';
    emit(TurnInterrupted(sessionId));
    record(Notice(id: '$sessionId-stopped-${_serial++}', text: 'Stopped.'));
    _running = false;
    emit(BusyChanged(sessionId, busy: false));
  }

  void answerApproval({required bool approved}) {
    final answer = _approval;
    if (answer != null && !answer.isCompleted) answer.complete(approved);
  }

  /// Continues after a sudo prompt. The value typed is never passed here.
  void answerSecret() {
    final answer = _secret;
    if (answer != null && !answer.isCompleted) answer.complete();
  }

  /// Notes [text] for the reply being written. False if no turn is running.
  bool steer(String text) {
    if (!_running) return false;
    _steers.add(text);
    return true;
  }

  /// Ends playback silently, for when the demo closes.
  void dispose() {
    _stopped = true;
    _running = false;
    _release();
  }

  void _release() {
    final approval = _approval;
    if (approval != null && !approval.isCompleted) approval.complete(false);
    final secret = _secret;
    if (secret != null && !secret.isCompleted) secret.complete();
  }

  static Iterable<String> _chunks(String text, int size) sync* {
    for (var start = 0; start < text.length; start += size) {
      yield text.substring(start, math.min(start + size, text.length));
    }
  }
}
```

- [ ] **Step 5: Run the tests.** `flutter test test/demo/script_player_test.dart` → all pass.

- [ ] **Step 6: Commit**

```bash
dart format lib/demo/demo_script.dart lib/demo/script_player.dart test/demo/script_player_test.dart
git add lib/demo test/demo
git commit -m "feat(demo): scripts, and a player that emits them as gateway events"
```

---

### Task 7: The demo world, its content and its ChatBackend

**Files:**
- Create: `lib/demo/demo_content.dart`, `lib/demo/demo_world.dart`, `lib/demo/demo_chat_backend.dart`
- Test: `test/demo/demo_world_test.dart`

**Interfaces:**
- Consumes: Task 6's step types, `DemoScript`, `ScriptPlayer`, `Delay`, `realDelay`.
- Produces:
  - `const leaveDemoLink = 'iris://leave-demo';` (in `demo_content.dart`)
  - `List<DemoScript> get demoScripts`; `String get demoFallback`
  - `DemoWorld({DateTime Function() clock = DateTime.now, Delay delay = realDelay})` with:
    `Stream<ChatEvent> get events`, `List<AgentProfile> get profiles`,
    `ConversationPage page(String profile, int offset, {required bool archived})`,
    `HistoryPage history(String storedId)`, `NewConversation create(String profile)`,
    `ResumedConversation resume(String storedId)`, `void submit(String runtimeId, String text)`,
    `void interrupt(String runtimeId)`, `SteerOutcome steer(String runtimeId, String text)`,
    `SlashOutcome slash(String runtimeId, String command)`, `void answerApproval(ApprovalRequest request, String
    choice)`, `void answerInput(InputRequest request)`, `void rename(String storedId, String title)`,
    `void setArchived(String storedId, {required bool archived})`,
    `List<SearchHit> search(String profile, String query)`, `ModelOptions get modelOptions`,
    `ModelSwitch switchModel(String runtimeId, String model, String provider)`, `Future<void> dispose()`,
    `static String runtimeIdFor(String storedId)`
  - `DemoChatBackend(DemoWorld world, {required String profile})` implements `ChatBackend`

- [ ] **Step 1: Write the failing tests** in `test/demo/demo_world_test.dart`:

```dart
/// The demo behaves like a small Hermes server that lives in memory.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/demo/demo_chat_backend.dart';
import 'package:iris/demo/demo_content.dart';
import 'package:iris/demo/demo_world.dart';

Future<void> instant(Duration _) async {}

Future<void> drain() async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late DemoWorld world;
  late List<ChatEvent> events;

  setUp(() {
    world = DemoWorld(clock: () => DateTime(2026, 10, 15, 20), delay: instant);
    events = [];
    world.events.listen(events.add);
  });
  tearDown(() => world.dispose());

  test('each profile has its own conversations; archived are apart', () {
    final home = world.page('default', 0, archived: false);
    final lab = world.page('homelab', 0, archived: false);
    expect(home.items, isNotEmpty);
    expect(lab.items, isNotEmpty);
    expect(home.items.map((c) => c.id).toSet().intersection(lab.items.map((c) => c.id).toSet()), isEmpty);
    expect(world.page('default', 0, archived: true).items, hasLength(1));
    expect(home.total, home.items.length);
  });

  test('a suggested prompt in a new chat plays its script and names it', () async {
    final created = world.create('default');
    final script = demoScripts.firstWhere((s) => s.prompt == 'Summarise this week\'s GitHub issues');
    world.submit(created.runtimeId, script.prompt);
    await drain();
    expect(events.whereType<TitleChanged>().single.title, script.title);
    expect(events.whereType<MessageCompleted>(), hasLength(1));
    final stored = world.history(created.storedId).items;
    expect(stored.first, isA<UserTurn>());
    expect(stored.whereType<AssistantTurn>().last.text, contains('acme/homelab-scripts'));
    expect(world.page('default', 0, archived: false).items.first.id, created.storedId);
  });

  test('free text gets the honest fallback', () async {
    final created = world.create('default');
    world.submit(created.runtimeId, 'what is the meaning of life');
    await drain();
    expect(events.whereType<MessageCompleted>().single.content, demoFallback);
    expect(demoFallback, contains(leaveDemoLink));
  });

  test('the media server fails once; retry replays it and succeeds', () async {
    final created = world.create('default');
    final run = created.runtimeId;
    world.submit(run, 'Restart the media server');
    await drain();
    world.answerApproval(events.whereType<ApprovalAsked>().last.request, 'once');
    await drain();
    expect(events.whereType<TurnFailed>(), hasLength(1));

    final outcome = world.slash(run, '/retry');
    expect(outcome.kind, SlashKind.send);
    expect(outcome.text, 'Restart the media server');
    // Hermes drops the failed exchange; the controller then sends the prompt.
    expect(world.history(created.storedId).items, isEmpty);
    world.submit(run, outcome.text);
    await drain();
    world.answerApproval(events.whereType<ApprovalAsked>().last.request, 'once');
    await drain();
    expect(events.whereType<TurnFailed>(), hasLength(1));
    expect(events.whereType<MessageCompleted>().last.content, contains('Jellyfin is back up'));
  });

  test('other slash commands are not available', () {
    final run = world.create('default').runtimeId;
    final outcome = world.slash(run, '/cron list');
    expect(outcome.kind, SlashKind.exec);
    expect(outcome.text, 'Not available in the demo.');
  });

  test('rename and archive change the lists', () {
    final first = world.page('default', 0, archived: false).items.first;
    world.rename(first.id, 'Renamed');
    expect(world.page('default', 0, archived: false).items.first.title, 'Renamed');
    world.setArchived(first.id, archived: true);
    expect(world.page('default', 0, archived: false).items.any((c) => c.id == first.id), isFalse);
    expect(world.page('default', 0, archived: true).items.any((c) => c.id == first.id), isTrue);
  });

  test('search finds message text and marks the match', () {
    final hits = world.search('default', 'fail2ban');
    expect(hits, hasLength(1));
    expect(hits.single.snippet.where((run) => run.matched).single.text.toLowerCase(), 'fail2ban');
    expect(world.search('default', 'zzz-nothing'), isEmpty);
  });

  test('a steer while running is accepted, otherwise rejected', () async {
    final created = world.create('default');
    expect(world.steer(created.runtimeId, 'hi'), SteerOutcome.rejected);
    world.submit(created.runtimeId, 'Check disk space on my server');
    await drain();
    expect(world.steer(created.runtimeId, 'only images'), SteerOutcome.accepted);
    world.interrupt(created.runtimeId);
    await drain();
    expect(events.whereType<TurnInterrupted>(), hasLength(1));
  });

  test('switching profile while a script runs in the other one is safe', () async {
    final created = world.create('default');
    world.submit(created.runtimeId, 'Why did last night\'s backup fail?');
    final lab = DemoChatBackend(world, profile: 'homelab');
    final page = await lab.conversations(0);
    expect(page, isA<Ok<ConversationPage>>());
    expect((page as Ok<ConversationPage>).value.items.every((c) => c.profile == 'homelab'), isTrue);
    await drain();
    expect(events.whereType<MessageCompleted>(), hasLength(1));
    expect(events.whereType<TurnFailed>(), isEmpty);
  });

  test('model options report usage, and a switch is remembered', () {
    final options = world.modelOptions;
    expect(options.usable.where((p) => p.usage != null), hasLength(2));
    final run = world.create('default').runtimeId;
    final change = world.switchModel(run, 'gpt-6.1', 'openai-codex');
    expect(change.model, 'gpt-6.1');
    expect(world.modelOptions.model, 'gpt-6.1');
    expect(events.whereType<ModelChanged>().single.model, 'gpt-6.1');
  });

  test('the backend answers everything with Ok', () async {
    final chat = DemoChatBackend(world, profile: 'default');
    expect(await chat.profiles(), isA<Ok<List<AgentProfile>>>());
    expect(await chat.commands(), isA<Ok<List<SlashCommand>>>());
    expect(await chat.archivedConversations(0), isA<Ok<ConversationPage>>());
    expect(await chat.search('backup'), isA<Ok<List<SearchHit>>>());
  });
}
```

- [ ] **Step 2: Run them to see them fail.** `flutter test test/demo/demo_world_test.dart` → compile errors.

- [ ] **Step 3: Write `lib/demo/demo_content.dart`** (data only):

```dart
/// What the demo shows: made-up conversations, profiles, models and the
/// scripted turns behind the suggested prompts. Data only, so the content can
/// be rewritten without touching how it plays.
library;

import '../data/chat/chat_models.dart';
import 'demo_script.dart';

/// The link in the fallback reply that leaves the demo.
const leaveDemoLink = 'iris://leave-demo';

/// The reply to anything that is not a suggested prompt.
const demoFallback =
    "This is a demo, so replies are pre-written and I can't act on that. Try "
    'one of the suggestions, or [connect your own Hermes server]'
    '($leaveDemoLink) to talk to your agent.';

const demoProfiles = [
  AgentProfile(
    name: 'default',
    isDefault: true,
    model: 'claude-sonnet-5-5',
    provider: 'anthropic',
  ),
  AgentProfile(name: 'homelab', model: 'gpt-6.1', provider: 'openai-codex'),
];

const demoCommands = [
  SlashCommand(name: '/retry', description: 'Run the last turn again'),
  SlashCommand(name: '/model', description: 'Switch the model'),
  SlashCommand(name: '/help', description: 'What commands there are'),
];

/// A stored conversation to seed the demo with.
final class DemoSeed {
  const DemoSeed({
    required this.id,
    required this.title,
    required this.profile,
    required this.age,
    required this.items,
    this.source,
    this.archived = false,
  });

  final String id;
  final String title;
  final String profile;

  /// How long before "now" it started.
  final Duration age;
  final List<TranscriptItem> items;
  final String? source;
  final bool archived;
}

const demoSeeds = [
  DemoSeed(
    id: 'backup-ok',
    title: 'Nightly backup to B2',
    profile: 'default',
    age: Duration(hours: 2),
    source: 'telegram',
    items: [
      UserTurn(id: 'backup-ok-1', text: 'Did the nightly backup run?'),
      ToolCall(
        id: 'backup-ok-2',
        name: 'terminal',
        arguments: 'systemctl status restic-backup.timer',
        output:
            '● restic-backup.timer - Nightly restic backup\n'
            '   Active: active (waiting) since Wed 03:00:02 IST\n'
            '  Trigger: Thu 2026-10-16 03:00:00 IST',
      ),
      AssistantTurn(
        id: 'backup-ok-3',
        text:
            'Yes. The timer fired at 03:00 and the run finished in 6 min 12 s. '
            '214 MB was added; the repository is 48.3 GB across 31 snapshots.',
      ),
    ],
  ),
  DemoSeed(
    id: 'caddy',
    title: 'Caddy certificate renewal',
    profile: 'default',
    age: Duration(hours: 5),
    source: 'cli',
    items: [
      UserTurn(
        id: 'caddy-1',
        text: 'When does the certificate for photos.home.example renew?',
      ),
      AssistantTurn(
        id: 'caddy-2',
        reasoning: 'Caddy manages this on its own; check its certificate store.',
        text:
            'Caddy renews it automatically about 30 days before it expires. '
            'The current certificate is valid until **12 December 2026**, so '
            'renewal starts around 12 November. Nothing to do.',
      ),
    ],
  ),
  DemoSeed(
    id: 'grafana',
    title: 'Grafana dashboard for the NAS',
    profile: 'default',
    age: Duration(days: 1),
    items: [
      UserTurn(
        id: 'grafana-1',
        text: 'Add a panel for disk temperatures to the NAS dashboard',
      ),
      ToolCall(
        id: 'grafana-2',
        name: 'write_file',
        arguments: 'dashboards/nas.json',
        output: 'Wrote 4.1 KB',
      ),
      AssistantTurn(
        id: 'grafana-3',
        text:
            'Added a **Disk temperatures** panel: a time series with one line '
            'per drive and a warning at 50 °C. Reload the dashboard to see it.',
      ),
    ],
  ),
  DemoSeed(
    id: 'morning',
    title: 'Morning summary',
    profile: 'default',
    age: Duration(days: 1, hours: 3),
    source: 'telegram',
    items: [
      UserTurn(id: 'morning-1', text: 'Summarise what happened overnight'),
      AssistantTurn(
        id: 'morning-2',
        text:
            'A quiet night:\n\n'
            '- The backup finished at 03:06\n'
            '- Two failed SSH logins from 203.0.113.7, blocked by fail2ban\n'
            '- Jellyfin updated to 10.11.2 and restarted cleanly',
      ),
    ],
  ),
  DemoSeed(
    id: 'postgres',
    title: 'Upgrade Postgres 15 to 16',
    profile: 'default',
    age: Duration(days: 9),
    archived: true,
    items: [
      UserTurn(id: 'postgres-1', text: 'Plan the Postgres 15 to 16 upgrade'),
      AssistantTurn(
        id: 'postgres-2',
        text:
            'Done last week: dumped with `pg_dumpall`, restored into 16 and '
            'switched the app over. The 15 cluster is still in '
            '`/var/lib/postgresql/15` if you want to keep it a little longer.',
      ),
    ],
  ),
  DemoSeed(
    id: 'proxmox',
    title: 'Proxmox host load',
    profile: 'homelab',
    age: Duration(hours: 3),
    items: [
      UserTurn(id: 'proxmox-1', text: 'Why is pve1 so busy?'),
      ToolCall(
        id: 'proxmox-2',
        name: 'terminal',
        arguments: 'top -b -n 1 | head -12',
        output:
            'load average: 7.92, 6.40, 5.11\n'
            '  PID USER   %CPU COMMAND\n'
            ' 2211 root    310 kvm (vm 104: media)',
      ),
      AssistantTurn(
        id: 'proxmox-3',
        text:
            'VM 104 (media) is transcoding and using about three cores. It is '
            'the scheduled library scan and should settle within the hour.',
      ),
    ],
  ),
  DemoSeed(
    id: 'pihole',
    title: 'Pi-hole blocklists',
    profile: 'homelab',
    age: Duration(days: 2),
    items: [
      UserTurn(id: 'pihole-1', text: 'Add the OISD blocklist to Pi-hole'),
      AssistantTurn(
        id: 'pihole-2',
        text:
            'Added **OISD big** and updated gravity: 312,904 domains are now '
            'blocked, up from 187,330.',
      ),
    ],
  ),
  DemoSeed(
    id: 'wireguard',
    title: 'Old VPN peer',
    profile: 'homelab',
    age: Duration(days: 20),
    archived: true,
    items: [
      UserTurn(
        id: 'wireguard-1',
        text: 'Remove the old WireGuard peer for the laptop',
      ),
      AssistantTurn(
        id: 'wireguard-2',
        text:
            'Removed peer `laptop-2023` from wg0 and reloaded. Two peers '
            'remain: phone and work.',
      ),
    ],
  ),
];

/// The model in use when the demo starts.
const demoModel = ('claude-sonnet-5-5', 'anthropic');

/// Models and usage, built at [now] so the reset times read sensibly.
ModelOptions demoModelOptions(DateTime now, {required String model, required String provider}) =>
    ModelOptions(
      model: model,
      provider: provider,
      providers: [
        ModelProvider(
          slug: 'anthropic',
          name: 'Anthropic',
          models: const ['claude-sonnet-5-5', 'claude-opus-5-5', 'claude-haiku-5-5'],
          isCurrent: provider == 'anthropic',
          usage: ProviderUsage(
            windows: [
              UsageWindow(
                label: 'Current session',
                usedPercent: 34,
                resetsAt: now.add(const Duration(hours: 3)),
              ),
              UsageWindow(
                label: 'Current week',
                usedPercent: 61,
                resetsAt: now.add(const Duration(days: 4)),
              ),
            ],
          ),
        ),
        ModelProvider(
          slug: 'openai-codex',
          name: 'OpenAI Codex',
          models: const ['gpt-6.1', 'gpt-6.1-mini'],
          isCurrent: provider == 'openai-codex',
          usage: ProviderUsage(
            windows: [
              UsageWindow(
                label: 'Session',
                usedPercent: 12,
                resetsAt: now.add(const Duration(hours: 1)),
              ),
              UsageWindow(
                label: 'Weekly',
                usedPercent: 45,
                resetsAt: now.add(const Duration(days: 2)),
              ),
            ],
          ),
        ),
      ],
    );

const demoScripts = [
  DemoScript(
    prompt: 'Check disk space on my server',
    title: 'Disk space on the server',
    steps: [
      ContextStep(18),
      ThinkStep(
        'Start with df to see which filesystem is tight, then look at what '
        'is using the space.',
      ),
      ToolStep(
        'terminal',
        input: 'df -h -x tmpfs -x devtmpfs',
        output:
            'Filesystem      Size  Used Avail Use% Mounted on\n'
            '/dev/nvme0n1p2  468G  431G   14G  97% /\n'
            '/dev/sda1       3.6T  2.1T  1.5T  59% /mnt/media',
        duration: Duration(milliseconds: 1600),
      ),
      ToolStep(
        'terminal',
        input: 'docker system df',
        output:
            'TYPE          TOTAL  ACTIVE  SIZE     RECLAIMABLE\n'
            'Images        41     12      58.3GB   39.7GB (68%)\n'
            'Containers    14     12      1.2GB    0B (0%)\n'
            'Build Cache   96     0       11.4GB   11.4GB',
        duration: Duration(milliseconds: 1400),
      ),
      ThinkStep(
        'The root disk is at 97%. Old Docker images are most of what can be '
        'freed.',
      ),
      ApprovalStep(
        command: 'docker image prune -a --filter "until=720h"',
        description: 'Remove Docker images unused for 30 days',
        ifApproved: [
          SecretStep('sudo docker image prune -a --filter "until=720h"'),
          ToolStep(
            'terminal',
            input: 'sudo docker image prune -a --filter "until=720h"',
            output:
                'Deleted Images:\n'
                'untagged: ghcr.io/example/photos-server:v1.118.0\n'
                '… and 27 more\n\n'
                'Total reclaimed space: 37.9GB',
            duration: Duration(milliseconds: 2400),
          ),
          ContextStep(31),
          SayStep(
            'Freed **37.9 GB**. The root disk is now at **89%**, with 52 GB '
            'free.\n\n'
            '| Filesystem | Before | After |\n'
            '|---|---|---|\n'
            '| `/` | 97% | 89% |\n'
            '| `/mnt/media` | 59% | 59% |\n\n'
            'The build cache holds another 11.4 GB; `docker builder prune` '
            'clears it if you want more room.',
          ),
        ],
        ifDenied: [
          SayStep(
            'Left everything in place. If you want room later without '
            'touching images, these are safe to clear:\n\n'
            '- **Build cache**: 11.4 GB (`docker builder prune`)\n'
            '- **Journal logs** older than two weeks: about 2.1 GB '
            '(`journalctl --vacuum-time=2weeks`)',
          ),
        ],
      ),
    ],
  ),
  DemoScript(
    prompt: "Why did last night's backup fail?",
    title: "Last night's backup",
    steps: [
      ContextStep(22),
      ThinkStep("Check the backup unit's journal for the last run."),
      ToolStep(
        'terminal',
        input: 'journalctl -u restic-backup --since yesterday | tail -3',
        output:
            'Oct 15 03:00:02 nas restic[4121]: Fatal: unable to open repository '
            'at b2:homelab-backup:\n'
            'Oct 15 03:00:02 nas restic[4121]: B2 returned 401: bad_auth_token '
            '(application key expired)\n'
            "Oct 15 03:00:02 nas systemd[1]: restic-backup.service: Failed with "
            "result 'exit-code'.",
      ),
      ThinkStep(
        'The B2 application key expired. A new key goes into the environment '
        'file, then one manual run confirms it.',
      ),
      SayStep(
        'The backup failed because the **Backblaze B2 application key '
        'expired** on 14 October. Restic never reached the repository, so '
        'nothing was written and the existing snapshots are intact.\n\n'
        'Create a new application key for the `homelab-backup` bucket in the '
        'B2 console, then update the environment file:\n\n'
        '```bash\n'
        '# /etc/restic/b2.env\n'
        'B2_ACCOUNT_ID=00a1b2c3d4e5f60000000003\n'
        'B2_ACCOUNT_KEY=<new application key>\n'
        'RESTIC_REPOSITORY=b2:homelab-backup:\n'
        '```\n\n'
        'Then run it once by hand to confirm:\n\n'
        '```bash\n'
        'sudo systemctl start restic-backup.service\n'
        'journalctl -u restic-backup -f\n'
        '```',
      ),
    ],
  ),
  DemoScript(
    prompt: "Summarise this week's GitHub issues",
    title: "This week's GitHub issues",
    steps: [
      ContextStep(26),
      ToolStep(
        'github',
        input: 'list issues in acme/homelab-scripts updated since Oct 8',
        output: '9 issues: 3 bug, 4 enhancement, 2 question',
        duration: Duration(milliseconds: 1800),
      ),
      ThinkStep('Group them by label and pick out anything that could lose data.'),
      SayStep(
        'Nine issues moved this week in **acme/homelab-scripts**:\n\n'
        '| Label | Open | Closed | Notable |\n'
        '|---|---|---|---|\n'
        '| bug | 2 | 1 | #142: the backup script ignores `--dry-run` |\n'
        '| enhancement | 3 | 1 | #139: support Podman as well as Docker |\n'
        '| question | 1 | 1 | #145: how to restore one file |\n\n'
        '**Needs attention:** #142, because a dry run actually deletes old '
        'snapshots. It has a reproduction and a suggested fix.',
      ),
    ],
  ),
  DemoScript(
    prompt: 'Restart the media server',
    title: 'Restart the media server',
    firstRun: [
      ThinkStep('Jellyfin runs as a Docker container on the media VM.'),
      ApprovalStep(
        command: 'docker restart jellyfin',
        description: 'Restart the Jellyfin container',
        ifApproved: [
          ToolStep(
            'terminal',
            input: 'docker restart jellyfin',
            output:
                'Error response from daemon: Cannot restart container '
                'jellyfin: port 8096 is already allocated',
            duration: Duration(milliseconds: 1300),
            failed: true,
          ),
          FailStep('Restarting Jellyfin failed: port 8096 is already in use.'),
        ],
        ifDenied: [SayStep('Left Jellyfin running as it is.')],
      ),
    ],
    steps: [
      ThinkStep('Something still holds port 8096. Find it before restarting.'),
      ApprovalStep(
        command: 'docker restart jellyfin',
        description: 'Restart the Jellyfin container',
        ifApproved: [
          ToolStep(
            'terminal',
            input: 'ss -ltnp "sport = :8096"',
            output: 'LISTEN 0 4096 *:8096 *:* users:(("jellyfin",pid=1882))',
            duration: Duration(milliseconds: 1200),
          ),
          ToolStep(
            'terminal',
            input: 'kill 1882 && docker restart jellyfin',
            output: 'jellyfin',
            duration: Duration(milliseconds: 1800),
          ),
          SayStep(
            'Jellyfin is back up. A stale process from the last update was '
            'still holding port 8096; I stopped it and restarted the '
            'container. It answered on **http://media.home.example:8096** '
            'within four seconds.',
          ),
        ],
        ifDenied: [SayStep('Left Jellyfin running as it is.')],
      ),
    ],
  ),
];

/// The script for [text], if it is one of the suggested prompts.
DemoScript? demoScriptFor(String text) {
  final wanted = text.trim().toLowerCase();
  for (final script in demoScripts) {
    if (script.prompt.toLowerCase() == wanted) return script;
  }
  return null;
}
```

- [ ] **Step 4: Write `lib/demo/demo_world.dart`:**

```dart
/// The demo's whole state: conversations, the model, and the scripts playing.
///
/// It stands in for a Hermes server. One world lives for one demo session and
/// is shared by every profile's `DemoChatBackend`, so switching profile does
/// not lose a turn that is still playing.
library;

import 'dart:async';

import '../data/chat/chat_backend.dart';
import '../data/chat/chat_event.dart';
import '../data/chat/chat_models.dart';
import 'demo_content.dart';
import 'demo_script.dart';
import 'script_player.dart';

final class _Conversation {
  _Conversation({
    required this.id,
    required this.title,
    required this.profile,
    required this.startedAt,
    required this.items,
    this.source,
    this.archived = false,
  });

  final String id;
  String title;
  final String profile;
  final DateTime startedAt;
  final List<TranscriptItem> items;
  final String? source;
  bool archived;
  double context = 12;

  ConversationSummary get summary => ConversationSummary(
    id: id,
    title: title,
    startedAt: startedAt,
    messageCount: items.where((i) => i is UserTurn || i is AssistantTurn).length,
    source: source,
    profile: profile,
  );
}

final class DemoWorld {
  DemoWorld({DateTime Function() clock = DateTime.now, Delay delay = realDelay})
    : _clock = clock,
      _delay = delay {
    final now = clock();
    for (final seed in demoSeeds) {
      _conversations.add(
        _Conversation(
          id: seed.id,
          title: seed.title,
          profile: seed.profile,
          startedAt: now.subtract(seed.age),
          items: [...seed.items],
          source: seed.source,
          archived: seed.archived,
        ),
      );
    }
  }

  static const _pageSize = 20;
  static const _runPrefix = 'demo-run-';

  final DateTime Function() _clock;
  final Delay _delay;
  final _events = StreamController<ChatEvent>.broadcast();

  /// Newest first.
  final List<_Conversation> _conversations = [];
  final Map<String, ScriptPlayer> _players = {};
  final Map<String, String> _lastPrompt = {};
  final Set<String> _played = {};
  var _created = 0;
  String _model = demoModel.$1;
  String _provider = demoModel.$2;

  static String runtimeIdFor(String storedId) => '$_runPrefix$storedId';

  static String _storedIdFor(String runtimeId) =>
      runtimeId.startsWith(_runPrefix)
      ? runtimeId.substring(_runPrefix.length)
      : runtimeId;

  Stream<ChatEvent> get events => _events.stream;

  List<AgentProfile> get profiles => demoProfiles;

  _Conversation? _find(String storedId) {
    for (final conversation in _conversations) {
      if (conversation.id == storedId) return conversation;
    }
    return null;
  }

  ConversationPage page(String profile, int offset, {required bool archived}) {
    final rows = [
      for (final c in _conversations)
        if (c.profile == profile && c.archived == archived) c.summary,
    ];
    final start = offset.clamp(0, rows.length);
    final end = (start + _pageSize).clamp(0, rows.length);
    return ConversationPage(items: rows.sublist(start, end), total: rows.length);
  }

  HistoryPage history(String storedId) =>
      HistoryPage(items: List.of(_find(storedId)?.items ?? const []));

  NewConversation create(String profile) {
    final id = 'demo-new-${_created++}';
    _conversations.insert(
      0,
      _Conversation(
        id: id,
        title: '',
        profile: profile,
        startedAt: _clock(),
        items: [],
      ),
    );
    return NewConversation(runtimeId: runtimeIdFor(id), storedId: id);
  }

  ResumedConversation resume(String storedId) => ResumedConversation(
    runtimeId: runtimeIdFor(storedId),
    running: _players[storedId]?.running ?? false,
    model: _model,
    provider: _provider,
    context: ContextUsage(percent: _find(storedId)?.context ?? 12),
  );

  void submit(String runtimeId, String text) {
    final storedId = _storedIdFor(runtimeId);
    final conversation = _find(storedId);
    if (conversation == null) return;
    conversation.items.add(
      UserTurn(id: '$storedId-user-${conversation.items.length}', text: text),
    );
    final script = demoScriptFor(text);
    if (conversation.title.isEmpty) {
      conversation.title = script?.title ?? _titleFrom(text);
      _events.add(TitleChanged(runtimeId, conversation.title));
    }
    final firstRun = script?.firstRun;
    final key = '$storedId/${script?.prompt}';
    final steps = script == null
        ? const <DemoStep>[SayStep(demoFallback)]
        : firstRun != null && !_played.contains(key)
        ? firstRun
        : script.steps;
    _played.add(key);
    _lastPrompt[storedId] = text;
    final player = _players[storedId] = ScriptPlayer(
      sessionId: runtimeId,
      emit: (event) {
        if (event is ContextChanged) conversation.context = event.usage.percent;
        if (!_events.isClosed) _events.add(event);
      },
      record: conversation.items.add,
      delay: _delay,
    );
    unawaited(player.play(steps));
  }

  static String _titleFrom(String text) {
    final line = text.trim().split('\n').first;
    return line.length <= 40 ? line : '${line.substring(0, 39)}…';
  }

  void interrupt(String runtimeId) =>
      _players[_storedIdFor(runtimeId)]?.stop();

  SteerOutcome steer(String runtimeId, String text) =>
      _players[_storedIdFor(runtimeId)]?.steer(text) ?? false
      ? SteerOutcome.accepted
      : SteerOutcome.rejected;

  SlashOutcome slash(String runtimeId, String command) {
    final storedId = _storedIdFor(runtimeId);
    final name = command.trim().split(' ').first;
    if (name != '/retry') {
      return const SlashOutcome(
        kind: SlashKind.exec,
        text: 'Not available in the demo.',
      );
    }
    final prompt = _lastPrompt[storedId];
    final conversation = _find(storedId);
    if (prompt == null || conversation == null) {
      return const SlashOutcome(kind: SlashKind.exec, text: 'Nothing to retry.');
    }
    // As Hermes does: the failed exchange goes, and the prompt is sent again.
    final last = conversation.items.lastIndexWhere((item) => item is UserTurn);
    if (last >= 0) conversation.items.removeRange(last, conversation.items.length);
    return SlashOutcome(kind: SlashKind.send, text: prompt);
  }

  void answerApproval(ApprovalRequest request, String choice) =>
      _players[_storedIdFor(request.sessionId)]?.answerApproval(
        approved: choice != 'deny',
      );

  /// The value typed is not taken: the demo needs only to know it was sent.
  void answerInput(InputRequest request) =>
      _players[_storedIdFor(request.sessionId)]?.answerSecret();

  void rename(String storedId, String title) => _find(storedId)?.title = title;

  void setArchived(String storedId, {required bool archived}) =>
      _find(storedId)?.archived = archived;

  List<SearchHit> search(String profile, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final c in _conversations)
        if (c.profile == profile)
          if (_hit(c, needle) case final hit?) hit,
    ];
  }

  SearchHit? _hit(_Conversation c, String needle) {
    for (final item in c.items) {
      final text = switch (item) {
        UserTurn(:final text) => text,
        AssistantTurn(:final text) => text,
        _ => '',
      };
      final at = text.toLowerCase().indexOf(needle);
      if (at < 0) continue;
      final start = (at - 30).clamp(0, text.length);
      final end = (at + needle.length + 50).clamp(0, text.length);
      return SearchHit(
        storedId: c.id,
        title: c.title,
        archived: c.archived,
        messageCount: c.summary.messageCount,
        lastActive: c.startedAt,
        snippet: [
          SnippetRun('${start > 0 ? '…' : ''}${text.substring(start, at)}'),
          SnippetRun(text.substring(at, at + needle.length), matched: true),
          SnippetRun('${text.substring(at + needle.length, end)}${end < text.length ? '…' : ''}'),
        ],
      );
    }
    if (c.title.toLowerCase().contains(needle)) {
      return SearchHit(
        storedId: c.id,
        title: c.title,
        archived: c.archived,
        messageCount: c.summary.messageCount,
        lastActive: c.startedAt,
      );
    }
    return null;
  }

  ModelOptions get modelOptions =>
      demoModelOptions(_clock(), model: _model, provider: _provider);

  ModelSwitch switchModel(String runtimeId, String model, String provider) {
    _model = model;
    _provider = provider;
    _events.add(ModelChanged(runtimeId, model: model, provider: provider));
    return ModelSwitch(model: model);
  }

  /// Ends every script without a word and closes the event stream.
  Future<void> dispose() async {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    await _events.close();
  }
}
```

- [ ] **Step 5: Write `lib/demo/demo_chat_backend.dart`:**

```dart
/// The demo, seen through one profile, as the `ChatBackend` the screens use.
library;

import '../core/result.dart';
import '../data/chat/chat_backend.dart';
import '../data/chat/chat_event.dart';
import '../data/chat/chat_models.dart';
import 'demo_content.dart';
import 'demo_world.dart';

final class DemoChatBackend implements ChatBackend {
  DemoChatBackend(this._world, {required this.profile});

  final DemoWorld _world;
  final String profile;

  @override
  Stream<ChatEvent> get events => _world.events;

  @override
  Stream<void> get reconnected => const Stream.empty();

  @override
  Future<Result<ConversationPage>> conversations(int offset) async =>
      Ok(_world.page(profile, offset, archived: false));

  @override
  Future<Result<ConversationPage>> archivedConversations(int offset) async =>
      Ok(_world.page(profile, offset, archived: true));

  @override
  Future<Result<List<AgentProfile>>> profiles() async => Ok(_world.profiles);

  @override
  Future<Result<HistoryPage>> history(
    String storedId, {
    HistoryCursor? before,
  }) async => Ok(_world.history(storedId));

  @override
  Future<Result<ResumedConversation>> resume(String storedId) async =>
      Ok(_world.resume(storedId));

  @override
  Future<Result<NewConversation>> create() async => Ok(_world.create(profile));

  @override
  Future<Result<void>> submit(String runtimeId, String text) async {
    _world.submit(runtimeId, text);
    return const Ok(null);
  }

  @override
  Future<Result<void>> interrupt(String runtimeId) async {
    _world.interrupt(runtimeId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> answerApproval(
    ApprovalRequest request,
    String choice,
  ) async {
    _world.answerApproval(request, choice);
    return const Ok(null);
  }

  @override
  Future<Result<void>> answerClarify(
    ClarifyRequest request,
    ClarifyQuestion question,
    String answer,
  ) async => const Ok(null);

  @override
  Future<Result<void>> answerInput(InputRequest request, String value) async {
    _world.answerInput(request);
    return const Ok(null);
  }

  @override
  Future<Result<ModelOptions>> modelOptions({String? runtimeId}) async =>
      Ok(_world.modelOptions);

  @override
  Future<Result<ModelSwitch>> switchModel(
    String runtimeId, {
    required String model,
    required String provider,
    required bool confirmed,
  }) async => Ok(_world.switchModel(runtimeId, model, provider));

  @override
  Future<Result<List<SlashCommand>>> commands() async => const Ok(demoCommands);

  @override
  Future<Result<SlashOutcome>> runSlash(String runtimeId, String command) async =>
      Ok(_world.slash(runtimeId, command));

  @override
  Future<Result<SteerOutcome>> steer(String runtimeId, String text) async =>
      Ok(_world.steer(runtimeId, text));

  @override
  Future<Result<void>> rename(String storedId, String title) async {
    _world.rename(storedId, title);
    return const Ok(null);
  }

  @override
  Future<Result<void>> setArchived(
    String storedId, {
    required bool archived,
  }) async {
    _world.setArchived(storedId, archived: archived);
    return const Ok(null);
  }

  @override
  Future<Result<List<SearchHit>>> search(String query) async =>
      Ok(_world.search(profile, query));
}
```

  `flutter analyze` will name any `ChatBackend` member this misses (compare with
  `lib/data/chat/chat_backend.dart`'s `abstract interface class ChatBackend`); add it the same way.

- [ ] **Step 6: Run the tests.** `flutter test test/demo/` → all pass. `flutter analyze` → no issues.

- [ ] **Step 7: Commit**

```bash
dart format lib/demo/demo_content.dart lib/demo/demo_world.dart lib/demo/demo_chat_backend.dart test/demo/demo_world_test.dart
git add lib/demo test/demo
git commit -m "feat(demo): an in-memory Hermes with seed conversations and four scripted turns"
```

---

### Task 8: The demo switch in the providers

**Files:**
- Create: `lib/demo/demo_mode.dart`
- Modify: `lib/app/providers.dart`, `lib/features/servers/server_gate.dart`
- Test: `test/demo/demo_mode_test.dart`

**Interfaces:**
- Consumes: `DemoWorld`, `DemoChatBackend` (Task 7); `clockProvider` (`lib/app/providers.dart`).
- Produces: `demoSessionProvider` (`NotifierProvider<DemoSession, DemoWorld?>`, with `enter()` and `leave()`);
  `demoModeProvider` (`Provider<bool>`); `const demoServer`; `final demoCapabilities`;
  `void leaveDemo(BuildContext context)`.

- [ ] **Step 1: Write the failing tests** in `test/demo/demo_mode_test.dart`:

```dart
/// The demo replaces the active server, link and chat, and nothing else.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/data/rpc/dashboard_session.dart';
import 'package:iris/demo/demo_chat_backend.dart';
import 'package:iris/demo/demo_mode.dart';

import '../support/fakes.dart';

void main() {
  late IrisDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = IrisDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        credentialStoreProvider.overrideWithValue(FakeCredentialStore()),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('off by default: no server, an idle link, no chat', () async {
    final link = container.listen(activeLinkProvider, (_, _) {});
    addTearDown(link.close);
    final chat = container.listen(activeChatProvider, (_, _) {});
    addTearDown(chat.close);
    expect(container.read(demoModeProvider), isFalse);
    expect(container.read(activeServerProvider), isNull);
    expect((await container.read(activeLinkProvider.future)).phase, LinkPhase.idle);
    expect(await container.read(activeChatProvider.future), isNull);
  });

  test('on: the demo server, a live link, a demo chat and no session', () async {
    container.read(demoSessionProvider.notifier).enter();
    final link = container.listen(activeLinkProvider, (_, _) {});
    addTearDown(link.close);
    final chat = container.listen(activeChatProvider, (_, _) {});
    addTearDown(chat.close);
    final session = container.listen(activeSessionProvider, (_, _) {});
    addTearDown(session.close);

    expect(container.read(demoModeProvider), isTrue);
    expect(container.read(activeServerProvider), demoServer);
    expect((await container.read(activeLinkProvider.future)).phase, LinkPhase.live);
    expect(await container.read(activeChatProvider.future), isA<DemoChatBackend>());
    expect(await container.read(activeSessionProvider.future), isNull);
  });

  test('leaving puts everything back', () async {
    final notifier = container.read(demoSessionProvider.notifier)..enter();
    final chat = container.listen(activeChatProvider, (_, _) {});
    addTearDown(chat.close);
    await container.read(activeChatProvider.future);
    notifier.leave();
    expect(container.read(demoModeProvider), isFalse);
    expect(container.read(activeServerProvider), isNull);
    expect(await container.read(activeChatProvider.future), isNull);
  });
}
```

- [ ] **Step 2: Run them to see them fail.** `flutter test test/demo/demo_mode_test.dart` → compile errors.

- [ ] **Step 3: Write `lib/demo/demo_mode.dart`:**

```dart
/// Whether the app is showing the demo, and how to leave it.
///
/// Held in memory only: the demo is a look around, so a fresh launch always
/// starts at the welcome screen.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/net/capabilities.dart';
import '../data/net/server_config.dart';
import 'demo_world.dart';

/// The demo's world while it is shown; null otherwise.
final demoSessionProvider = NotifierProvider<DemoSession, DemoWorld?>(
  DemoSession.new,
);

class DemoSession extends Notifier<DemoWorld?> {
  DemoWorld? _world;

  @override
  DemoWorld? build() {
    ref.onDispose(() => unawaited(_world?.dispose()));
    return null;
  }

  void enter() {
    if (state != null) return;
    state = _world = DemoWorld(clock: ref.read(clockProvider));
  }

  void leave() {
    final world = _world;
    if (world == null) return;
    _world = null;
    state = null;
    unawaited(world.dispose());
  }
}

final demoModeProvider = Provider<bool>(
  (ref) => ref.watch(demoSessionProvider) != null,
);

/// The server the demo pretends to be. Its address is never contacted.
const demoServer = ServerConfig(
  id: 'demo',
  baseUrl: 'https://demo.iris',
  label: 'Demo',
);

final demoCapabilities = ServerCapabilities(
  available: const {ServerCapability.profiles, ServerCapability.sessionSearch},
  probedAt: DateTime(2026, 10, 15),
  serverVersion: 'demo',
);

/// Leaves the demo from anywhere: back to the bottom of the stack, where the
/// gate then shows the welcome screen.
void leaveDemo(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  Navigator.of(context).popUntil((route) => route.isFirst);
  container.read(demoSessionProvider.notifier).leave();
}
```

- [ ] **Step 4: Branch the providers** in `lib/app/providers.dart` (add
`import '../demo/demo_chat_backend.dart';` and `import '../demo/demo_mode.dart';`):

  - `activeServerProvider`, first line of the body: `if (ref.watch(demoModeProvider)) return demoServer;`
  - `activeSessionProvider`, first line: `if (ref.watch(demoModeProvider)) return null;`
  - `activeLinkProvider`, first lines:

```dart
  if (ref.watch(demoModeProvider)) {
    yield const LinkState(LinkPhase.live);
    return;
  }
```

  - `activeCapabilitiesProvider`, first line:
    `if (ref.watch(demoModeProvider)) return Stream.value(demoCapabilities);`
  - `activeChatProvider`, after `final profile = ref.watch(activeProfileProvider);`:

```dart
  final world = ref.watch(demoSessionProvider);
  if (world != null) return DemoChatBackend(world, profile: profile);
```

- [ ] **Step 5: The gate shows home in the demo.** In `ServerGate.build`, first line:

```dart
    if (ref.watch(demoModeProvider)) return connected(context);
```

(import `../../demo/demo_mode.dart`.)

- [ ] **Step 6: Run the tests.** `flutter test test/demo/demo_mode_test.dart`, then `flutter test` and
`flutter analyze`.

- [ ] **Step 7: Commit**

```bash
dart format lib/demo/demo_mode.dart lib/app/providers.dart lib/features/servers/server_gate.dart test/demo/demo_mode_test.dart
git add lib/demo/demo_mode.dart lib/app/providers.dart lib/features/servers/server_gate.dart test/demo/demo_mode_test.dart
git commit -m "feat(demo): a demo switch the server, link and chat providers honour"
```

---

### Task 9: The demo in the UI

**Files:**
- Modify: `lib/features/servers/welcome_screen.dart`, `lib/features/chat/conversation_list_screen.dart`,
  `lib/features/chat/chat_screen.dart`, `lib/features/chat/transcript_view.dart`,
  `lib/features/settings/settings_screen.dart`, `lib/features/home/link_status_screen.dart`
- Test: `test/features/demo_flow_test.dart`, `test/design/welcome_demo_golden_test.dart`

**Interfaces:**
- Consumes: `demoSessionProvider`, `demoModeProvider`, `leaveDemo` (Task 8); `demoScripts`, `leaveDemoLink`
  (Task 7).
- Produces: `ChatScreen({..., List<String>? suggestions})`.

- [ ] **Step 1: Write the failing tests** in `test/features/demo_flow_test.dart`:

```dart
/// Into the demo, around it, and out again.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/data/db/database.dart';
import 'package:iris/demo/demo_mode.dart';
import 'package:iris/features/chat/chat_screen.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/home/link_status_screen.dart';
import 'package:iris/features/servers/server_gate.dart';
import 'package:iris/features/servers/welcome_screen.dart';
import 'package:iris/features/settings/settings_screen.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  late IrisDatabase db;

  setUp(() => db = IrisDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      credentialStoreProvider.overrideWithValue(FakeCredentialStore()),
    ],
    child: themed(
      ServerGate(connected: (_) => const ConversationListScreen()),
    ),
  );

  /// Lets providers resolve, and a demo turn play a little.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> enterDemo(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.tap(find.text('Try the demo'));
    await settle(tester);
  }

  testWidgets('Try the demo opens home with the Demo pill and its conversations', (
    tester,
  ) async {
    await enterDemo(tester);
    expect(find.byType(ConversationListScreen), findsOneWidget);
    expect(find.text('Demo'), findsWidgets);
    expect(find.text('Nightly backup to B2'), findsOneWidget);
  });

  testWidgets('a new demo chat offers the scripted prompts, and one plays', (
    tester,
  ) async {
    await enterDemo(tester);
    await tester.tap(find.bySemanticsLabel('New conversation'));
    await settle(tester);
    expect(find.text('Check disk space on my server'), findsOneWidget);
    await tester.tap(find.text("Summarise this week's GitHub issues"));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('acme/homelab-scripts'), findsWidgets);
    expect(find.text('Check disk space on my server'), findsNothing);
  });

  testWidgets('the fallback link leaves the demo from inside a chat', (
    tester,
  ) async {
    await enterDemo(tester);
    await tester.tap(find.bySemanticsLabel('New conversation'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'hello there');
    await tester.tap(find.bySemanticsLabel('Send'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.textContaining('connect your own Hermes server'));
    await settle(tester);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WelcomeScreen)),
    );
    expect(container.read(demoModeProvider), isFalse);
  });

  testWidgets('Settings has Leave demo, and it returns to the welcome screen', (
    tester,
  ) async {
    await enterDemo(tester);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Servers'), findsNothing);
    await tester.tap(find.text('Leave demo'));
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('the connection screen in the demo offers no server switcher', (
    tester,
  ) async {
    await enterDemo(tester);
    await tester.tap(find.textContaining('demo.iris'));
    await settle(tester);
    expect(find.byType(LinkStatusScreen), findsOneWidget);
    await tester.tap(find.text('Demo').last);
    await settle(tester);
    expect(find.text('Add server'), findsNothing);
  });
}
```

  `'New conversation'`, `'Settings'` and `'Send'` are semantics labels the app already uses. The hero's gateway
  line reads `demo.iris · Connected`; if the hero formats it differently, adjust the finder but keep the test
  tapping the connection line.

- [ ] **Step 2: Run them to see them fail.** `flutter test test/features/demo_flow_test.dart` → "Try the demo" not
found.

- [ ] **Step 3: The demo row on the welcome screen.** In `welcome_screen.dart`, import `../../demo/demo_mode.dart`,
and after the `for (final mode in ConnectionMode.values) ...` rows and before the final `SizedBox`, add:

```dart
              if (showDemo) ...[
                const SizedBox(height: IrisSpace.xl),
                IrisLabel('No server yet?', color: palette.inkFaint),
                const SizedBox(height: IrisSpace.sm),
                IrisListRow(
                  title: 'Try the demo',
                  subtitle: 'Sample conversations. No server needed.',
                  leading: Icon(
                    Icons.play_circle_outline,
                    size: IrisSize.icon,
                    color: palette.inkMuted,
                  ),
                  onTap: () => ref.read(demoSessionProvider.notifier).enter(),
                ),
              ],
```

- [ ] **Step 4: The Demo pill.** In `conversation_list_screen.dart`, import `../../demo/demo_mode.dart` and
`../../demo/demo_content.dart`.
  - `_HomeBar`: add `required this.demo,` and `final bool demo;`; in its `Row`, after `pill,` add:

```dart
                if (demo) ...[
                  const SizedBox(width: IrisSpace.sm),
                  IrisChip.state('Demo', AgentState.waiting, palette),
                ],
```

  - where `_HomeBar(` is built in `build`, add `demo: ref.watch(demoModeProvider),`
  - `_open`: give `ChatScreen(...)` the argument
    `suggestions: ref.read(demoModeProvider) ? [for (final script in demoScripts) script.prompt] : null,`

- [ ] **Step 5: Suggestions on the chat screen.** In `chat_screen.dart`:
  - `ChatScreen`: add `this.suggestions,` to the constructor and

```dart
  /// What a new chat offers to ask; the general suggestions when null.
  final List<String>? suggestions;
```

  - `_EmptyConversation`: add `required this.suggestions,` and `final List<String> suggestions;`, and loop over
    `suggestions` instead of `_suggestions`
  - where it is built: `_EmptyConversation(onSuggestion: _sendSuggestion, suggestions: widget.suggestions ??
    _suggestions)`

- [ ] **Step 6: The leave link.** In `transcript_view.dart`, import `../../demo/demo_content.dart` and
`../../demo/demo_mode.dart`, and change the `onTapLink` line to:

```dart
              onTapLink: (href) => href == leaveDemoLink
                  ? leaveDemo(context)
                  : unawaited(openLink(href)),
```

- [ ] **Step 7: Leave demo in Settings.** In `settings_screen.dart`, import `../../demo/demo_mode.dart`; replace the
`IrisSettingsGroup(title: 'Server', ...)` expression with:

```dart
            if (ref.watch(demoModeProvider))
              IrisSettingsGroup(
                title: 'Demo',
                children: [
                  IrisSettingsRow(
                    label: 'Leave demo',
                    sub: 'Connect your own Hermes server',
                    onTap: () => leaveDemo(context),
                  ),
                ],
              )
            else
              IrisSettingsGroup(
                title: 'Server',
                children: [
                  // the two existing rows, unchanged
                ],
              ),
```

  Keep the two existing rows ("Servers" and "Connection details") exactly as they are inside the `else` branch.

- [ ] **Step 8: No switcher in the demo.** In `link_status_screen.dart`, import `../../demo/demo_mode.dart`, and on
the server `IrisListRow` change `onTap` to:

```dart
                onTap: ref.watch(demoModeProvider)
                    ? null
                    : () => unawaited(showServerSwitcher(context)),
```

- [ ] **Step 9: Run the flow tests.** `flutter test test/features/demo_flow_test.dart` → pass. Then `flutter test`.

- [ ] **Step 10: Goldens.** Create `test/design/welcome_demo_golden_test.dart`:

```dart
/// The welcome screen, demo home and a demo chat mid-turn, light and dark.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/providers.dart';
import 'package:iris/app/theme_controller.dart';
import 'package:iris/demo/demo_mode.dart';
import 'package:iris/demo/demo_world.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/chat/conversation_list_screen.dart';
import 'package:iris/features/servers/welcome_screen.dart';

import '../support/fonts.dart';

const _phone = Size(390, 844);
final _now = DateTime(2026, 10, 15, 20, 40);

class _FixedTheme extends ThemeController {
  _FixedTheme(this._value);
  final ThemePreference _value;

  @override
  ThemePreference build() => _value;
}

/// A demo already running, on the fixed clock.
class _RunningDemo extends DemoSession {
  @override
  DemoWorld? build() => DemoWorld(clock: () => _now);
}

Widget _framed(Widget screen, {required bool isDark, List<Override> overrides = const []}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: isDark);
  return ProviderScope(
    overrides: [
      themeControllerProvider.overrideWith(
        () => _FixedTheme(
          ThemePreference(mode: isDark ? BrightnessMode.dark : BrightnessMode.light),
        ),
      ),
      clockProvider.overrideWithValue(() => _now),
      ...overrides,
    ],
    child: MediaQuery(
      data: const MediaQueryData(size: _phone, disableAnimations: true),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme,
        builder: (context, navigator) => IrisTheme(
          data: theme,
          child: Material(type: MaterialType.transparency, child: navigator),
        ),
        home: screen,
      ),
    ),
  );
}

void main() {
  setUpAll(loadIrisFonts);

  Future<void> capture(WidgetTester tester, Widget app, String name) async {
    await tester.binding.setSurfaceSize(_phone);
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  for (final isDark in [true, false]) {
    final mode = isDark ? 'dark' : 'light';

    testWidgets('welcome, $mode', (tester) async {
      await capture(
        tester,
        _framed(const WelcomeScreen(), isDark: isDark),
        'screen_welcome_$mode',
      );
    });

    testWidgets('demo home, $mode', (tester) async {
      await capture(
        tester,
        _framed(
          const ConversationListScreen(),
          isDark: isDark,
          overrides: [demoSessionProvider.overrideWith(_RunningDemo.new)],
        ),
        'screen_demo_home_$mode',
      );
    });

    testWidgets('demo chat waiting on an approval, $mode', (tester) async {
      await capture(
        tester,
        _framed(
          const ConversationListScreen(),
          isDark: isDark,
          overrides: [demoSessionProvider.overrideWith(_RunningDemo.new)],
        ),
        'screen_demo_home_$mode',
      );
      await tester.tap(find.bySemanticsLabel('New conversation'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.tap(find.text('Check disk space on my server'));
      // Two tool calls and the thinking, then the approval card waits.
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/screen_demo_chat_$mode.png'),
      );
    });
  }
}
```

  `DemoSession`'s `build` in Task 8 also registers `ref.onDispose`; `_RunningDemo.build` replaces it, so its world
  is not disposed on teardown, which is acceptable in a test. If `ThemePreference`, `BrightnessMode` or
  `themeControllerProvider` live elsewhere, take the imports from `test/design/screens_golden_test.dart`.

  Generate and inspect: `flutter test --update-goldens test/design/welcome_demo_golden_test.dart`, then open each new
  PNG in `test/design/goldens/` with the Read tool. Check:
  - welcome: three mode rows, then "No server yet?" and the quieter demo row
  - demo home: the Demo pill beside the profile pill, the usage strip, demo conversations
  - demo chat: the two tool cards and the approval card for `docker image prune`

  Fix any layout problem (overlap, clipped text, a wrong colour) and regenerate. Then run `flutter test` once more
  without `--update-goldens`.

- [ ] **Step 11: Commit**

```bash
dart format lib/features/servers/welcome_screen.dart lib/features/chat/conversation_list_screen.dart lib/features/chat/chat_screen.dart lib/features/chat/transcript_view.dart lib/features/settings/settings_screen.dart lib/features/home/link_status_screen.dart test/features/demo_flow_test.dart test/design/welcome_demo_golden_test.dart
git add lib test
git commit -m "feat(demo): try the demo from the welcome screen, and leave it from anywhere"
```

---

### Task 10: Verify on the emulator and record it

**Files:**
- Create: `docs/superpowers/plans/2026-10-15-welcome-and-demo-device.md`

- [ ] **Step 1: Release build, fresh install.**

```bash
flutter build apk --release
adb uninstall com.example.iris; adb uninstall com.iflotech.iris
adb install build/app/outputs/flutter-apk/app-release.apk
```

- [ ] **Step 2: The demo with no network.** `adb shell cmd connectivity airplane-mode enable`. Launch the app.
Screenshot (`adb exec-out screencap -p > "$SCRATCH/d1.png"`) and look before every tap. Check, with a screenshot of
each:
  - the welcome screen's four choices
  - "Try the demo" → home with the Demo pill, usage strip and conversations
  - a new chat → the four prompts; "Check disk space on my server" → reasoning, two tool cards, the approval card;
    approve → the sudo card; type anything → the prune and the table reply; the context ring fills
  - "Restart the media server" → approve → failure card → Retry → approve → success
  - typed text → the fallback, and its link → back to the welcome screen
  - search "fail2ban" on home → one hit with the word marked; rename and archive a conversation; Archived lists it
  - switch to the `homelab` profile → its conversations
  - Settings → Leave demo → welcome
  Then `adb shell cmd connectivity airplane-mode disable`.

- [ ] **Step 3: A LAN sign-in.** If the user's Hermes dashboard is reachable from the emulator's network over a
private address, ask the user to type the address and login themselves (never type the user's secrets yourself), in
Same Wi-Fi mode, and confirm it reaches home. If it is not reachable, write that down; Task 1's check already proved
plain http works in a release build.

- [ ] **Step 4: Delete every screenshot** taken in this task once the notes are written.

- [ ] **Step 5: Write the record** `docs/superpowers/plans/2026-10-15-welcome-and-demo-device.md`: the build, the
date, each check above with pass or fail and one line of what was seen, and anything that needs fixing. Fix any
failure found (with a test first where it can be tested), then commit:

```bash
git add docs/superpowers/plans/2026-10-15-welcome-and-demo-device.md
git commit -m "test(device): the welcome screen and the demo on the emulator, offline"
```
