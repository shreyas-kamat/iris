/// A connection request, tolerant of every shape Hermes has used.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/chat/connection_models.dart';

void main() {
  Json payload() => Json.of({
    'op_id': 'op1',
    'seq': 2,
    'deadline_at': 1900000000.5,
    'timeout_seconds': 120,
    'targets': [
      {
        'name': 'Linear',
        'kind': 'connector',
        'action': 'authorize',
        'state': 'pending',
        'connect_url': 'https://linear.app/oauth',
      },
      {
        'name': 'GitHub',
        'kind': 'mcp',
        'action': 'connect',
        'state': 'pending',
        'required_env': [
          {
            'name': 'GITHUB_TOKEN',
            'required': true,
            'secret': true,
            'default': '',
            'prompt': 'Personal access token with repo scope.',
          },
        ],
      },
      {'name': 'release-notes', 'kind': 'skill', 'action': 'enable', 'state': 'pending'},
      {'name': 'security-scan', 'kind': 'plugin', 'action': 'install', 'state': 'pending'},
      {'name': 'Mystery', 'kind': 'teleporter', 'action': 'beam', 'state': 'glowing'},
    ],
  });

  test('parses targets and picks the control each one needs', () {
    final request = ConnectionRequest.parse(payload(), sessionId: 's1')!;
    expect(request.opId, 'op1');
    expect(request.sessionId, 's1');
    expect(request.targets.map((t) => t.control), [
      TargetControl.signIn,
      TargetControl.credentials,
      TargetControl.approve,
      TargetControl.desktopOnly,
      TargetControl.desktopOnly,
    ]);
    expect(request.targets[1].requiredEnv.single.secret, isTrue);
    expect(request.targets[1].requiredEnv.single.prompt, contains('repo scope'));
  });

  test('unknown kinds, actions and states are kept, not thrown on', () {
    final request = ConnectionRequest.parse(payload(), sessionId: 's1')!;
    final odd = request.targets.last;
    expect(odd.kind, TargetKind.other);
    expect(odd.action, TargetAction.other);
    expect(odd.state, TargetState.other);
    expect(odd.control, TargetControl.desktopOnly);
  });

  test('a resolved target needs no control', () {
    final target = ConnectionTarget.parse(Json.of({
      'name': 'x',
      'kind': 'connector',
      'action': 'authorize',
      'state': 'connected',
      'connect_url': 'https://x.test',
    }))!;
    expect(target.control, TargetControl.none);
  });

  test('no op id means no card', () {
    expect(ConnectionRequest.parse(Json.of({'targets': <Object?>[]}), sessionId: 's'), isNull);
  });

  test('the deadline comes from deadline_at, else from the timeout', () {
    final fixed = DateTime.utc(2030);
    final at = ConnectionRequest.parse(
      Json.of({'op_id': 'a', 'deadline_at': fixed.millisecondsSinceEpoch / 1000}),
      sessionId: 's',
      now: DateTime.utc(2029),
    )!;
    expect(at.deadline.toUtc(), fixed);
    final soon = ConnectionRequest.parse(
      Json.of({'op_id': 'a', 'timeout_seconds': 90}),
      sessionId: 's',
      now: DateTime.utc(2029),
    )!;
    expect(soon.deadline, DateTime.utc(2029).add(const Duration(seconds: 90)));
  });

  test('an update replaces target states by name and can settle', () {
    final request = ConnectionRequest.parse(payload(), sessionId: 's1')!;
    final updated = request.withTargets([
      ConnectionTarget.parse(Json.of({
        'name': 'Linear',
        'kind': 'connector',
        'action': 'authorize',
        'state': 'connected',
      }))!,
    ], settled: false);
    expect(updated.targets.firstWhere((t) => t.name == 'Linear').state, TargetState.connected);
    expect(updated.targets, hasLength(5), reason: 'targets not in the update stay');
    expect(updated.settled, isFalse);
    expect(updated.withTargets(const [], settled: true).settled, isTrue);
  });
}
