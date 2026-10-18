/// The Scheduled, Tasks and Profiles tools in the demo: real-looking data held
/// in memory, so a reviewer can use every screen without a server.
library;

import '../core/failure.dart';
import '../core/result.dart';
import '../data/automation/cron_models.dart';
import '../data/automation/cron_repository.dart';
import '../data/automation/kanban_models.dart';
import '../data/automation/kanban_repository.dart';
import '../data/automation/profile_repository.dart';
import '../data/chat/chat_models.dart';
import 'demo_world.dart';

final class DemoAutomation {
  DemoAutomation(this._world, {DateTime Function() clock = DateTime.now})
    : _clock = clock {
    final now = clock();
    _jobs.addAll([
      CronJob(
        id: 'job-1',
        name: 'Morning inbox digest',
        prompt: 'Summarise what needs a reply from overnight.',
        schedule: '0 7 * * *',
        scheduleDisplay: 'every day 7am',
        enabled: true,
        state: CronState.active,
        nextRun: now.add(const Duration(hours: 9, minutes: 12)),
        model: 'claude-sonnet-5-5',
      ),
      CronJob(
        id: 'job-2',
        name: 'Nightly backup to cold storage',
        prompt:
            'Back up /srv/data to the s3-cold bucket.\nVerify the checksum.',
        schedule: '0 2 * * *',
        enabled: true,
        state: CronState.active,
        lastRun: now.subtract(const Duration(hours: 2)),
        nextRun: now.add(const Duration(hours: 21, minutes: 40)),
        lastError:
            'backup target returned 502 Bad Gateway (s3-cold, 3 retries)',
        deliver: 'telegram-ops',
      ),
      CronJob(
        id: 'job-3',
        prompt: 'Audit dependencies for known advisories.',
        schedule: '0 9 * * 1',
        scheduleDisplay: 'every monday 9am',
        enabled: true,
        state: CronState.active,
        nextRun: now.add(const Duration(days: 3, hours: 4)),
      ),
      CronJob(
        id: 'job-4',
        name: 'Sync Linear → Tasks',
        prompt: 'Mirror new Linear issues into the task board.',
        schedule: '*/15 * * * *',
        enabled: false,
        state: CronState.paused,
      ),
    ]);
    _tasks.addAll(_seedTasks(now));
    _comments['t_26'] = [
      KanbanComment(
        author: 'you',
        body: 'Hold off until the 14:00 deploy is out.',
        at: now.subtract(const Duration(hours: 2)),
      ),
      KanbanComment(
        author: 'homelab',
        body: 'Deploy is finished, starting the rotation now.',
        at: now.subtract(const Duration(hours: 1)),
      ),
    ];
  }

  final DemoWorld _world;
  final DateTime Function() _clock;
  final List<CronJob> _jobs = [];
  final Map<String, List<ConversationSummary>> _runs = {};
  final List<KanbanTask> _tasks = [];
  final Map<String, List<KanbanComment>> _comments = {};
  var _jobCounter = 4;
  var _taskCounter = 40;

  late final CronRepository cron = _DemoCron(this);
  late final KanbanRepository kanban = _DemoKanban(this);
  late final ProfileRepository profiles = _DemoProfiles(_world);

  static const _columns = [
    'triage',
    'todo',
    'ready',
    'running',
    'blocked',
    'review',
    'done',
  ];

  static List<KanbanTask> _seedTasks(DateTime now) => [
    KanbanTask(id: 't_29', title: 'Flaky iOS UI tests on CI', status: 'triage'),
    KanbanTask(
      id: 't_27',
      title: 'Draft Q3 roadmap summary for the board',
      status: 'todo',
      priority: 2,
    ),
    KanbanTask(id: 't_24', title: 'Rotate gateway API keys', status: 'todo'),
    KanbanTask(
      id: 't_33',
      title: 'Write passkey migration notes',
      status: 'ready',
      assignee: 'homelab',
    ),
    KanbanTask(
      id: 't_30',
      title: 'Investigate worker heartbeat gaps overnight',
      status: 'running',
      assignee: 'homelab',
      priority: 2,
      latestSummary: 'Pulled the heartbeat logs between 01:00 and 05:00.',
      startedAt: now.subtract(const Duration(minutes: 4)),
      progress: const KanbanProgress(2, 5),
      commentCount: 1,
    ),
    KanbanTask(
      id: 't_28',
      title: 'Refactor billing to usage-based pricing',
      status: 'running',
      assignee: 'research',
      startedAt: now.subtract(const Duration(minutes: 11)),
    ),
    KanbanTask(
      id: 't_31',
      title: 'Nightly backup failing with 502 from gateway',
      status: 'blocked',
      blockKind: 'needs_input',
      latestSummary: 'Needs a decision: retry, or move the job to 04:30.',
    ),
    KanbanTask(
      id: 't_35',
      title: 'Update billing-worker',
      status: 'blocked',
      blockKind: 'dependency',
    ),
    KanbanTask(
      id: 't_36',
      title: 'Update webhook-relay',
      status: 'blocked',
      blockKind: 'capability',
    ),
    KanbanTask(
      id: 't_37',
      title: 'Sync the model catalogue',
      status: 'blocked',
      blockKind: 'transient',
      warningCount: 1,
    ),
    KanbanTask(
      id: 't_26',
      title: 'Rotate gateway API keys',
      status: 'review',
      assignee: 'homelab',
      priority: 2,
      latestSummary: 'Rotated keys and restarted all three services.',
      commentCount: 2,
    ),
    KanbanTask(
      id: 't_22',
      title: 'Local embeddings vs API cost, report',
      status: 'done',
    ),
  ];

