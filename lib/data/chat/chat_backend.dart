/// Conversations on one dashboard: listing, reading, sending, answering.
///
/// [ChatBackend] is the seam the chat screen depends on, so the screen is
/// tested against a scripted fake. [DashboardChat] is the real one: the live
/// socket for anything live, and REST for stored history and lists — the split
/// Hermes Desktop and Conduit both use, because a long transcript sent over the
/// socket would hold up every event queued behind it.
library;

import 'dart:async';
import 'dart:math' as math;

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/result.dart';
import '../rpc/dashboard_session.dart';
import '../rpc/rpc_frame.dart';
import 'catalog_parser.dart';
import 'chat_event.dart';
import 'chat_models.dart';
import 'history_parser.dart';

/// Where a page of stored history starts, in the server's own terms.
final class HistoryCursor {
  const HistoryCursor({required this.offset, required this.fromNewest});

  /// Rows to skip.
  final int offset;

  /// Whether [offset] counts back from the newest row (a dashboard that
  /// honours `order=latest`) or forward from the oldest (Hermes 0.18.2).
  final bool fromNewest;
}

/// One page of stored history.
final class HistoryPage {
  const HistoryPage({required this.items, this.earlier});

  /// Oldest first.
  final List<TranscriptItem> items;

  /// Where the page before this one starts; null at the beginning.
  final HistoryCursor? earlier;
}

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
    this.model,
    this.provider,
  });

  final String runtimeId;

  /// A turn was already in progress — started elsewhere, or before a
  /// reconnect.
  final bool running;

  /// Approvals and questions still waiting for an answer.
  final List<ChatEvent> pending;

  /// The model the conversation runs on, when the gateway says.
  final String? model;
  final String? provider;
}

abstract interface class ChatBackend {
  /// Events and decisions for every live conversation; callers keep the ones
  /// for their own session.
  Stream<ChatEvent> get events;

  /// Fires each time the live link comes back after a drop. A runtime
  /// session belongs to the socket that created or resumed it, so an open
  /// conversation has to resume again or its events go nowhere.
  Stream<void> get reconnected;

  /// A page of this profile's conversations, newest first, from [offset].
  Future<Result<ConversationPage>> conversations(int offset);

  /// Every agent profile on the dashboard.
  Future<Result<List<AgentProfile>>> profiles();

  /// The newest page of [storedId]'s transcript, or the page before
  /// [before].
  Future<Result<HistoryPage>> history(String storedId, {HistoryCursor? before});

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

  /// The models the live session — or, without one, the profile — can use.
  Future<Result<ModelOptions>> modelOptions({String? runtimeId});

  /// Switches the live session's model. A switch Hermes wants confirmed
  /// changes nothing and says so; call again with [confirmed] once the
  /// person agrees.
  Future<Result<ModelSwitch>> switchModel(
    String runtimeId, {
    required String model,
    required String provider,
    required bool confirmed,
  });

  /// Every slash command the gateway knows.
  Future<Result<List<SlashCommand>>> commands();

  /// Runs [command] (with or without its leading slash) in the live session.
  Future<Result<SlashOutcome>> runSlash(String runtimeId, String command);
}

