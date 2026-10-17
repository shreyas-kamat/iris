/// Scripted repositories, so the tabs and forms are tested without HTTP.
library;

import 'dart:async';

import 'package:iris/core/failure.dart';
import 'package:iris/core/result.dart';
import 'package:iris/data/automation/cron_models.dart';
import 'package:iris/data/automation/cron_repository.dart';
import 'package:iris/data/automation/kanban_models.dart';
import 'package:iris/data/automation/kanban_repository.dart';
import 'package:iris/data/automation/profile_repository.dart';
import 'package:iris/data/chat/chat_models.dart';

CronJob fakeJob(
  String id, {
  String? name,
  String? prompt,
  String schedule = '0 7 * * *',
  String? display,
  bool enabled = true,
  CronState state = CronState.active,
  DateTime? nextRun,
  DateTime? lastRun,
  String? lastError,
  String? model,
  String? deliver,
}) => CronJob(
  id: id,
  name: name,
  prompt: prompt,
  schedule: schedule,
  scheduleDisplay: display,
  enabled: enabled,
  state: state,
  nextRun: nextRun,
  lastRun: lastRun,
  lastError: lastError,
  model: model,
  deliver: deliver,
);

KanbanTask fakeTask(
  String id, {
  String? title,
  String status = 'todo',
  String? assignee,
  int? priority,
  String? summary,
  KanbanProgress? progress,
  DateTime? startedAt,
  String? blockKind,
  int comments = 0,
  int warnings = 0,
  String? sessionId,
}) => KanbanTask(
  id: id,
  title: title ?? 'Task $id',
  status: status,
  assignee: assignee,
  priority: priority,
  latestSummary: summary,
  progress: progress,
  startedAt: startedAt,
  blockKind: blockKind,
  commentCount: comments,
  warningCount: warnings,
  sessionId: sessionId,
);

final class FakeCronRepository implements CronRepository {
  Result<List<CronJob>> jobsResult = const Ok([]);
  Result<List<ConversationSummary>> runsResult = const Ok([]);
  Result<List<DeliveryTarget>> targetsResult = const Ok([]);
  Result<CronJob>? writeResult;
  Result<void> voidResult = const Ok(null);

  /// When set, `setEnabled` waits for it, so a test can look at the screen
  /// between the tap and the server's answer.
  Completer<void>? setEnabledGate;

  /// `jobs`, `setEnabled <id> <bool>`, `trigger <id>`, `delete <id>`,
  /// `create`, `update <id>`, `runs <id>`, `targets`.
  final List<String> calls = [];
  final List<JobDraft> drafts = [];

  Result<CronJob> get _write =>
      writeResult ??
      Ok(
        CronJob(
          id: 'new',
          schedule: '30m',
          enabled: true,
          state: CronState.active,
        ),
      );

  @override
  Future<Result<List<CronJob>>> jobs() async {
    calls.add('jobs');
    return jobsResult;
  }

  @override
  Future<Result<CronJob>> job(String id) async {
    calls.add('job $id');
    return _write;
  }

  @override
  Future<Result<List<ConversationSummary>>> runs(
    String id, {
    int limit = 20,
  }) async {
    calls.add('runs $id');
    return runsResult;
  }

  @override
  Future<Result<List<DeliveryTarget>>> deliveryTargets() async {
    calls.add('targets');
    return targetsResult;
  }

  @override
  Future<Result<CronJob>> create(JobDraft draft) async {
    calls.add('create');
    drafts.add(draft);
    return _write;
  }

  @override
  Future<Result<CronJob>> update(String id, JobDraft draft) async {
    calls.add('update $id');
    drafts.add(draft);
    return _write;
  }

  @override
  Future<Result<CronJob>> setEnabled(
    String id, {
    required bool enabled,
  }) async {
    calls.add('setEnabled $id $enabled');
    await setEnabledGate?.future;
    return _write;
  }

  @override
  Future<Result<void>> trigger(String id) async {
    calls.add('trigger $id');
    return voidResult;
  }

  @override
  Future<Result<void>> delete(String id) async {
    calls.add('delete $id');
    return voidResult;
  }
}

final class FakeKanbanRepository implements KanbanRepository {
  Result<KanbanBoard> boardResult = const Ok(KanbanBoard(columns: []));
  Result<KanbanTaskDetail>? detailResult;
  Result<KanbanTask?> createResult = const Ok(null);
  Result<void> moveResult = const Ok(null);

  /// `board`, `task <id>`, `create`, `move <id> <status>`.
  final List<String> calls = [];
  final List<TaskDraft> drafts = [];

  @override
  Future<Result<KanbanBoard>> board() async {
    calls.add('board');
    return boardResult;
  }

  @override
  Future<Result<KanbanTaskDetail>> task(String id) async {
    calls.add('task $id');
    return detailResult ??
        Err(const IrisFailure(FailureKind.notFound, message: 'no detail'));
  }

  @override
  Future<Result<KanbanTask?>> create(TaskDraft draft) async {
    calls.add('create');
    drafts.add(draft);
    return createResult;
  }

  @override
  Future<Result<void>> move(String id, String status) async {
    calls.add('move $id $status');
    return moveResult;
  }
}

final class FakeProfileRepository implements ProfileRepository {
  Result<void> createResult = const Ok(null);
  Result<void> renameResult = const Ok(null);
  Result<String> soulResult = const Ok('');
  Result<void> setSoulResult = const Ok(null);
  Result<void> deleteResult = const Ok(null);

  /// `create <name>`, `rename <old> <new>`, `soul <name>`,
  /// `setSoul <name>`, `delete <name>`.
  final List<String> calls = [];
  final List<ProfileDraft> drafts = [];
  final Map<String, String> writtenSouls = {};

  @override
  Future<Result<void>> create(ProfileDraft draft) async {
    calls.add('create ${draft.name}');
    drafts.add(draft);
    return createResult;
  }

  @override
  Future<Result<void>> rename(String name, String newName) async {
    calls.add('rename $name $newName');
    return renameResult;
  }

  @override
  Future<Result<String>> soul(String name) async {
    calls.add('soul $name');
    return soulResult;
  }

  @override
  Future<Result<void>> setSoul(String name, String content) async {
    calls.add('setSoul $name');
    writtenSouls[name] = content;
    return setSoulResult;
  }

  @override
  Future<Result<void>> delete(String name) async {
    calls.add('delete $name');
    return deleteResult;
  }
}
