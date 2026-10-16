/// The demo's whole state: conversations, the model, and the scripts playing.
///
/// It stands in for a Hermes server. One world lives for one demo session and
/// is shared by every profile's `DemoChatBackend`, so switching profile does
/// not lose a turn that is still playing.
library;

import 'dart:async';

import '../data/chat/chat_backend.dart';
import '../data/chat/chat_event.dart';
import '../data/chat/chat_models.dart';
import 'demo_content.dart';
import 'demo_script.dart';
import 'script_player.dart';

final class _Conversation {
  _Conversation({
    required this.id,
    required this.title,
    required this.profile,
    required this.startedAt,
    required this.items,
    this.source,
    this.archived = false,
  });

  final String id;
  String title;
  final String profile;
  final DateTime startedAt;
  final List<TranscriptItem> items;
  final String? source;
  bool archived;
  double context = 12;

  ConversationSummary get summary => ConversationSummary(
    id: id,
    title: title,
    startedAt: startedAt,
    messageCount: items
        .where((item) => item is UserTurn || item is AssistantTurn)
        .length,
    source: source,
    profile: profile,
  );
}

final class DemoWorld {
  DemoWorld({DateTime Function() clock = DateTime.now, Delay delay = realDelay})
    : _clock = clock,
      _delay = delay {
    final now = clock();
    for (final seed in demoSeeds) {
      _conversations.add(
        _Conversation(
          id: seed.id,
          title: seed.title,
          profile: seed.profile,
          startedAt: now.subtract(seed.age),
          items: [...seed.items],
          source: seed.source,
          archived: seed.archived,
        ),
      );
    }
  }

  static const _pageSize = 20;
  static const _runPrefix = 'demo-run-';

  final DateTime Function() _clock;
  final Delay _delay;
  final _events = StreamController<ChatEvent>.broadcast();

  /// Newest first.
  final List<_Conversation> _conversations = [];
  final Map<String, ScriptPlayer> _players = {};
  final Map<String, String> _lastPrompt = {};
  final Set<String> _played = {};
  var _created = 0;
  String _model = demoModel.$1;
  String _provider = demoModel.$2;

  static String runtimeIdFor(String storedId) => '$_runPrefix$storedId';

  static String _storedIdFor(String runtimeId) =>
      runtimeId.startsWith(_runPrefix)
      ? runtimeId.substring(_runPrefix.length)
      : runtimeId;

  Stream<ChatEvent> get events => _events.stream;

  List<AgentProfile> get profiles => demoProfiles;

  _Conversation? _find(String storedId) {
    for (final conversation in _conversations) {
      if (conversation.id == storedId) return conversation;
    }
    return null;
  }

  ConversationPage page(String profile, int offset, {required bool archived}) {
    final rows = [
      for (final c in _conversations)
        if (c.profile == profile && c.archived == archived) c.summary,
    ];
    final start = offset.clamp(0, rows.length);
    final end = (start + _pageSize).clamp(0, rows.length);
    return ConversationPage(
      items: rows.sublist(start, end),
      total: rows.length,
    );
  }

  HistoryPage history(String storedId) =>
      HistoryPage(items: List.of(_find(storedId)?.items ?? const []));

  NewConversation create(String profile) {
    final id = 'demo-new-${_created++}';
    _conversations.insert(
      0,
      _Conversation(
        id: id,
        title: '',
        profile: profile,
        startedAt: _clock(),
        items: [],
      ),
    );
    return NewConversation(runtimeId: runtimeIdFor(id), storedId: id);
  }

  ResumedConversation resume(String storedId) => ResumedConversation(
    runtimeId: runtimeIdFor(storedId),
    running: _players[storedId]?.running ?? false,
    model: _model,
    provider: _provider,
    context: ContextUsage(percent: _find(storedId)?.context ?? 12),
  );

  void submit(String runtimeId, String text) {
    final storedId = _storedIdFor(runtimeId);
    final conversation = _find(storedId);
    if (conversation == null) return;
    conversation.items.add(
      UserTurn(id: '$storedId-user-${conversation.items.length}', text: text),
    );
    final script = demoScriptFor(text);
    if (conversation.title.isEmpty) {
      conversation.title = script?.title ?? _titleFrom(text);
      _events.add(TitleChanged(runtimeId, conversation.title));
    }
    final firstRun = script?.firstRun;
    final key = '$storedId/${script?.prompt}';
    final steps = script == null
        ? const <DemoStep>[SayStep(demoFallback)]
        : firstRun != null && !_played.contains(key)
        ? firstRun
        : script.steps;
    _played.add(key);
    _lastPrompt[storedId] = text;
    final player = _players[storedId] = ScriptPlayer(
      sessionId: runtimeId,
      emit: (event) {
        if (event is ContextChanged) conversation.context = event.usage.percent;
        if (!_events.isClosed) _events.add(event);
      },
      record: conversation.items.add,
      delay: _delay,
    );
    unawaited(player.play(steps));
  }

