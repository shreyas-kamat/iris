/// Answering an approval from a notification: Iris opens the chat after the phone is unlocked, finds what is waiting
/// and answers the one the notification named. It never answers what is not there.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/data/push/push_intents.dart';
import 'package:iris/features/chat/chat_controller.dart';

import '../support/fake_chat_backend.dart';

ApprovalRequest _approval(String queueId, String command) => ApprovalRequest(
  sessionId: 'run-1',
  command: command,
  description: 'Run a command',
  choices: const ['once', 'session', 'always', 'deny'],
  queueId: queueId,
);

PushTap _tap(String? action, {String? command}) => PushTap(
  kind: 'approval',
  sessionId: 'stored-1',
  eventId: 'e1',
  action: action,
  command: command,
);

void main() {
  late FakeChatBackend backend;
  late ChatController chat;

  setUp(() {
    backend = FakeChatBackend();
    chat = ChatController(backend, conversationId: 'stored-1');
  });

  tearDown(() {
    chat.dispose();
    backend.close();
  });

  Future<void> openAndApply(PushTap tap) async {
    await chat.open();
    await chat.applyPushAction(tap);
  }

  List<String> notices() => [
    for (final item in chat.value.items)
      if (item is Notice && !item.isError) item.text,
  ];

  List<String> errors() => [
    for (final item in chat.value.items)
      if (item is Notice && item.isError) item.text,
  ];

  test('answer once when pending', () async {
    backend.pendingApprovalList = [_approval('q1', 'rm -rf build')];
    await openAndApply(_tap('once'));

    expect(backend.resolved, ['q1:once']);
    expect(notices(), contains('Approved once.'));
  });

  test('deny', () async {
    backend.pendingApprovalList = [_approval('q1', 'rm -rf build')];
    await openAndApply(_tap('deny'));

    expect(backend.resolved, ['q1:deny']);
    expect(notices(), contains('Denied.'));
  });

  test('answer when nothing is pending', () async {
    backend.pendingApprovalList = [];
    await openAndApply(_tap('once'));

    expect(backend.resolved, isEmpty);
    expect(notices(), contains('That approval is no longer waiting.'));
  });

  test('answered somewhere else between the list and the answer', () async {
    backend.pendingApprovalList = [_approval('q1', 'rm -rf build')];
    backend.resolvedResult = false;
    await openAndApply(_tap('once'));

    expect(backend.resolved, ['q1:once']);
    expect(notices(), contains('That approval was already answered.'));
  });

  test('two pending: answers the one whose command matches', () async {
    backend.pendingApprovalList = [
      _approval('q1', 'ls -la'),
      _approval('q2', 'rm -rf build'),
    ];
    await openAndApply(_tap('deny', command: 'rm -rf build'));

    expect(backend.resolved, ['q2:deny']);
  });

  test('a shortened command in the notification still matches', () async {
    backend.pendingApprovalList = [
      _approval('q1', 'ls -la'),
      _approval('q2', 'rm -rf /var/lib/some/long/path/that/was/cut'),
    ];
    await openAndApply(_tap('once', command: 'rm -rf /var/lib/some/long…'));

    expect(backend.resolved, ['q2:once']);
  });

  test(
    'the shown command is gone and another waits: nothing is answered',
    () async {
      // The notified approval was answered elsewhere; a different one is waiting now. Approving it would approve a
      // command the person never saw.
      backend.pendingApprovalList = [_approval('q2', 'rm -rf build')];
      await openAndApply(_tap('once', command: 'ls -la'));

      expect(backend.resolved, isEmpty);
      expect(notices(), contains('That approval is no longer waiting.'));
      expect(chat.value.approvals.map((a) => a.queueId), ['q2']);
    },
  );

  test('two pending and no matching command: nothing is answered', () async {
    backend.pendingApprovalList = [
      _approval('q1', 'ls -la'),
      _approval('q2', 'rm -rf build'),
    ];
    await openAndApply(_tap('once', command: 'something else'));

    expect(backend.resolved, isEmpty);
    expect(chat.value.approvals.map((a) => a.queueId), ['q1', 'q2']);
  });

  test(
    'two pending and the notification named none: nothing is answered',
    () async {
      backend.pendingApprovalList = [
        _approval('q1', 'ls -la'),
        _approval('q2', 'rm -rf build'),
      ];
      await openAndApply(_tap('once'));

      expect(backend.resolved, isEmpty);
      expect(
        notices(),
        contains('More than one approval is waiting. Choose one here.'),
      );
      expect(chat.value.approvals.map((a) => a.queueId), ['q1', 'q2']);
    },
  );

  test('a tap without an action only opens the chat', () async {
    backend.pendingApprovalList = [_approval('q1', 'rm -rf build')];
    await openAndApply(_tap(null));

    expect(backend.resolved, isEmpty);
    expect(notices(), isEmpty);
  });

  test('a reply notification never answers anything', () async {
    backend.pendingApprovalList = [_approval('q1', 'rm -rf build')];
    await chat.open();
    await chat.applyPushAction(
      const PushTap(kind: 'reply', sessionId: 'stored-1', action: 'once'),
    );

    expect(backend.resolved, isEmpty);
  });

  test('the card for the answered approval goes', () async {
    final request = _approval('q1', 'rm -rf build');
    backend.pendingApprovalList = [request];
    await chat.open();
    // The card was already on screen, re-announced by the resume.
    chat.value = chat.value.withApproval(request);
    expect(chat.value.approvals, hasLength(1));

    await chat.applyPushAction(_tap('once'));

    expect(chat.value.approvals, isEmpty);
  });

  test('a failed list is said, and nothing is answered', () async {
    backend.pendingFailure = const IrisFailure(FailureKind.offline);
    await openAndApply(_tap('once'));

    expect(backend.resolved, isEmpty);
    expect(notices(), isEmpty);
    expect(errors(), isNotEmpty);
  });

  test('a failed answer keeps the card and says so', () async {
    backend.pendingApprovalList = [_approval('q1', 'rm -rf build')];
    backend.answerResult = const Err(IrisFailure(FailureKind.offline));
    await chat.open();
    chat.value = chat.value.withApproval(backend.pendingApprovalList.single);
    await chat.applyPushAction(_tap('once'));

    expect(chat.value.approvals, hasLength(1));
    expect(errors().single, contains('Could not send the answer'));
    expect(notices(), isNot(contains('Approved once.')));
  });
}
