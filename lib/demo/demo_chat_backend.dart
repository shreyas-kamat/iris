/// The demo, seen through one profile, as the `ChatBackend` the screens use.
library;

import 'dart:typed_data';

import '../core/result.dart';
import '../data/chat/chat_backend.dart';
import '../data/chat/chat_event.dart';
import '../data/chat/chat_models.dart';
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
  Future<Result<void>> submit(String runtimeId, String text) async {
    _world.submit(runtimeId, text);
    return const Ok(null);
  }

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
  Future<Result<List<SearchHit>>> search(String query) async =>
      Ok(_world.search(profile, query));
}
