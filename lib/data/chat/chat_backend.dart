/// Conversations on one dashboard: listing, reading, sending, answering.
///
/// [ChatBackend] is the seam the chat screen depends on, so the screen is
/// tested against a scripted fake. [DashboardChat] is the real one: the live
/// socket for anything live, and REST for stored history and lists — the split
/// Hermes Desktop and Conduit both use, because a long transcript sent over the
/// socket would hold up every event queued behind it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/failure.dart';
import '../../core/json.dart';
import '../../core/result.dart';
import '../rpc/dashboard_session.dart';
import '../rpc/rpc_frame.dart';
import 'attachment.dart';
import 'catalog_parser.dart';
import 'chat_event.dart';
import 'chat_models.dart';
import 'connection_models.dart';
import 'history_parser.dart';
import 'search_merge.dart';
import 'usage_parser.dart';

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
    this.context,
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

  /// How full the context window is, when the gateway says. A lazy, idle
  /// session never does.
  final ContextUsage? context;
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

  /// Sends [text] as a turn, or, on a busy session, as Hermes's busy policy
  /// decides. [queued] forces "run after the current reply".
  Future<Result<SubmitOutcome>> submit(
    String runtimeId,
    String text, {
    bool queued = false,
  });

  /// Deletes [storedId] for good. Hermes refuses while it is live.
  Future<Result<void>> delete(String storedId);

  /// Removes the last user turn and everything after it. Returns how many
  /// messages went.
  Future<Result<int>> undo(String runtimeId);

  /// Copies all of [storedId] into a new conversation.
  Future<Result<NewConversation>> branchWhole(String storedId);

  /// A new conversation seeded with [prefix] (the visible user and assistant
  /// text up to a chosen reply), linked to [storedId] as its parent.
  Future<Result<NewConversation>> branchFrom(
    String storedId,
    List<SeedMessage> prefix, {
    required String title,
  });

  /// Summarises older turns in the live session.
  Future<Result<void>> compress(String runtimeId);

  /// What Hermes does with a message sent mid-reply, for this profile.
  Future<Result<BusyMode>> busyMode();
  Future<Result<void>> setBusyMode(BusyMode mode);

  Future<Result<void>> setReasoning(String runtimeId, ReasoningEffort effort);
  Future<Result<void>> setFast(String runtimeId, {required bool fast});

  /// Answers a save-login prompt. Both values go straight into the reply
  /// frame and are kept nowhere.
  Future<Result<void>> answerLogin(
    LoginRequest request, {
    required String identifier,
    required String password,
  });

  /// Answers [targets] of an open connection card; [settle] also closes it.
  Future<Result<void>> answerConnection(
    ConnectionRequest request,
    List<TargetAnswer> targets, {
    bool settle = false,
  });

  /// The runtime sessions live on the gateway right now.
  Future<Result<List<LiveStatus>>> activeSessions();

  /// Stages [file] in the runtime session. Returns the `@file:` reference
  /// the prompt must carry, or null for an image Hermes took as an image.
  Future<Result<String?>> attach(String runtimeId, Attachment file);

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

  /// Steers the running turn with [text], without interrupting it.
  Future<Result<SteerOutcome>> steer(String runtimeId, String text);

  /// Answers a sudo or secret prompt. An empty [value] skips it.
  Future<Result<void>> answerInput(InputRequest request, String value);

  Future<Result<void>> rename(String storedId, String title);

  Future<Result<void>> setArchived(String storedId, {required bool archived});

  /// A page of this profile's archived conversations, newest first.
  Future<Result<ConversationPage>> archivedConversations(int offset);

  /// One conversation's row, for a pin that is not in the loaded pages.
  Future<Result<ConversationSummary>> conversation(String storedId);

  /// This profile's conversations matching [query], one hit per conversation.
  Future<Result<List<SearchHit>>> search(String query);

  /// A search across [profiles], hits labelled by profile and merged. Fails
  /// only when every profile's search fails.
  Future<Result<List<SearchHit>>> searchAcross(
    String query,
    List<String> profiles,
  );

  /// What was said in [wav] (16 kHz mono WAV), by Hermes' speech-to-text.
  /// Empty when it heard nothing worth sending.
  Future<Result<String>> transcribe(Uint8List wav);
}

