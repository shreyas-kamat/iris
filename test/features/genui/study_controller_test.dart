/// Starting a study: a new "Iris setup" chat is created, the study is asked for in a plain sentence, and progress is
/// read from the chat and from what the plugin holds.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/genui/personal_models.dart';
import 'package:iris/features/genui/study_controller.dart';

import '../../support/fake_chat_backend.dart';
import '../../support/fake_genui_api.dart';

void main() {
  late FakeChatBackend backend;
  late FakeGenUiApi api;
  late StudyController study;

  setUp(() {
    backend = FakeChatBackend();
    api = FakeGenUiApi();
    study = StudyController(
      backend,
      api,
      pollEvery: const Duration(seconds: 1),
    );
  });

  tearDown(() async {
    study.dispose();
    await backend.close();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('starts at the intro with nothing found', () {
    expect(study.value.phase, StudyPhase.intro);
    expect(study.value.proposedTemplates, 0);
    expect(study.value.profileProposed, isFalse);
  });

  test(
    'start creates a chat, asks for the study in a sentence and names it',
    () async {
      await study.start();
      expect(backend.calls, contains('create'));
      final (runtime, text) = backend.submitted.single;
      expect(runtime, 'run-new');
      expect(text, contains('iris-study'));
      expect(text, contains('iris_profile_propose'));
      expect(
        text,
        isNot(startsWith('/')),
        reason: 'a sentence, not a slash command',
      );
      expect(backend.renames.single, ('stored-new', 'Iris setup'));
      expect(study.value.phase, StudyPhase.working);
      expect(study.value.conversationId, 'stored-new');
    },
  );

  test('a chat that cannot be created fails with the reason', () async {
    backend.createResult = const Err(
      IrisFailure(FailureKind.offline, message: 'No route'),
    );
    await study.start();
    expect(study.value.phase, StudyPhase.failed);
    expect(study.value.message, isNotEmpty);
    expect(backend.submitted, isEmpty);
  });

  test('it counts proposals while the agent works', () async {
    await study.start();
    api
      ..profile = const WorkProfile(
        summary: 'Engineer',
        chips: [],
        status: PersonalStatus.proposed,
        rev: 1,
      )
      ..stored = [
        sampleTemplate('a'),
        sampleTemplate('b', kind: TemplateKind.replyKit),
        sampleTemplate('c', status: PersonalStatus.approved),
      ];
    await study.refresh();
    expect(study.value.profileProposed, isTrue);
    expect(
      study.value.proposedTemplates,
      2,
      reason: 'approved ones are not new',
    );
    expect(study.value.proposedKits, 1);
    expect(study.value.phase, StudyPhase.working);
  });

  test('it polls on a timer while working, and stops when disposed', () {
    fakeAsync((async) {
      final s = StudyController(
        backend,
        api,
        pollEvery: const Duration(seconds: 1),
      );
      s.start();
      async.flushMicrotasks();
      final before = api.calls.length;
      async.elapse(const Duration(seconds: 3));
      expect(api.calls.length, greaterThan(before));
      s.dispose();
      final after = api.calls.length;
      async.elapse(const Duration(seconds: 3));
      expect(api.calls.length, after);
    });
  });

  test('it is done when the reply finishes, with what was found', () async {
    await study.start();
    backend.emit(const BusyChanged('run-new', busy: true));
    backend.emit(const MessageStarted('run-new'));
    await pump();
    api.stored = [sampleTemplate('a'), sampleTemplate('b')];
    backend.emit(const MessageCompleted('run-new', content: 'Done.'));
    backend.emit(const BusyChanged('run-new', busy: false));
    await pump();
    await pump();
    expect(study.value.phase, StudyPhase.done);
    expect(study.value.proposedTemplates, 2);
    expect(study.value.found, isTrue);
  });

  test(
    'finished with nothing proposed says so rather than offering a review',
    () async {
      await study.start();
      backend.emit(const MessageStarted('run-new'));
      await pump();
      backend.emit(const MessageCompleted('run-new', content: 'Nothing.'));
      backend.emit(const BusyChanged('run-new', busy: false));
      await pump();
      await pump();
      expect(study.value.phase, StudyPhase.done);
      expect(study.value.found, isFalse);
    },
  );

  test('a failed turn is a failure with the gateway\'s words', () async {
    await study.start();
    backend.emit(const MessageStarted('run-new'));
    await pump();
    backend.emit(const TurnFailed('run-new', 'The model is not available'));
    await pump();
    await pump();
    expect(study.value.phase, StudyPhase.failed);
    expect(study.value.message, contains('model'));
  });

  test('start twice does not make a second chat', () async {
    await study.start();
    await study.start();
    expect(backend.calls.where((c) => c == 'create'), hasLength(1));
  });
}
