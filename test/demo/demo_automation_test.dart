import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/data/automation/kanban_models.dart';
import 'package:iris/data/automation/profile_repository.dart';
import 'package:iris/demo/demo_automation.dart';
import 'package:iris/demo/demo_world.dart';

void main() {
  late DemoWorld world;
  late DemoAutomation demo;
  final now = DateTime(2026, 10, 17, 12);

  setUp(() {
    world = DemoWorld(clock: () => now);
    demo = DemoAutomation(world, clock: () => now);
    addTearDown(world.dispose);
  });

  group('jobs', () {
    test('four jobs: active, failed, active, paused', () async {
      final jobs = (await demo.cron.jobs()).valueOrNull!;
      expect(jobs, hasLength(4));
      expect(jobs.where((j) => j.lastError != null), hasLength(1));
      expect(jobs.where((j) => !j.enabled), hasLength(1));
      expect(jobs.every((j) => j.title.isNotEmpty), isTrue);
    });

    test('pause and resume change the job', () async {
      final id = (await demo.cron.jobs()).valueOrNull!.first.id;
      await demo.cron.setEnabled(id, enabled: false);
      expect(
        (await demo.cron.jobs()).valueOrNull!
            .firstWhere((j) => j.id == id)
            .enabled,
        isFalse,
      );
    });

    test('create, edit and delete', () async {
      final created = (await demo.cron.create(
        const JobDraft(schedule: 'every 2h', prompt: 'Check', name: 'Check'),
      )).valueOrNull!;
      expect(
        (await demo.cron.jobs()).valueOrNull!.map((j) => j.id),
        contains(created.id),
      );
      await demo.cron.update(
        created.id,
        const JobDraft(schedule: '30m', prompt: 'Check again', name: 'Check'),
      );
      expect((await demo.cron.job(created.id)).valueOrNull!.schedule, '30m');
      await demo.cron.delete(created.id);
      expect(
        (await demo.cron.jobs()).valueOrNull!.map((j) => j.id),
        isNot(contains(created.id)),
      );
    });

    test('an unparseable schedule is refused like the server would', () async {
      final result = await demo.cron.create(
        const JobDraft(schedule: 'every blursday', prompt: 'x'),
      );
      expect(result.failureOrNull?.message, contains("Couldn't parse"));
    });

    test('running a job adds a past run that opens', () async {
      final id = (await demo.cron.jobs()).valueOrNull!.first.id;
      await demo.cron.trigger(id);
      final runs = (await demo.cron.runs(id)).valueOrNull!;
      expect(runs, hasLength(1));
    });
  });

  group('tasks', () {
    test('every column is present and Blocked has each kind', () async {
      final board = (await demo.kanban.board()).valueOrNull!;
      expect(board.columns.map((c) => c.id), [
        'triage',
        'todo',
        'ready',
        'running',
        'blocked',
        'review',
        'done',
      ]);
      final kinds = board
          .column('blocked')!
          .tasks
          .map((t) => t.blockKind)
          .toSet();
      expect(kinds, {'dependency', 'needs_input', 'capability', 'transient'});
      expect(
        board.column('running')!.tasks.every((t) => t.startedAt != null),
        isTrue,
      );
    });

    test(
      'moving and creating change the board; locked columns are refused',
      () async {
        final todo = (await demo.kanban.board()).valueOrNull!
            .column('todo')!
            .tasks
            .first;
        await demo.kanban.move(todo.id, 'done');
        expect(
          (await demo.kanban.board()).valueOrNull!.task(todo.id)!.status,
          'done',
        );
        final locked = await demo.kanban.move(todo.id, 'running');
        expect(locked.isErr, isTrue);
        final created = (await demo.kanban.create(
          const TaskDraft(title: 'New one', status: 'todo'),
        )).valueOrNull!;
        expect(
          (await demo.kanban.board()).valueOrNull!.task(created.id),
          isNotNull,
        );
      },
    );

    test('a task detail has a parent and subtasks', () async {
      final detail = (await demo.kanban.task('t_26')).valueOrNull!;
      expect(detail.parents, isNotEmpty);
      expect(detail.children, isNotEmpty);
    });
  });

  group('profiles', () {
    test('three profiles to start', () {
      expect(world.profiles.map((p) => p.name), [
        'default',
        'homelab',
        'research',
      ]);
    });

    test('create, rename, edit the SOUL and delete', () async {
      await demo.profiles.create(
        const ProfileDraft(name: 'notes', soul: '# Notes'),
      );
      expect(world.profiles.map((p) => p.name), contains('notes'));
      expect((await demo.profiles.soul('notes')).valueOrNull, '# Notes');
      await demo.profiles.rename('notes', 'notebook');
      expect(world.profiles.map((p) => p.name), contains('notebook'));
      await demo.profiles.setSoul('notebook', '# Book');
      expect((await demo.profiles.soul('notebook')).valueOrNull, '# Book');
      await demo.profiles.delete('notebook');
      expect(world.profiles.map((p) => p.name), isNot(contains('notebook')));
    });

    test('the default profile cannot be deleted', () async {
      final result = await demo.profiles.delete('default');
      expect(result.failureOrNull?.message, contains('cannot be deleted'));
    });
  });
}
