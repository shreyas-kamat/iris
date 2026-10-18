/// The Kanban plugin's board: columns, task cards and one task's detail.
library;

import '../../core/json.dart';

abstract final class KanbanColumns {
  /// Hermes sets these; a person does not move a card into them.
  static const systemSet = {'running', 'review', 'scheduled'};

  /// The columns a new task can start in.
  static const creatable = ['triage', 'todo'];

  static bool isSystemSet(String id) => systemSet.contains(id);

  static const _labels = {
    'triage': 'Triage',
    'todo': 'To do',
    'ready': 'Ready',
    'running': 'Running',
    'blocked': 'Blocked',
    'review': 'Review',
    'done': 'Done',
    'scheduled': 'Scheduled',
  };

  /// The column's name for people. An unknown id is capitalised, not hidden.
  static String label(String id) {
    final known = _labels[id];
    if (known != null) return known;
    if (id.isEmpty) return id;
    final spaced = id.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

final class KanbanProgress {
  const KanbanProgress(this.done, this.total);
  final int done;
  final int total;
}

final class KanbanTask {
  const KanbanTask({
    required this.id,
    required this.title,
    required this.status,
    this.body,
    this.assignee,
    this.priority,
    this.latestSummary,
    this.commentCount = 0,
    this.warningCount = 0,
    this.progress,
    this.startedAt,
    this.blockKind,
    this.sessionId,
  });

  static KanbanTask? fromJsonOrNull(Json json) {
    final id = json['id'].stringOrNull;
    if (id == null || id.isEmpty) return null;
    final progress = json['progress'];
    final total = progress['total'].intOrNull;
    return KanbanTask(
      id: id,
      title: json['title'].string(id),
      status: json['status'].string(),
      body: _clean(json['body'].stringOrNull),
      assignee: _clean(json['assignee'].stringOrNull),
      priority: json['priority'].intOrNull,
      latestSummary: _clean(json['latest_summary'].stringOrNull),
      commentCount: json['comment_count'].integer(),
      warningCount: json['warnings']['count'].integer(),
      progress: total == null || total <= 0
          ? null
          : KanbanProgress(progress['done'].integer(), total),
      startedAt: json.any(['current_run_started_at', 'started_at']).dateTimeOrNull,
      blockKind: _clean(json['block_kind'].stringOrNull),
      // Task 0 records whether the wire carries a session link and under which
      // key; this reads the likeliest spellings and is null otherwise.
      sessionId: _clean(
        json.any(['session_id', 'stored_session_id']).stringOrNull,
      ),
    );
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final String id;
  final String title;

  /// The column id: `triage`, `todo`, `ready`, `running`, `blocked`, `review`,
  /// `done`, or something a newer server added.
  final String status;
  final String? body;
  final String? assignee;
  final int? priority;
  final String? latestSummary;
  final int commentCount;
  final int warningCount;
  final KanbanProgress? progress;
  final DateTime? startedAt;

  /// `dependency`, `needs_input`, `capability`, `transient`, or null. Only
  /// meaningful while [status] is `blocked`.
  final String? blockKind;
  final String? sessionId;

  bool get running => status == 'running';

  KanbanTask copyWith({String? status}) => KanbanTask(
    id: id,
    title: title,
    status: status ?? this.status,
    body: body,
    assignee: assignee,
    priority: priority,
    latestSummary: latestSummary,
    commentCount: commentCount,
    warningCount: warningCount,
    progress: progress,
    startedAt: startedAt,
    blockKind: blockKind,
    sessionId: sessionId,
  );
}

final class KanbanColumn {
  const KanbanColumn({required this.id, required this.tasks});

  final String id;
  final List<KanbanTask> tasks;
  String get label => KanbanColumns.label(id);
}

final class KanbanBoard {
  const KanbanBoard({required this.columns, this.assignees = const []});

  factory KanbanBoard.fromJson(Json json) => KanbanBoard(
    columns: [
      for (final column in json['columns'].list)
        if (column['name'].stringOrNull case final id?)
          KanbanColumn(
            id: id,
            tasks: [
              for (final task in column['tasks'].list)
                ?KanbanTask.fromJsonOrNull(task),
            ],
          ),
    ],
    assignees: [
      for (final name in json['assignees'].list)
        ?name.stringOrNull,
    ],
  );

  final List<KanbanColumn> columns;
  final List<String> assignees;

  KanbanColumn? column(String id) {
    for (final column in columns) {
      if (column.id == id) return column;
    }
    return null;
  }

  KanbanTask? task(String id) {
    for (final column in columns) {
      for (final task in column.tasks) {
        if (task.id == id) return task;
      }
    }
    return null;
  }

  /// The same board with [id] moved to [status], for an optimistic move.
  KanbanBoard moved(String id, String status) {
    final task = this.task(id);
    if (task == null) return this;
    final moved = task.copyWith(status: status);
    final next = [
      for (final column in columns)
        KanbanColumn(
          id: column.id,
          tasks: [
            for (final t in column.tasks)
              if (t.id != id) t,
            if (column.id == status) moved,
          ],
        ),
    ];
    return KanbanBoard(
      columns: next.any((c) => c.id == status)
          ? next
          : [...next, KanbanColumn(id: status, tasks: [moved])],
      assignees: assignees,
    );
  }
}

final class KanbanLink {
  const KanbanLink({required this.id, required this.title, this.status});
  final String id;
  final String title;
  final String? status;
}

final class KanbanComment {
  const KanbanComment({required this.author, required this.body, this.at});
  final String author;
  final String body;
  final DateTime? at;
}

final class KanbanRun {
  const KanbanRun({this.startedAt, this.endedAt, this.outcome});
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// `completed`, `failed`, or whatever the server calls it.
  final String? outcome;
}

final class KanbanTaskDetail {
  const KanbanTaskDetail({
    required this.task,
    this.result,
    this.lastFailure,
    this.comments = const [],
    this.runs = const [],
    this.parents = const [],
    this.children = const [],
  });

  factory KanbanTaskDetail.fromJson(Json json) {
    final task = KanbanTask.fromJsonOrNull(json['task']);
    if (task == null) {
      throw const FormatException('No task in the detail response');
    }
    final known = <String, KanbanLink>{
      for (final row in json['link_tasks'].list)
        ?row['id'].stringOrNull: KanbanLink(
          id: row['id'].string(),
          title: row['title'].string(row['id'].string()),
          status: row['status'].stringOrNull,
        ),
    };
    List<KanbanLink> links(Json ids) => [
      for (final id in ids.list)
        if (id.stringOrNull case final value?)
          known[value] ?? KanbanLink(id: value, title: value),
    ];
    return KanbanTaskDetail(
      task: task,
      result: KanbanTask._clean(json['task']['result'].stringOrNull),
      lastFailure: KanbanTask._clean(
        json['task']['last_failure_error'].stringOrNull,
      ),
      comments: [
        for (final row in json['comments'].list)
          KanbanComment(
            author: row['author'].string('unknown'),
            body: row['body'].string(),
            at: row['created_at'].dateTimeOrNull,
          ),
      ],
      runs: [
        for (final row in json['runs'].list)
          KanbanRun(
            startedAt: row['started_at'].dateTimeOrNull,
            endedAt: row['ended_at'].dateTimeOrNull,
            outcome: KanbanTask._clean(
              row.any(['outcome', 'status']).stringOrNull,
            ),
          ),
      ],
      parents: links(json['links']['parents']),
      children: links(json['links']['children']),
    );
  }

  final KanbanTask task;
  final String? result;
  final String? lastFailure;
  final List<KanbanComment> comments;
  final List<KanbanRun> runs;
  final List<KanbanLink> parents;
  final List<KanbanLink> children;
}

/// What the New task form sends.
final class TaskDraft {
  const TaskDraft({
    required this.title,
    this.body,
    this.status = 'triage',
    this.assignee,
    this.priority,
  });

  final String title;
  final String? body;

  /// `triage` or `todo`.
  final String status;
  final String? assignee;
  final int? priority;

  Map<String, Object?> toBody() => {
    'title': title.trim(),
    if (body != null && body!.trim().isNotEmpty) 'body': body!.trim(),
    'status': status,
    if (assignee != null && assignee!.isNotEmpty) 'assignee': assignee,
    if (priority != null) 'priority': priority,
  };
}