final class DashboardChat implements ChatBackend {
  DashboardChat(this._session, {this.profile = 'default'})
    : _live = _session.state.phase == LinkPhase.live,
      _everLive = _session.state.phase == LinkPhase.live {
    _linkSubscription = _session.states.listen(_onLink);
    _eventSubscription = _session.events.listen((event) {
      if (ChatEvent.fromEvent(event) case final parsed?) _events.add(parsed);
      if (ChatEvent.contextFromEvent(event) case final context?) {
        _events.add(context);
      }
      if (ChatEvent.infoFromEvent(event) case final info?) _events.add(info);
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

  /// Conversations a search returns.
  static const searchLimit = 30;

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
  Future<Result<ConversationPage>> conversations(int offset) =>
      _page(offset, archived: 'exclude');

  @override
  Future<Result<ConversationPage>> archivedConversations(int offset) =>
      _page(offset, archived: 'only');

  Future<Result<ConversationPage>> _page(
    int offset, {
    required String archived,
  }) async => (await _session.connection.client.get(
    '/api/profiles/sessions',
    // Always named, even for the default: without it the route merges
    // every profile's conversations.
    query: {
      'profile': profile,
      'limit': conversationPage,
      'offset': offset,
      'min_messages': 1,
      'archived': archived,
      'order': 'recent',
    },
  )).map(CatalogParser.conversationPage);

  @override
  Future<Result<List<AgentProfile>>> profiles() async =>
      (await _session.connection.client.get(
        '/api/profiles',
      )).map(CatalogParser.profiles);

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
      final runtime =
          HistoryParser.firstText(json, const ['session_id']) ?? storedId;
      // A connection card open before Iris attached comes back with the
      // resume, not as a server request. Null without an op id.
      if (ConnectionRequest.parse(
            json['pending_connection'],
            sessionId: runtime,
          )
          case final card?) {
        pending.add(ConnectionAsked(card));
      }
      final info = json['info'];
      return ResumedConversation(
        runtimeId: runtime,
        running: json['running'].boolOrNull ?? info['running'].boolean(),
        pending: pending,
        model: HistoryParser.firstText(info, const ['model']),
        provider: HistoryParser.firstText(info, const ['provider']),
        context: UsageParser.context(info),
      );
    });
  }

  @override
  Future<Result<NewConversation>> create() async => _newConversation(
    await _session.call(
      'session.create',
      params: _scoped({'cols': 96, 'source': 'desktop'}),
    ),
    endpoint: 'session.create',
  );

  @override
  Future<Result<SubmitOutcome>> submit(
    String runtimeId,
    String text, {
    bool queued = false,
  }) async => (await _session.call(
    'prompt.submit',
    params: {'session_id': runtimeId, 'text': text, if (queued) 'queued': true},
    timeout: submitTimeout,
  )).map((json) => SubmitOutcome.fromStatus(json['status'].stringOrNull));

  @override
  Future<Result<void>> delete(String storedId) async =>
      (await _session.connection.client.delete(
        '/api/sessions/${Uri.encodeComponent(storedId)}',
        query: _scoped(const {}),
      )).map((_) {});

  @override
  Future<Result<int>> undo(String runtimeId) async => (await _session.call(
    'session.undo',
    params: {'session_id': runtimeId},
  )).map((json) => json['removed'].integer());

  @override
  Future<Result<NewConversation>> branchWhole(String storedId) async =>
      _newConversation(
        await _session.call(
          'session.branch_stored',
          params: _scoped({
            'parent_session_id': storedId,
            'cols': 96,
            'source': 'desktop',
          }),
        ),
        endpoint: 'session.branch_stored',
      );

  @override
  Future<Result<NewConversation>> branchFrom(
    String storedId,
    List<SeedMessage> prefix, {
    required String title,
  }) async => _newConversation(
    await _session.call(
      'session.create',
      params: _scoped({
        'cols': 96,
        'source': 'desktop',
        'parent_session_id': storedId,
        'title': title,
        'messages': [for (final message in prefix) message.toWire()],
      }),
    ),
    endpoint: 'session.create',
  );

  @override
  Future<Result<void>> compress(String runtimeId) async => (await _session.call(
    'session.compress',
    params: {'session_id': runtimeId},
    timeout: const Duration(seconds: 120),
  )).map((_) {});

  @override
  Future<Result<BusyMode>> busyMode() async => (await _session.call(
    'config.set',
    params: _scoped({'key': 'busy', 'value': 'status'}),
  )).map((json) => BusyMode.fromWire(json['value'].stringOrNull));

