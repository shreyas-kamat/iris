/// A scripted chat backend, so the controller and screens are tested without
/// a socket.
library;

import 'dart:async';

import 'package:iris/core/result.dart';
import 'package:iris/data/chat/chat_backend.dart';
import 'package:iris/data/chat/chat_event.dart';
import 'package:iris/data/chat/chat_models.dart';

final class FakeChatBackend implements ChatBackend {
  final _events = StreamController<ChatEvent>.broadcast();
  final _reconnects = StreamController<void>.broadcast();

  Result<List<ConversationSummary>> conversationsResult = const Ok([]);
  Result<List<TranscriptItem>> historyResult = const Ok([]);
  Result<ResumedConversation> resumeResult = const Ok(
    ResumedConversation(runtimeId: 'run-1'),
  );
  Result<NewConversation> createResult = const Ok(
    NewConversation(runtimeId: 'run-new', storedId: 'stored-new'),
  );
  Result<void> submitResult = const Ok(null);
  Result<void> answerResult = const Ok(null);

  /// Everything asked of the backend, in order: `history <id>`,
  /// `resume <id>`, `create`, `interrupt <id>`, `conversations`.
  final List<String> calls = [];
  final List<(String, String)> submitted = [];
  final List<String> approvals = [];
  final List<String> answers = [];

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
  Future<Result<List<ConversationSummary>>> conversations() async {
    calls.add('conversations');
    return conversationsResult;
  }

  @override
  Future<Result<List<TranscriptItem>>> history(String storedId) async {
    calls.add('history $storedId');
    return historyResult;
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
}
