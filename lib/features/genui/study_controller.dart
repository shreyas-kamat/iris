/// Running a study: a new "Iris setup" chat asks Hermes to read the person's work and *propose* a profile, templates
/// and reply kits. This controller starts that chat and reports how it is going, from the chat itself and from what the
/// plugin has stored so far. Nothing it finds is used until the person approves it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/chat/chat_backend.dart';
import '../../data/chat/chat_models.dart';
import '../../data/genui/genui_api.dart';
import '../../data/genui/personal_models.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_state.dart';

enum StudyPhase {
  /// Explaining what a study reads; nothing has started.
  intro,

  /// Making the chat and sending the request.
  starting,

  /// Hermes is reading and proposing.
  working,

  /// The reply is complete.
  done,

  /// Something went wrong; [StudyState.message] says what.
  failed,
}

@immutable
final class StudyState {
  const StudyState({
    this.phase = StudyPhase.intro,
    this.profileProposed = false,
    this.proposedTemplates = 0,
    this.proposedKits = 0,
    this.conversationId,
    this.message,
  });

  final StudyPhase phase;

  /// A profile is waiting for review.
  final bool profileProposed;

  /// Templates waiting for review (displays and reply kits together).
  final int proposedTemplates;

  /// Of [proposedTemplates], how many are reply kits.
  final int proposedKits;

  /// The stored id of the "Iris setup" chat, so the person can open it.
  final String? conversationId;

  /// Why it failed.
  final String? message;

  /// There is something to review.
  bool get found => profileProposed || proposedTemplates > 0;

  StudyState copyWith({
    StudyPhase? phase,
    bool? profileProposed,
    int? proposedTemplates,
    int? proposedKits,
    String? conversationId,
    String? message,
  }) => StudyState(
    phase: phase ?? this.phase,
    profileProposed: profileProposed ?? this.profileProposed,
    proposedTemplates: proposedTemplates ?? this.proposedTemplates,
    proposedKits: proposedKits ?? this.proposedKits,
    conversationId: conversationId ?? this.conversationId,
    message: message ?? this.message,
  );
}

final class StudyController extends ValueNotifier<StudyState> {
  StudyController(
    this._backend,
    this._api, {
    this.pollEvery = const Duration(seconds: 8),
  }) : super(const StudyState());

  final ChatBackend _backend;
  final GenUiApi _api;

  /// How often the plugin is asked what has been proposed while Hermes works.
  final Duration pollEvery;

  /// The chat's title in the conversation list.
  static const chatTitle = 'Iris setup';

  /// What Hermes is asked. A plain sentence that names the skill: whether `/iris-study` resolves as a command depends on
  /// the Hermes version, and a sentence works on all of them.
  static const prompt =
      'Study my work for Iris. Use the iris-study skill '
      "(skill_view('iris:iris-study')) and follow it: read what is on this "
      'server, then propose a profile with iris_profile_propose and templates '
      'and reply kits with iris_template_propose. Propose only; do not show '
      'anything with iris_ui, and finish with a short summary in text.';

  ChatController? _chat;
  Timer? _timer;
  bool _sawRunning = false;
  bool _disposed = false;
  bool _started = false;

  /// Makes the chat and sends the request. A second call does nothing.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _set(value.copyWith(phase: StudyPhase.starting));
    final chat = _chat = ChatController(_backend, title: chatTitle);
    chat.addListener(_onChat);
    await chat.open();
    await chat.send(prompt, literal: true);
    if (_disposed) return;
    final id = chat.conversationId;
    if (id == null) {
      _fail(
        _lastError(chat.value) ?? 'Iris could not start a chat to study in.',
      );
      return;
    }
    // The chat is named after it exists; a refusal is not worth stopping for.
    unawaited(chat.rename(chatTitle));
    _set(value.copyWith(phase: StudyPhase.working, conversationId: id));
    _timer = Timer.periodic(pollEvery, (_) => unawaited(refresh()));
    unawaited(refresh());
    _onChat();
  }

  /// Asks the plugin what has been proposed so far.
  Future<void> refresh() async {
    final profile = await _api.workProfile();
    final templates = await _api.templates(status: PersonalStatus.proposed);
    if (_disposed) return;
    final found = templates.valueOrNull ?? const <UiTemplate>[];
    _set(
      value.copyWith(
        profileProposed: profile.valueOrNull?.status == PersonalStatus.proposed,
        proposedTemplates: found.length,
        proposedKits: found
            .where((t) => t.kind == TemplateKind.replyKit)
            .length,
      ),
    );
  }

  void _onChat() {
    final chat = _chat;
    if (chat == null || _disposed || value.phase != StudyPhase.working) return;
    final state = chat.value;
    if (state.running) {
      _sawRunning = true;
      return;
    }
    if (!_sawRunning) return;
    final error = _lastError(state);
    if (error != null) {
      _fail(error);
    } else {
      unawaited(_finish());
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    await refresh();
    if (_disposed) return;
    _set(value.copyWith(phase: StudyPhase.done));
  }

  void _fail(String message) {
    _timer?.cancel();
    _set(value.copyWith(phase: StudyPhase.failed, message: message));
  }

  /// The words of the newest error notice in the chat, if the last thing in it is one.
  static String? _lastError(ChatState state) {
    for (final item in state.items.reversed) {
      if (item is Notice && item.isError) return item.text;
      if (item is AssistantTurn) return null;
    }
    return null;
  }

  void _set(StudyState next) {
    if (!_disposed) value = next;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _chat
      ?..removeListener(_onChat)
      ..dispose();
    super.dispose();
  }
}