  KanbanBoard _board() => KanbanBoard(
    columns: [
      for (final id in _columns)
        KanbanColumn(
          id: id,
          tasks: [
            for (final task in _tasks)
              if (task.status == id) task,
          ],
        ),
    ],
  );

  static final _knownSchedule = RegExp(
    r'^(\d+[smhd]|every\s+.+|([\d*/,-]+\s+){4}[\d*/,\-A-Za-z]+|\d{4}-\d{2}-\d{2}.*)$',
    caseSensitive: false,
  );

  static IrisFailure? _scheduleProblem(String schedule) {
    final text = schedule.trim();
    final knownWords = RegExp(
      r'^every\s+((\d+\s*[smhdw]|(\d+\s*)?(second|minute|hour|day|week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?)(\s+.*)?)$',
      caseSensitive: false,
    );
    final ok =
        _knownSchedule.hasMatch(text) &&
        (!text.toLowerCase().startsWith('every') || knownWords.hasMatch(text));
    return ok
        ? null
        : IrisFailure(
            FailureKind.rejected,
            statusCode: 422,
            message: "Couldn't parse '$text'",
          );
  }
}

final class _DemoCron implements CronRepository {
  _DemoCron(this._demo);
  final DemoAutomation _demo;

  List<CronJob> get _jobs => _demo._jobs;

  int _index(String id) => _jobs.indexWhere((j) => j.id == id);

  @override
  Future<Result<List<CronJob>>> jobs() async => Ok(List.of(_jobs));

  @override
  Future<Result<CronJob>> job(String id) async => _index(id) < 0
      ? const Err(IrisFailure(FailureKind.notFound))
      : Ok(_jobs[_index(id)]);

  @override
  Future<Result<List<ConversationSummary>>> runs(
    String id, {
    int limit = 20,
  }) async => Ok(List.of(_demo._runs[id] ?? const []));

  @override
  Future<Result<List<DeliveryTarget>>> deliveryTargets() async => const Ok([
    DeliveryTarget(id: 'telegram-ops', name: 'telegram-ops'),
    DeliveryTarget(id: 'email-me', name: 'email'),
  ]);

  @override
  Future<Result<CronJob>> create(JobDraft draft) async {
    final problem = DemoAutomation._scheduleProblem(draft.schedule);
    if (problem != null) return Err(problem);
    final job = CronJob(
      id: 'job-${++_demo._jobCounter}',
      name: draft.name?.trim().isEmpty ?? true ? null : draft.name!.trim(),
      prompt: draft.prompt.trim(),
      schedule: draft.schedule.trim(),
      enabled: true,
      state: CronState.active,
      nextRun: _demo._clock().add(const Duration(hours: 1)),
      model: draft.model,
      deliver: draft.deliver,
    );
    _jobs.add(job);
    return Ok(job);
  }

  @override
  Future<Result<CronJob>> update(String id, JobDraft draft) async {
    final at = _index(id);
    if (at < 0) return const Err(IrisFailure(FailureKind.notFound));
    final problem = DemoAutomation._scheduleProblem(draft.schedule);
    if (problem != null) return Err(problem);
    final old = _jobs[at];
    return Ok(
      _jobs[at] = CronJob(
        id: id,
        name: draft.name?.trim().isEmpty ?? true ? null : draft.name!.trim(),
        prompt: draft.prompt.trim(),
        schedule: draft.schedule.trim(),
        enabled: old.enabled,
        state: old.state,
        nextRun: old.nextRun,
        lastRun: old.lastRun,
        lastError: old.lastError,
        model: draft.model,
        deliver: draft.deliver,
      ),
    );
  }