  @override
  Future<Result<void>> setBusyMode(BusyMode mode) async => (await _session.call(
    'config.set',
    params: _scoped({'key': 'busy', 'value': mode.wire}),
  )).map((_) {});

  @override
  Future<Result<void>> setReasoning(
    String runtimeId,
    ReasoningEffort effort,
  ) async => (await _session.call(
    'config.set',
    params: {'key': 'reasoning', 'session_id': runtimeId, 'value': effort.wire},
  )).map((_) {});

  @override
  Future<Result<void>> setFast(String runtimeId, {required bool fast}) async =>
      (await _session.call(
        'config.set',
        params: {
          'key': 'fast',
          'session_id': runtimeId,
          'value': fast ? 'fast' : 'normal',
        },
      )).map((_) {});

  @override
  Future<Result<void>> answerLogin(
    LoginRequest request, {
    required String identifier,
    required String password,
  }) async =>
      // Straight into the reply frame; never logged or kept.
      _session.replyToServerRequest(request.requestId, {
        // Both empty is a skip, which Hermes reads as an empty value.
        'value': identifier.isEmpty && password.isEmpty
            ? ''
            : jsonEncode({'identifier': identifier, 'password': password}),
      })
      ? const Ok(null)
      : const Err(
          IrisFailure.offline(message: 'Not connected to the dashboard.'),
        );

  @override
  Future<Result<void>> answerConnection(
    ConnectionRequest request,
    List<TargetAnswer> targets, {
    bool settle = false,
  }) async => (await _session.call(
    'connection.respond',
    params: _scoped({
      'owner': {'type': 'session', 'session_id': request.sessionId},
      'op_id': request.opId,
      'result': {
        'targets': [for (final target in targets) target.toWire()],
        if (settle) 'settled_by': 'continue',
      },
    }),
  )).map((_) {});

  @override
  Future<Result<List<LiveStatus>>> activeSessions() async =>
      (await _session.call(
        'session.active_list',
        params: _scoped(const {}),
      )).map(
        (json) => [
          for (final row in json['sessions'].list)
            if (row['id'].stringOrNull case final String id when id.isNotEmpty)
              LiveStatus(
                runtimeId: id,
                storedId: row['session_key'].string(),
                status: row['status'].string('idle'),
              ),
        ],
      );