final class DashboardChat implements ChatBackend {
  DashboardChat(this._session, {this.profile = 'default'})
    : _live = _session.state.phase == LinkPhase.live,
      _everLive = _session.state.phase == LinkPhase.live {
    _linkSubscription = _session.states.listen(_onLink);
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

  /// Conversations per list page.
  static const conversationPage = 50;

  /// Long enough for a busy gateway to accept a turn. The reply itself
  /// streams as events, not as this call's result.
  static const submitTimeout = Duration(seconds: 180);

  /// The agent profile this backend reads and writes.
  final String profile;

  final DashboardSession _session;
  final _events = StreamController<ChatEvent>.broadcast();
  late final StreamSubscription<RpcEvent> _eventSubscription;
  late final StreamSubscription<RpcServerRequest> _requestSubscription;
  late final StreamSubscription<LinkState> _linkSubscription;
  final _reconnected = StreamController<void>.broadcast();
  bool _live;
  bool _everLive;

  @override
  Stream<ChatEvent> get events => _events.stream;

  @override
  Stream<void> get reconnected => _reconnected.stream;

  void _onLink(LinkState state) {
    final live = state.phase == LinkPhase.live;
    if (live && !_live && _everLive) _reconnected.add(null);
    if (live) _everLive = true;
    _live = live;
  }

  /// [values] plus this profile, for a route or call that belongs to it. The
  /// default profile is left implicit, as the dashboard expects; a named
  /// profile's sessions answer 404 without it.
  Map<String, Object?> _scoped(Map<String, Object?> values) =>
      profile == 'default' ? values : {...values, 'profile': profile};

  @override
  Future<Result<ConversationPage>> conversations(int offset) async =>
      (await _session.connection.client.get(
        '/api/profiles/sessions',
        // Always named, even for the default: without it the route merges
        // every profile's conversations.
        query: {
          'profile': profile,
          'limit': conversationPage,
          'offset': offset,
          'min_messages': 1,
          'archived': 'exclude',
          'order': 'recent',
        },
      )).map(CatalogParser.conversationPage);

  @override
  Future<Result<List<AgentProfile>>> profiles() async => (await _session
      .connection
      .client
      .get('/api/profiles')).map(CatalogParser.profiles);

  @override
  Future<Result<HistoryPage>> history(
    String storedId, {
    HistoryCursor? before,
  }) async {
    final path = '/api/sessions/${Uri.encodeComponent(storedId)}';
    if (before != null) return _earlier(path, before);
    // Ask for the newest page. A dashboard that honours `order=latest` echoes
    // it and counts offsets back from the newest row. One that does not —
    // Hermes 0.18.2 — counts from the oldest, so its newest page starts at
    // `message_count - historyPage`.
    final first = await _messages(path, offset: 0, limit: historyPage);
    switch (first) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final body):
        final rows = body['messages'].list.length;
        if (body['pagination']['order'].stringOrNull == 'latest') {
          return Ok(
            HistoryPage(
              items: HistoryParser.transcript(body),
              earlier: rows < historyPage
                  ? null
                  : const HistoryCursor(offset: historyPage, fromNewest: true),
            ),
          );
        }
        final all = HistoryPage(items: HistoryParser.transcript(body));
        if (rows < historyPage) return Ok(all);
        final row = await _session.connection.client.get(
          path,
          query: _scoped(const {}),
        );
        final count = row.valueOrNull?['message_count'].intOrNull;
        // Without a count the end cannot be found; the oldest page beats
        // nothing.
        if (count == null || count <= historyPage) return Ok(all);
        final start = count - historyPage;
        final tail = await _messages(path, offset: start, limit: historyPage);
        return tail.map(
          (page) => page['messages'].list.isEmpty
              ? all
              : HistoryPage(
                  items: HistoryParser.transcript(page),
                  earlier: HistoryCursor(offset: start, fromNewest: false),
                ),
        );
    }
  }

  Future<Result<HistoryPage>> _earlier(
    String path,
    HistoryCursor before,
  ) async {
    if (before.fromNewest) {
      final page = await _messages(
        path,
        offset: before.offset,
        limit: historyPage,
      );
      return page.map((body) {
        final rows = body['messages'].list.length;
        return HistoryPage(
          items: HistoryParser.transcript(body),
          earlier: rows < historyPage
              ? null
              : HistoryCursor(offset: before.offset + rows, fromNewest: true),
        );
      });
    }
    if (before.offset <= 0) return const Ok(HistoryPage(items: []));
    final start = math.max(0, before.offset - historyPage);
    final page = await _messages(
      path,
      offset: start,
      limit: before.offset - start,
    );
    return page.map(
      (body) => HistoryPage(
        items: HistoryParser.transcript(body),
        earlier: start == 0
            ? null
            : HistoryCursor(offset: start, fromNewest: false),
      ),
    );
  }

  Future<Result<Json>> _messages(
    String path, {
    required int offset,
    required int limit,
  }) => _session.connection.client.get(
    '$path/messages',
    query: _scoped({
      'limit': limit,
      'offset': offset,
      'order': 'latest',
      'include_compacted': 'true',
    }),
  );

  @override
  Future<Result<ResumedConversation>> resume(String storedId) async {
    final result = await _session.call(
      'session.resume',
      params: _scoped({
        'session_id': storedId,
        'cols': 96,
        'source': 'desktop',
        'omit_messages': true,
      }),
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
      final info = json['info'];
      return ResumedConversation(
        runtimeId:
            HistoryParser.firstText(json, const ['session_id']) ?? storedId,
        running: json['running'].boolOrNull ?? info['running'].boolean(),
        pending: pending,
        model: HistoryParser.firstText(info, const ['model']),
        provider: HistoryParser.firstText(info, const ['provider']),
      );
    });
  }

  @override
  Future<Result<NewConversation>> create() async {
    final result = await _session.call(
      'session.create',
      params: _scoped({'cols': 96, 'source': 'desktop'}),
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
  Future<Result<void>> interrupt(String runtimeId) async =>
      (await _session.call(
        'session.interrupt',
        params: {'session_id': runtimeId},
      )).map((_) {});

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
        : const Err(
            IrisFailure.offline(message: 'Not connected to the dashboard.'),
          );
  }

  @override
  Future<Result<ModelOptions>> modelOptions({String? runtimeId}) async =>
      (await _session.call(
        'model.options',
        params: {'explicit_only': true, 'session_id': ?runtimeId},
      )).map(CatalogParser.modelOptions);

  @override
  Future<Result<ModelSwitch>> switchModel(
    String runtimeId, {
    required String model,
    required String provider,
    required bool confirmed,
  }) async =>
      (await _session.call(
        'config.set',
        params: {
          'key': 'model',
          'session_id': runtimeId,
          'value': '$model --provider $provider --session',
          if (confirmed) 'confirm_expensive_model': true,
        },
      )).map((json) => CatalogParser.modelSwitch(json, requested: model));

  @override
  Future<Result<List<SlashCommand>>> commands() async =>
      (await _session.call('commands.catalog')).map(CatalogParser.commands);

  @override
  Future<Result<SlashOutcome>> runSlash(
    String runtimeId,
    String command,
  ) async {
    final cleaned = command.replaceFirst(RegExp('^/+'), '').trim();
    final result = await _session.call(
      'slash.exec',
      params: {'session_id': runtimeId, 'command': cleaned},
    );
    // Only a gateway answer means slash.exec declined to run it. A timeout or
    // a dropped socket may mean it IS running, and dispatching it again could
    // run it twice.
    if (result case Err(:final failure)
        when failure.kind == FailureKind.rejected) {
      final space = cleaned.indexOf(' ');
      final dispatched = await _session.call(
        'command.dispatch',
        params: {
          'session_id': runtimeId,
          'name': space < 0 ? cleaned : cleaned.substring(0, space),
          'arg': space < 0 ? '' : cleaned.substring(space + 1).trim(),
        },
      );
      // When slash.exec pointed at command.dispatch, dispatch's own failure is
      // the real one; otherwise slash.exec's rejection is.
      if (dispatched is Err &&
          !(failure.message ?? '').contains('command.dispatch')) {
        return Err(failure);
      }
      return dispatched.map(CatalogParser.slashOutcome);
    }
    return result.map(CatalogParser.slashOutcome);
  }

  Future<void> dispose() async {
    await _eventSubscription.cancel();
    await _requestSubscription.cancel();
    await _linkSubscription.cancel();
    await _events.close();
    await _reconnected.close();
  }
}