  @override
  Future<Result<CronJob>> setEnabled(String id, {required bool enabled}) async {
    final at = _index(id);
    if (at < 0) return const Err(IrisFailure(FailureKind.notFound));
    return Ok(_jobs[at] = _jobs[at].copyWith(enabled: enabled));
  }

  @override
  Future<Result<void>> trigger(String id) async {
    final at = _index(id);
    if (at < 0) return const Err(IrisFailure(FailureKind.notFound));
    final created = _demo._world.create('default');
    final now = _demo._clock();
    (_demo._runs[id] ??= []).insert(
      0,
      ConversationSummary(
        id: created.storedId,
        title: _jobs[at].title,
        startedAt: now,
        source: 'cron',
      ),
    );
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    _jobs.removeWhere((j) => j.id == id);
    _demo._runs.remove(id);
    return const Ok(null);
  }
}

final class _DemoKanban implements KanbanRepository {
  _DemoKanban(this._demo);
  final DemoAutomation _demo;

  @override
  Future<Result<KanbanBoard>> board() async => Ok(_demo._board());

  @override
  Future<Result<KanbanTaskDetail>> task(String id) async {
    final task = _demo._tasks.where((t) => t.id == id).firstOrNull;
    if (task == null) return const Err(IrisFailure(FailureKind.notFound));
    final now = _demo._clock();
    return Ok(
      KanbanTaskDetail(
        task: task,
        result: id == 't_26'
            ? 'New keys are live in vault/gateway. Old keys were revoked at 14:20.'
            : null,
        lastFailure: id == 't_26'
            ? 'webhook-relay: health check timed out after 30s'
            : null,
        comments: _demo._comments[id] ?? const [],
        runs: id == 't_26'
            ? [
                KanbanRun(
                  startedAt: now.subtract(const Duration(hours: 1)),
                  endedAt: now.subtract(const Duration(minutes: 40)),
                  outcome: 'completed',
                ),
                KanbanRun(
                  startedAt: now.subtract(const Duration(hours: 2)),
                  endedAt: now.subtract(const Duration(hours: 1, minutes: 50)),
                  outcome: 'failed',
                ),
              ]
            : const [],
        parents: id == 't_26'
            ? const [KanbanLink(id: 't_20', title: 'Q4 security hygiene')]
            : const [],
        children: id == 't_26'
            ? const [
                KanbanLink(
                  id: 't_34',
                  title: 'Update api-edge',
                  status: 'done',
                ),
                KanbanLink(
                  id: 't_35',
                  title: 'Update billing-worker',
                  status: 'blocked',
                ),
                KanbanLink(
                  id: 't_36',
                  title: 'Update webhook-relay',
                  status: 'blocked',
                ),
              ]
            : const [],
      ),
    );
  }

  @override
  Future<Result<KanbanTask?>> create(TaskDraft draft) async {
    final task = KanbanTask(
      id: 't_${++_demo._taskCounter}',
      title: draft.title.trim(),
      status: draft.status,
      body: draft.body,
      assignee: draft.assignee,
      priority: draft.priority,
    );
    _demo._tasks.add(task);
    return Ok(task);
  }

  @override
  Future<Result<void>> move(String id, String status) async {
    if (KanbanColumns.isSystemSet(status)) {
      return const Err(
        IrisFailure(FailureKind.rejected, message: 'Hermes moves tasks there'),
      );
    }
    final at = _demo._tasks.indexWhere((t) => t.id == id);
    if (at < 0) return const Err(IrisFailure(FailureKind.notFound));
    _demo._tasks[at] = _demo._tasks[at].copyWith(status: status);
    return const Ok(null);
  }
}

final class _DemoProfiles implements ProfileRepository {
  _DemoProfiles(this._world);
  final DemoWorld _world;

  @override
  Future<Result<void>> create(ProfileDraft draft) async {
    if (_world.profiles.any((p) => p.name == draft.name)) {
      return const Err(
        IrisFailure(
          FailureKind.rejected,
          message: 'That profile already exists',
        ),
      );
    }
    _world.addProfile(
      draft.name,
      copyFrom: draft.start == ProfileStart.blank ? null : draft.source,
      soul: draft.soul,
    );
    return const Ok(null);
  }

  @override
  Future<Result<void>> rename(String name, String newName) async {
    _world.renameProfile(name, newName);
    return const Ok(null);
  }

  @override
  Future<Result<String>> soul(String name) async => Ok(_world.soulOf(name));

  @override
  Future<Result<void>> setSoul(String name, String content) async {
    _world.setSoul(name, content);
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String name) async {
    if (name == 'default') {
      return const Err(
        IrisFailure(
          FailureKind.rejected,
          message: 'The default profile cannot be deleted.',
        ),
      );
    }
    _world.removeProfile(name);
    return const Ok(null);
  }
}
