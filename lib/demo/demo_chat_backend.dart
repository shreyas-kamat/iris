/// The demo, seen through one profile, as the `ChatBackend` the screens use.
library;

import 'dart:typed_data';

import '../core/failure.dart';
import '../core/result.dart';
import '../data/chat/attachment.dart';
import '../data/chat/chat_backend.dart';
import '../data/chat/chat_event.dart';
import '../data/chat/chat_models.dart';
import '../data/chat/connection_models.dart';
import '../data/chat/search_merge.dart';
import 'demo_content.dart';
import 'demo_world.dart';

final class DemoChatBackend implements ChatBackend {
  DemoChatBackend(this._world, {required this.profile});

  final DemoWorld _world;
  final String profile;

  @override
  Stream<ChatEvent> get events => _world.events;

  @override
  Stream<void> get reconnected => const Stream.empty();

  @override
  Future<Result<ConversationPage>> conversations(int offset) async =>
      Ok(_world.page(profile, offset, archived: false));

  @override
  Future<Result<ConversationPage>> archivedConversations(int offset) async =>
      Ok(_world.page(profile, offset, archived: true));

  @override
  Future<Result<List<AgentProfile>>> profiles() async => Ok(_world.profiles);

  @override
  Future<Result<HistoryPage>> history(
    String storedId, {
    HistoryCursor? before,
  }) async => Ok(_world.history(storedId));

  @override
  Future<Result<ResumedConversation>> resume(String storedId) async =>
      Ok(_world.resume(storedId));

  @override
  Future<Result<NewConversation>> create() async => Ok(_world.create(profile));

  @override
  Future<Result<SubmitOutcome>> submit(
    String runtimeId,
    String text, {
    bool queued = false,
    VoiceSubmit? voice,
  }) async {
    _world.submit(runtimeId, text);
    return const Ok(SubmitOutcome.started);
  }

  @override
  Future<Result<void>> delete(String storedId) async {
    _world.delete(storedId);
    return const Ok(null);
  }

  @override
  Future<Result<int>> undo(String runtimeId) async => const Ok(1);

  @override
  Future<Result<NewConversation>> branchWhole(String storedId) async =>
      Ok(_world.create(profile));

  @override
  Future<Result<NewConversation>> branchFrom(
    String storedId,
    List<SeedMessage> prefix, {
    required String title,
  }) async => Ok(_world.create(profile));

  @override
  Future<Result<void>> compress(String runtimeId) async => const Ok(null);

  @override
  Future<Result<BusyMode>> busyMode() async => Ok(_world.busyMode);

  @override
  Future<Result<void>> setBusyMode(BusyMode mode) async {
    _world.busyMode = mode;
    return const Ok(null);
  }

  @override
  Future<Result<void>> setReasoning(String runtimeId, ReasoningEffort effort) async =>
      const Ok(null);

  @override
  Future<Result<void>> setFast(String runtimeId, {required bool fast}) async =>
      const Ok(null);

  @override
  Future<Result<void>> answerLogin(
    LoginRequest request, {
    required String identifier,
    required String password,
  }) async {
    _world.answerPrompt(request.sessionId);
    return const Ok(null);
  }

  /// Approving one target leaves the card as it is, so it can show the next;
  /// Continue (`settle`) ends the card and the script with it.
  @override
  Future<Result<void>> answerConnection(
    ConnectionRequest request,
    List<TargetAnswer> targets, {
    bool settle = false,
  }) async {
    if (settle) _world.answerPrompt(request.sessionId);
    return const Ok(null);
  }

  @override
  Future<Result<List<LiveStatus>>> activeSessions() async => const Ok([]);

  @override
  Future<Result<String?>> attach(String runtimeId, Attachment file) async =>
      Ok('@file:/demo/${file.name}');

  @override
  Future<Result<void>> interrupt(String runtimeId) async {
    _world.interrupt(runtimeId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> answerApproval(
    ApprovalRequest request,
    String choice,
  ) async {
    _world.answerApproval(request, choice);
    return const Ok(null);
  }

  @override
  Future<Result<void>> answerClarify(
    ClarifyRequest request,
    ClarifyQuestion question,
    String answer,
  ) async => const Ok(null);

  @override
  Future<Result<void>> answerInput(InputRequest request, String value) async {
    _world.answerInput(request);
    return const Ok(null);
  }

  @override
  Future<Result<ModelOptions>> modelOptions({String? runtimeId}) async =>
      Ok(_world.modelOptions);

  @override
  Future<Result<ModelSwitch>> switchModel(
    String runtimeId, {
    required String model,
    required String provider,
    required bool confirmed,
  }) async => Ok(_world.switchModel(runtimeId, model, provider));

  @override
  Future<Result<List<SlashCommand>>> commands() async => const Ok(demoCommands);

  @override
  Future<Result<SlashOutcome>> runSlash(
    String runtimeId,
    String command,
  ) async => Ok(_world.slash(runtimeId, command));

  @override
  Future<Result<SteerOutcome>> steer(String runtimeId, String text) async =>
      Ok(_world.steer(runtimeId, text));

  @override
  Future<Result<void>> rename(String storedId, String title) async {
    _world.rename(storedId, title);
    return const Ok(null);
  }

  @override
  Future<Result<void>> setArchived(
    String storedId, {
    required bool archived,
  }) async {
    _world.setArchived(storedId, archived: archived);
    return const Ok(null);
  }

  @override
  Future<Result<String>> transcribe(Uint8List wav) async =>
      const Ok('How much disk space is left on the NAS?');

  @override
  Future<Result<ConversationSummary>> conversation(String storedId) async {
    final page = _world.page(profile, 0, archived: false).items;
    for (final row in [..._world.page(profile, 0, archived: true).items, ...page]) {
      if (row.id == storedId) return Ok(row);
    }
    return const Err(IrisFailure(FailureKind.notFound));
  }

  @override
  Future<Result<List<SearchHit>>> search(String query) async =>
      Ok(_world.search(profile, query));

  @override
  Future<Result<List<SearchHit>>> searchAcross(
    String query,
    List<String> profiles,
  ) async => Ok(
    mergeProfileHits({
      for (final name in profiles) name: _world.search(name, query),
    }),
  );
}
