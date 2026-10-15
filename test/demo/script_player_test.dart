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
    expect(
      events.first,
      isA<BusyChanged>().having((e) => e.busy, 'busy', isTrue),
    );
    expect(
      events.last,
      isA<BusyChanged>().having((e) => e.busy, 'busy', isFalse),
    );
    // Each think step ends with a newline, so two read as separate lines.
    expect(
      events.whereType<ReasoningDelta>().map((e) => e.text).join(),
      'Look at the disk first.\n',
    );
    expect(events.whereType<ToolStarted>().single.input, 'df -h');
    expect(events.whereType<ToolCompleted>().single.output, '97% /');
    expect(
      events.whereType<TextDelta>().map((e) => e.text).join(),
      'The disk is nearly full.',
    );
    expect(
      events.whereType<MessageCompleted>().single.content,
      'The disk is nearly full.',
    );
    expect(events.every((e) => e.sessionId == 's'), isTrue);
    expect(recorded.map((item) => item.runtimeType), [
      AssistantTurn,
      ToolCall,
      AssistantTurn,
    ]);
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
    expect(
      events.last,
      isA<BusyChanged>().having((e) => e.busy, 'busy', isFalse),
    );
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
    expect(events.whereType<MessageCompleted>().map((e) => e.content), [
      'First.',
      '_Noted: thanks._',
    ]);
  });

  test('a failure ends the turn as failed and is recorded for retry', () async {
    await player.play(const [
      FailStep('Port 8096 is already in use.'),
      SayStep('never'),
    ]);
    expect(
      events.whereType<TurnFailed>().single.message,
      'Port 8096 is already in use.',
    );
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
