/// Conversations on one dashboard: listing, reading, sending, answering.
///
/// [ChatBackend] is the seam the chat screen depends on, so the screen is
/// tested against a scripted fake. [DashboardChat] is the real one: the live
/// socket for anything live, and REST for stored history — the split Hermes
/// Desktop and Conduit both use, because a long transcript sent over the
/// socket would hold up every event queued behind it.
library;

import 'dart:async';

import '../../core/failure.dart';
import '../../core/result.dart';
import '../rpc/dashboard_session.dart';
import '../rpc/rpc_frame.dart';
import 'chat_event.dart';
import 'chat_models.dart';
import 'history_parser.dart';

/// A conversation Iris just created.
final class NewConversation {
  const NewConversation({required this.runtimeId, required this.storedId});

  /// What live calls and events use.
  final String runtimeId;

  /// What history and the conversation list use.
  final String storedId;
}

/// A stored conversation, attached to the live socket.
final class ResumedConversation {
  const ResumedConversation({
    required this.runtimeId,
    this.running = false,
    this.pending = const [],
  });

  final String runtimeId;

  /// A turn was already in progress — started elsewhere, or before a
  /// reconnect.
  final bool running;

  /// Approvals and questions still waiting for an answer.
  final List<ChatEvent> pending;
}

abstract interface class ChatBackend {
  /// Events and decisions for every live conversation; callers keep the ones
  /// for their own session.
  Stream<ChatEvent> get events;

  Future<Result<List<ConversationSummary>>> conversations();

  /// The newest page of [storedId]'s transcript, oldest first.
  Future<Result<List<TranscriptItem>>> history(String storedId);

  Future<Result<ResumedConversation>> resume(String storedId);

  Future<Result<NewConversation>> create();

  Future<Result<void>> submit(String runtimeId, String text);

  Future<Result<void>> interrupt(String runtimeId);

  Future<Result<void>> answerApproval(ApprovalRequest request, String choice);

  Future<Result<void>> answerClarify(
    ClarifyRequest request,
    ClarifyQuestion question,
    String answer,
  );
}

final class DashboardChat implements ChatBackend {
  DashboardChat(this._session) {
    _eventSubscription = _session.events.listen((event) {
      if (ChatEvent.fromEvent(event) case final parsed?) _events.add(parsed);
    });
    _requestSubscription = _session.serverRequests.listen((request) {
      if (ChatEvent.fromServerRequest(request) case final parsed?) {
        _events.add(parsed);
      }
    });
  }

  /// Rows per history page, as Hermes Desktop asks for.
  static const historyPage = 120;

  /// Long enough for a busy gateway to accept a turn. The reply itself
  /// streams as events, not as this call's result.
  static const submitTimeout = Duration(seconds: 180);

  final DashboardSession _session;
  final _events = StreamController<ChatEvent>.broadcast();
  late final StreamSubscription<RpcEvent> _eventSubscription;
  late final StreamSubscription<RpcServerRequest> _requestSubscription;

  @override
  Stream<ChatEvent> get events => _events.stream;

  @override
  Future<Result<List<ConversationSummary>>> conversations() async =>
      (await _session.call('session.list')).map(HistoryParser.conversations);

  @override
  Future<Result<List<TranscriptItem>>> history(String storedId) async =>
      (await _session.connection.client.get(
        '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
        query: {
          'limit': historyPage,
          'offset': 0,
          'order': 'latest',
          'include_compacted': 'true',
        },
      )).map(HistoryParser.transcript);

  @override
  Future<Result<ResumedConversation>> resume(String storedId) async {
    final result = await _session.call(
      'session.resume',
      params: {
        'session_id': storedId,
        'cols': 96,
        'source': 'desktop',
        'omit_messages': true,
      },
    );
    return result.map((json) {
      final pending = <ChatEvent>[];
      // Decisions asked before Iris attached are re-announced here, under
      // their original server request ids.
      for (final entry in json['open_requests'].list) {
        final method = entry['method'].stringOrNull;
        final id = entry['id'].stringOrNull;
        if (method == null || id == null) continue;
        final request = RpcServerRequest(
          id: id,
          method: method,
          params: entry['params'],
        );
        if (ChatEvent.fromServerRequest(request) case final parsed?) {
          pending.add(parsed);
        }
      }
      return ResumedConversation(
        runtimeId: HistoryParser.firstText(json, const ['session_id']) ?? storedId,
        running: json['running'].boolOrNull ?? json['info']['running'].boolean(),
        pending: pending,
      );
    });
  }

  @override
  Future<Result<NewConversation>> create() async {
    final result = await _session.call(
      'session.create',
      params: const {'cols': 96, 'source': 'desktop'},
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final json):
        final runtimeId = HistoryParser.firstText(json, const ['session_id']);
        if (runtimeId == null) {
          return const Err(
            IrisFailure.malformed(
              message: 'The dashboard did not return a session id.',
              endpoint: 'session.create',
            ),
          );
        }
        return Ok(
          NewConversation(
            runtimeId: runtimeId,
            storedId:
                HistoryParser.firstText(json, const ['stored_session_id']) ??
                runtimeId,
          ),
        );
    }
  }

  @override
  Future<Result<void>> submit(String runtimeId, String text) async =>
      (await _session.call(
        'prompt.submit',
        params: {'session_id': runtimeId, 'text': text},
        timeout: submitTimeout,
      )).map((_) {});

  @override
  Future<Result<void>> interrupt(String runtimeId) async => (await _session
      .call('session.interrupt', params: {'session_id': runtimeId})).map((_) {});

  @override
  Future<Result<void>> answerApproval(
    ApprovalRequest request,
    String choice,
  ) async => (await _session.call(
    'approval.respond',
    params: {
      'choice': choice,
      'session_id': request.sessionId,
      'request_id': ?request.queueId,
    },
  )).map((_) {});

  @override
  Future<Result<void>> answerClarify(
    ClarifyRequest request,
    ClarifyQuestion question,
    String answer,
  ) async {
    if (!request.isServerRequest) {
      return (await _session.call(
        'clarify.respond',
        params: {
          'request_id': request.requestId,
          'answer': answer,
          if (!question.synthetic) 'question_id': question.id,
        },
      )).map((_) {});
    }
    if (!question.synthetic) {
      // One question of a batch. Each is locked on its own; the last lock
      // resolves the whole request.
      return (await _session.call(
        'clarify.lock',
        params: {
          'request_id': request.requestId,
          'question_id': question.id,
          'answer': answer,
        },
      )).map((_) {});
    }
    // A single question is answered with the response frame itself.
    return _session.replyToServerRequest(request.requestId, {'answer': answer})
        ? const Ok(null)
        : const Err(IrisFailure.offline(message: 'Not connected to the dashboard.'));
  }

  Future<void> dispose() async {
    await _eventSubscription.cancel();
    await _requestSubscription.cancel();
    await _events.close();
  }
}