  /// A new conversation from a `session.create`-shaped answer.
  Result<NewConversation> _newConversation(
    Result<Json> result, {
    required String endpoint,
  }) {
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final json):
        final runtimeId = HistoryParser.firstText(json, const ['session_id']);
        if (runtimeId == null) {
          return Err(
            IrisFailure.malformed(
              message: 'The dashboard did not return a session id.',
              endpoint: endpoint,
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

  /// Long enough to send 20 MB as base64 over a slow uplink.
  static const attachTimeout = Duration(seconds: 120);

  @override
  Future<Result<String?>> attach(String runtimeId, Attachment file) async {
    if (file.isImage) {
      final sent = await _session.call(
        'image.attach_bytes',
        params: {
          'session_id': runtimeId,
          'content_base64': base64Encode(file.bytes),
          'filename': file.name,
        },
        timeout: attachTimeout,
      );
      switch (sent) {
        case Ok():
          return const Ok(null);
        case Err(:final failure) when !_refusedAsImage(failure):
          return Err(failure);
        case Err():
        // Hermes won't take it as an image (a format it doesn't list, or past
        // its image size cap). It still goes up, as a file.
      }
    }
    final staged = await _session.call(
      'file.attach',
      params: {
        'session_id': runtimeId,
        'data_url': file.dataUrl,
        'name': file.name,
        'path': '',
      },
      timeout: attachTimeout,
    );
    return staged.map(_fileReference);
  }

  static bool _refusedAsImage(IrisFailure failure) => switch (failure.cause) {
    RpcError(code: 4016 || 4018) => true,
    _ => false,
  };

  /// The reply's `ref_text`, or one built from the staged path.
  static String? _fileReference(Json result) {
    final text = result['ref_text'].stringOrNull?.trim();
    if (text != null && text.startsWith('@file:') && text.length > 6) {
      return text;
    }
    final path = [result['ref_path'].stringOrNull, result['path'].stringOrNull]
        .map((s) => s?.trim())
        .firstWhere((s) => s != null && s.isNotEmpty, orElse: () => null);
    return path == null ? null : '@file:${formatReferenceValue(path)}';
  }

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
  }) async => (await _session.call(
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
    if (result case Err(
      :final failure,
    ) when failure.kind == FailureKind.rejected) {
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

  @override
  Future<Result<SteerOutcome>> steer(String runtimeId, String text) async =>
      (await _session.call(
        'session.steer',
        params: {'session_id': runtimeId, 'text': text},
      )).map(
        (json) => json['status'].string() == 'rejected'
            ? SteerOutcome.rejected
            : SteerOutcome.accepted,
      );

  @override
  Future<Result<void>> answerInput(InputRequest request, String value) async =>
      // The value goes straight into the reply frame and is not kept or
      // logged; the RPC layer logs method names, never results.
      _session.replyToServerRequest(request.requestId, {'value': value})
      ? const Ok(null)
      : const Err(
          IrisFailure.offline(message: 'Not connected to the dashboard.'),
        );

  @override
  Future<Result<void>> rename(String storedId, String title) =>
      _patchSession(storedId, {'title': title});

  @override
  Future<Result<void>> setArchived(String storedId, {required bool archived}) =>
      _patchSession(storedId, {'archived': archived});

  /// The owning profile goes in the body: the dashboard opens that
  /// profile's database from it, and without it a named profile's write
  /// lands on the default's (Hermes Desktop, `api/sessions.ts`).
  Future<Result<void>> _patchSession(
    String storedId,
    Map<String, Object?> body,
  ) async => (await _session.connection.client.patch(
    '/api/sessions/${Uri.encodeComponent(storedId)}',
    body: _scoped(body),
  )).map((_) {});

  /// A two-minute clip is about 5 MB as base64; transcription can take a
  /// while on a small host.
  static const transcribeTimeout = Duration(seconds: 90);

  @override
  Future<Result<String>> transcribe(Uint8List wav) async {
    const route = '/api/audio/transcribe';
    final sent = await _session.connection.client.post(
      route,
      body: {
        'data_url': 'data:audio/wav;base64,${base64Encode(wav)}',
        'mime_type': 'audio/wav',
      },
      query: _scoped({}),
      receiveTimeout: transcribeTimeout,
    );
    switch (sent) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final error = value['error'].stringOrNull?.trim();
        if (error != null && error.isNotEmpty) {
          return Err(
            IrisFailure(FailureKind.server, message: error, endpoint: route),
          );
        }
        final words =
            value['transcript'].stringOrNull ?? value['text'].stringOrNull;
        if (words == null) {
          return Err(
            const IrisFailure(
              FailureKind.malformed,
              message: "Hermes didn't send back what you said.",
              endpoint: route,
            ),
          );
        }
        return Ok(words.trim());
    }
  }

  @override
  Future<Result<ConversationSummary>> conversation(String storedId) async {
    final path = '/api/sessions/${Uri.encodeComponent(storedId)}';
    final result = await _session.connection.client.get(
      path,
      query: _scoped(const {}),
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final row = HistoryParser.conversationRow(value);
        return row == null
            ? Err(
                IrisFailure.malformed(
                  message: 'The dashboard did not describe that conversation.',
                  endpoint: path,
                ),
              )
            : Ok(row);
    }
  }

  @override
  Future<Result<List<SearchHit>>> search(String query) async =>
      (await _session.connection.client.get(
        '/api/sessions/search',
        // Named even for the default, as the list is: an unscoped search
        // reads the gateway's launch profile, whatever is on screen.
        query: {'q': query, 'limit': searchLimit, 'profile': profile},
      )).map(UsageParser.searchHits);

  @override
  Future<Result<List<SearchHit>>> searchAcross(
    String query,
    List<String> profiles,
  ) async {
    final results = await Future.wait([
      for (final name in profiles)
        _session.connection.client
            .get(
              '/api/sessions/search',
              query: {'q': query, 'limit': searchLimit, 'profile': name},
            )
            .then((result) => (name, result.map(UsageParser.searchHits))),
    ]);
    final byProfile = <String, List<SearchHit>>{
      for (final (name, result) in results) name: ?result.valueOrNull,
    };
    if (byProfile.isEmpty && results.isNotEmpty) {
      return Err(results.first.$2.failureOrNull!);
    }
    return Ok(mergeProfileHits(byProfile));
  }

  Future<void> dispose() async {
    await _eventSubscription.cancel();
    await _requestSubscription.cancel();
    await _linkSubscription.cancel();
    await _events.close();
    await _reconnected.close();
  }
}
