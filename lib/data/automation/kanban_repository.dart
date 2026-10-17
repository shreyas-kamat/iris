/// The Kanban plugin: the board, one task, a new task, a move.
library;

import '../../core/failure.dart';
import '../../core/result.dart';
import '../net/api_client.dart';
import 'kanban_models.dart';

abstract interface class KanbanRepository {
  Future<Result<KanbanBoard>> board();
  Future<Result<KanbanTaskDetail>> task(String id);

  /// Creates a task and returns it, or null when the server did not echo it.
  Future<Result<KanbanTask?>> create(TaskDraft draft);

  /// Moves a task to [status] (a column id).
  Future<Result<void>> move(String id, String status);
}

final class DashboardKanbanRepository implements KanbanRepository {
  DashboardKanbanRepository(this._client);

  final ApiClient _client;

  static const _base = '/api/plugins/kanban';

  @override
  Future<Result<KanbanBoard>> board() async =>
      (await _client.get('$_base/board')).map(KanbanBoard.fromJson);

  @override
  Future<Result<KanbanTaskDetail>> task(String id) async {
    final result = await _client.get('$_base/tasks/${Uri.encodeComponent(id)}');
    return result.flatMap((body) {
      try {
        return Ok(KanbanTaskDetail.fromJson(body));
      } on FormatException catch (e) {
        return Err(IrisFailure.malformed(message: e.message));
      }
    });
  }

  @override
  Future<Result<KanbanTask?>> create(TaskDraft draft) async =>
      (await _client.post('$_base/tasks', body: draft.toBody())).map(
        (body) => KanbanTask.fromJsonOrNull(body['task']),
      );

  @override
  Future<Result<void>> move(String id, String status) async =>
      (await _client.patch(
        '$_base/tasks/${Uri.encodeComponent(id)}',
        body: {'status': status},
      )).map((_) {});
}
