/// A scripted chat backend, so the controller and screens are tested without
/// a socket.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:iris/core/result.dart';
import 'package:iris/data/chat/attachment.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';

final class FakeChatBackend implements ChatBackend {
  final _events = StreamController<ChatEvent>.broadcast();
  final _reconnects = StreamController<void>.broadcast();

  Result<List<ConversationSummary>> conversationsResult = const Ok([]);

  /// The list's total; the page's own length when null.
  int? conversationsTotal;
  Result<List<AgentProfile>> profilesResult = const Ok([]);

  /// The newest page of history.
  Result<List<TranscriptItem>> historyResult = const Ok([]);

  /// The cursor reported with the newest page.
  HistoryCursor? historyEarlier;

  /// Any earlier page.
  Result<HistoryPage> earlierResult = const Ok(HistoryPage(items: []));
  Result<ResumedConversation> resumeResult = const Ok(
    ResumedConversation(runtimeId: 'run-1'),
  );
  Result<NewConversation> createResult = const Ok(
    NewConversation(runtimeId: 'run-new', storedId: 'stored-new'),
  );
  Result<void> submitResult = const Ok(null);
  Result<void> answerResult = const Ok(null);
  Result<ModelOptions> modelOptionsResult = const Ok(ModelOptions());
  Result<ModelSwitch> switchResult = const Ok(ModelSwitch(model: ''));
  Result<List<SlashCommand>> commandsResult = const Ok([]);
  Result<SlashOutcome> slashResult = const Ok(
    SlashOutcome(kind: SlashKind.exec),
  );

  /// Everything asked of the backend, in order: `history <id>`,
  /// `earlier <id> <offset>`, `resume <id>`, `create`, `interrupt <id>`,
  /// `conversations <offset>`, `profiles`, `models`, `commands`.
  final List<String> calls = [];
  final List<(String, String)> submitted = [];
  final List<String> approvals = [];
  final List<String> answers = [];

  /// `<model>@<provider>`, with ` confirmed` when it was.
  final List<String> switches = [];
  final List<String> slashes = [];

  Result<SteerOutcome> steerResult = const Ok(SteerOutcome.accepted);
  Result<void> renameResult = const Ok(null);
  Result<void> archiveResult = const Ok(null);
  Result<List<ConversationSummary>> archivedResult = const Ok([]);
  Result<List<SearchHit>> searchResult = const Ok([]);

  /// Held by a test to keep a steer in flight.
  Completer<void>? steerGate;

  final List<(String, String)> steers = [];
  final List<(String, String)> inputAnswers = [];
  final List<(String, String)> renames = [];
  final List<(String, bool)> archives = [];

  /// Called as each archive or unarchive is accepted, so a test can keep a
  /// server-side list in step with it.
  void Function(String storedId, {required bool archived})? onArchived;

  /// Queries searched, in order.
  final List<String> searches = [];

  /// Answered first, in order, before [modelOptionsResult]: a gateway whose
  /// answer changes between two asks, such as a usage cache warming up.
  final List<Result<ModelOptions>> modelOptionsQueue = [];

  /// Delivers [event] as if the gateway had sent it.
  void emit(ChatEvent event) => _events.add(event);

  /// Announces that the live link came back after a drop.
  void reconnect() => _reconnects.add(null);

  Future<void> close() async {
    await _events.close();
    await _reconnects.close();
  }

  @override
  Stream<ChatEvent> get events => _events.stream;

  @override
  Stream<void> get reconnected => _reconnects.stream;

  @override
  Future<Result<ConversationPage>> conversations(int offset) async {
    calls.add('conversations $offset');
    return conversationsResult.map(
      (items) => ConversationPage(
        items: items,
        total: conversationsTotal ?? items.length,
      ),
    );
  }

  @override
  Future<Result<List<AgentProfile>>> profiles() async {
    calls.add('profiles');
    return profilesResult;
  }

  @override
  Future<Result<HistoryPage>> history(
    String storedId, {
    HistoryCursor? before,
  }) async {
    if (before != null) {
      calls.add('earlier $storedId ${before.offset}');
      return earlierResult;
    }
    calls.add('history $storedId');
    return historyResult.map(
      (items) => HistoryPage(items: items, earlier: historyEarlier),
    );
  }

  @override
  Future<Result<ResumedConversation>> resume(String storedId) async {
    calls.add('resume $storedId');
    return resumeResult;
  }

  @override
  Future<Result<NewConversation>> create() async {
    calls.add('create');
    return createResult;
  }

  @override
  Future<Result<void>> submit(String runtimeId, String text) async {
    submitted.add((runtimeId, text));
    return submitResult;
  }

  final List<(String, String)> attached = [];
  Result<String?> Function(Attachment file) attachResult =
      (file) => Ok(file.isImage ? null : '@file:/s/${file.name}');

  @override
  Future<Result<String?>> attach(String runtimeId, Attachment file) async {
    attached.add((runtimeId, file.name));
    return attachResult(file);
  }

  @override
  Future<Result<void>> interrupt(String runtimeId) async {
    calls.add('interrupt $runtimeId');
    return const Ok(null);
  }

  @override
  Future<Result<void>> answerApproval(
    ApprovalRequest request,
    String choice,
  ) async {
    approvals.add(choice);
    return answerResult;
  }

  @override
  Future<Result<void>> answerClarify(
    ClarifyRequest request,
    ClarifyQuestion question,
    String answer,
  ) async {
    answers.add('${question.id}=$answer');
    return answerResult;
  }

  @override
  Future<Result<ModelOptions>> modelOptions({String? runtimeId}) async {
    calls.add('models');
    return modelOptionsQueue.isNotEmpty
        ? modelOptionsQueue.removeAt(0)
        : modelOptionsResult;
  }

  @override
  Future<Result<ModelSwitch>> switchModel(
    String runtimeId, {
    required String model,
    required String provider,
    required bool confirmed,
  }) async {
    switches.add('$model@$provider${confirmed ? ' confirmed' : ''}');
    return switchResult;
  }

  @override
  Future<Result<List<SlashCommand>>> commands() async {
    calls.add('commands');
    return commandsResult;
  }

  @override
  Future<Result<SlashOutcome>> runSlash(
    String runtimeId,
    String command,
  ) async {
    slashes.add(command);
    return slashResult;
  }

  @override
  Future<Result<SteerOutcome>> steer(String runtimeId, String text) async {
    steers.add((runtimeId, text));
    await steerGate?.future;
    return steerResult;
  }

  @override
  Future<Result<void>> answerInput(InputRequest request, String value) async {
    inputAnswers.add((request.requestId, value));
    return answerResult;
  }

  @override
  Future<Result<void>> rename(String storedId, String title) async {
    renames.add((storedId, title));
    return renameResult;
  }

  @override
  Future<Result<void>> setArchived(
    String storedId, {
    required bool archived,
  }) async {
    archives.add((storedId, archived));
    if (archiveResult is Ok) onArchived?.call(storedId, archived: archived);
    return archiveResult;
  }

  @override
  Future<Result<ConversationPage>> archivedConversations(int offset) async {
    calls.add('archived $offset');
    return archivedResult.map(
      (items) => ConversationPage(items: items, total: items.length),
    );
  }

  Result<String> transcribeResult = const Ok('dictated words');

  @override
  Future<Result<String>> transcribe(Uint8List wav) async => transcribeResult;

  @override
  Future<Result<List<SearchHit>>> search(String query) async {
    searches.add(query);
    return searchResult;
  }
}