  static String _titleFrom(String text) {
    final line = text.trim().split('\n').first;
    return line.length <= 40 ? line : '${line.substring(0, 39)}…';
  }

  void interrupt(String runtimeId) => _players[_storedIdFor(runtimeId)]?.stop();

  SteerOutcome steer(String runtimeId, String text) =>
      _players[_storedIdFor(runtimeId)]?.steer(text) ?? false
      ? SteerOutcome.accepted
      : SteerOutcome.rejected;

  SlashOutcome slash(String runtimeId, String command) {
    final storedId = _storedIdFor(runtimeId);
    final name = command.trim().split(' ').first;
    if (name != '/retry') {
      return const SlashOutcome(
        kind: SlashKind.exec,
        text: 'Not available in the demo.',
      );
    }
    final prompt = _lastPrompt[storedId];
    final conversation = _find(storedId);
    if (prompt == null || conversation == null) {
      return const SlashOutcome(
        kind: SlashKind.exec,
        text: 'Nothing to retry.',
      );
    }
    // As Hermes does: the failed exchange goes, and the prompt is sent again.
    final last = conversation.items.lastIndexWhere((item) => item is UserTurn);
    if (last >= 0) {
      conversation.items.removeRange(last, conversation.items.length);
    }
    return SlashOutcome(kind: SlashKind.send, text: prompt);
  }

  void answerApproval(ApprovalRequest request, String choice) =>
      _players[_storedIdFor(request.sessionId)]?.answerApproval(
        approved: choice != 'deny',
      );

  /// The value typed is not taken: the demo needs only to know it was sent.
  void answerInput(InputRequest request) =>
      _players[_storedIdFor(request.sessionId)]?.answerSecret();

  /// What the demo's "While Hermes is replying" setting says.
  BusyMode busyMode = BusyMode.interrupt;

  void delete(String storedId) =>
      _conversations.removeWhere((c) => c.id == storedId);

  void rename(String storedId, String title) => _find(storedId)?.title = title;

  void setArchived(String storedId, {required bool archived}) =>
      _find(storedId)?.archived = archived;

  List<SearchHit> search(String profile, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final c in _conversations)
        if (c.profile == profile) ?_hit(c, needle),
    ];
  }

  SearchHit? _hit(_Conversation c, String needle) {
    for (final item in c.items) {
      final text = switch (item) {
        UserTurn(:final text) => text,
        AssistantTurn(:final text) => text,
        _ => '',
      };
      final at = text.toLowerCase().indexOf(needle);
      if (at < 0) continue;
      final start = (at - 30).clamp(0, text.length);
      final end = (at + needle.length + 50).clamp(0, text.length);
      return SearchHit(
        storedId: c.id,
        title: c.title,
        archived: c.archived,
        messageCount: c.summary.messageCount,
        lastActive: c.startedAt,
        snippet: [
          SnippetRun('${start > 0 ? '…' : ''}${text.substring(start, at)}'),
          SnippetRun(text.substring(at, at + needle.length), matched: true),
          SnippetRun(
            '${text.substring(at + needle.length, end)}'
            '${end < text.length ? '…' : ''}',
          ),
        ],
      );
    }
    if (c.title.toLowerCase().contains(needle)) {
      return SearchHit(
        storedId: c.id,
        title: c.title,
        archived: c.archived,
        messageCount: c.summary.messageCount,
        lastActive: c.startedAt,
      );
    }
    return null;
  }

  /// The same object until the model changes: a provider that reads it sees
  /// no change on a rebuild, so nothing downstream is invalidated.
  late ModelOptions _options = _buildOptions();

  ModelOptions _buildOptions() =>
      demoModelOptions(_clock(), model: _model, provider: _provider);

  ModelOptions get modelOptions => _options;

  ModelSwitch switchModel(String runtimeId, String model, String provider) {
    _model = model;
    _provider = provider;
    _options = _buildOptions();
    _events.add(ModelChanged(runtimeId, model: model, provider: provider));
    return ModelSwitch(model: model);
  }

  /// Ends every script without a word and closes the event stream.
  Future<void> dispose() async {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    await _events.close();
  }
}
