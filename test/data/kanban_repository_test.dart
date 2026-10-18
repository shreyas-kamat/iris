import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/json.dart';
import 'package:iris/data/automation/kanban_models.dart';
import 'package:iris/data/automation/kanban_repository.dart';
import 'package:iris/data/net/server_config.dart';
import 'package:iris/data/net/server_connection.dart';

import '../support/fake_http.dart';

void main() {
  late FakeHttp http;
  setUp(() => http = FakeHttp());

  DashboardKanbanRepository repo() {
    final connection = ServerConnection.create(
      const ServerConfig(id: 's', baseUrl: 'https://h.example', label: 'S'),
      adapter: http,
    );
    addTearDown(connection.close);
    return DashboardKanbanRepository(connection.client);
  }

  final board = {
    'columns': [
      {
        'name': 'running',
        'tasks': [
          {
            'id': 't_30',
            'title': 'Investigate heartbeat gaps',
            'status': 'running',
            'assignee': 'homelab',
            'priority': 2,
            'started_at': 1760684400,
            'progress': {'done': 2, 'total': 5},
            'warnings': {'count': 1},
          },
        ],
      },
      {
        'name': 'blocked',
        'tasks': [
          {
            'id': 't_31',
            'title': 'Backup failing',
            'status': 'blocked',
            'block_kind': 'needs_input',
          },
        ],
      },
      {'name': 'sprinting', 'tasks': <Object>[]},
    ],
    'assignees': ['homelab'],
  };

  test('parses the board with an unknown column kept', () async {
    http.on('GET', '/api/plugins/kanban/board', (_) => FakeReply.json(board));
    final parsed = (await repo().board()).valueOrNull!;
    expect(parsed.columns.map((c) => c.id), ['running', 'blocked', 'sprinting']);
    expect(parsed.columns.last.label, 'Sprinting');
    final task = parsed.task('t_30')!;
    expect(task.priority, 2);
    expect(task.progress!.done, 2);
    expect(task.progress!.total, 5);
    expect(task.startedAt, isNotNull);
    expect(task.warningCount, 1);
    expect(parsed.task('t_31')!.blockKind, 'needs_input');
  });

  test('a task with no optional fields still parses', () {
    final task = KanbanTask.fromJsonOrNull(
      Json.of({'id': 't_1', 'title': 'x', 'status': 'todo'}),
    )!;
    expect(task.progress, isNull);
    expect(task.startedAt, isNull);
    expect(task.commentCount, 0);
    expect(task.sessionId, isNull);
  });

  test('progress with a zero total is dropped', () {
    final task = KanbanTask.fromJsonOrNull(Json.of({
      'id': 't_1',
      'title': 'x',
      'status': 'running',
      'progress': {'done': 0, 'total': 0},
    }))!;
    expect(task.progress, isNull);
  });

  test('system-set columns are locked', () {
    expect(KanbanColumns.isSystemSet('running'), isTrue);
    expect(KanbanColumns.isSystemSet('review'), isTrue);
    expect(KanbanColumns.isSystemSet('scheduled'), isTrue);
    expect(KanbanColumns.isSystemSet('todo'), isFalse);
    expect(KanbanColumns.label('todo'), 'To do');
  });

  test('moved takes a card out of one column and into another', () {
    final parsed = KanbanBoard.fromJson(Json.of(board));
    final next = parsed.moved('t_31', 'todo');
    expect(next.column('blocked')!.tasks, isEmpty);
    expect(next.column('todo')!.tasks.single.id, 't_31');
    expect(next.task('t_31')!.status, 'todo');
  });

  test('detail joins links to their titles and keeps unknown ones', () async {
    http.on('GET', '/api/plugins/kanban/tasks/t_26', (_) => FakeReply.json({
          'task': {
            'id': 't_26',
            'title': 'Rotate keys',
            'status': 'review',
            'result': 'Keys are live.',
            'last_failure_error': 'health check timed out',
          },
          'comments': [
            {'author': 'you', 'body': 'Hold off', 'created_at': 1760684400},
          ],
          'runs': [
            {'started_at': 1760684400, 'ended_at': 1760685400, 'outcome': 'completed'},
            {'started_at': 1760680000, 'status': 'failed'},
          ],
          'links': {
            'parents': ['t_20'],
            'children': ['t_34', 't_99'],
          },
          'link_tasks': [
            {'id': 't_20', 'title': 'Q4 hygiene', 'status': 'todo'},
            {'id': 't_34', 'title': 'Update api-edge', 'status': 'done'},
          ],
        }));
    final detail = (await repo().task('t_26')).valueOrNull!;
    expect(detail.result, 'Keys are live.');
    expect(detail.lastFailure, 'health check timed out');
    expect(detail.parents.single.title, 'Q4 hygiene');
    expect(detail.children.map((c) => c.title), ['Update api-edge', 't_99']);
    expect(detail.runs.map((r) => r.outcome), ['completed', 'failed']);
    expect(detail.comments.single.author, 'you');
  });

  test('a detail response with no task is malformed, not a crash', () async {
    http.on('GET', '/api/plugins/kanban/tasks/x', (_) => FakeReply.json({}));
    expect((await repo().task('x')).failureOrNull?.kind.name, 'malformed');
  });

  test('create posts the draft; move patches the status', () async {
    http.on('POST', '/api/plugins/kanban/tasks', (_) => FakeReply.json({
          'task': {'id': 't_40', 'title': 'New', 'status': 'triage'},
        }));
    http.on('PATCH', '/api/plugins/kanban/tasks/t_40', (_) => FakeReply.json({}));
    final r = repo();
    final created = (await r.create(
      const TaskDraft(title: ' New ', body: '', priority: 2),
    )).valueOrNull;
    expect(created!.id, 't_40');
    expect(http.requests.first.data, {
      'title': 'New',
      'status': 'triage',
      'priority': 2,
    });
    expect((await r.move('t_40', 'todo')).isOk, isTrue);
    expect(http.requests.last.data, {'status': 'todo'});
  });

  test('the board parameter is never sent', () async {
    http.on('GET', '/api/plugins/kanban/board', (_) => FakeReply.json(board));
    await repo().board();
    expect(http.requests.single.uri.queryParameters.containsKey('board'), isFalse);
  });
}
