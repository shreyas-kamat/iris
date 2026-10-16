/// Plays a demo script as the events a Hermes gateway sends.
///
/// The chat screen cannot tell the difference: it receives the same
/// `ChatEvent`s, in the same order, as from a real turn. Everything that
/// finishes is also handed to [ScriptPlayer.record], so the conversation's
/// stored history matches what was shown.
library;

import 'dart:async';
import 'dart:math' as math;

import '../core/json.dart';
import '../data/chat/chat_event.dart';
import '../data/chat/chat_models.dart';
import '../data/chat/connection_models.dart';
import 'demo_script.dart';

typedef Delay = Future<void> Function(Duration duration);

Future<void> realDelay(Duration duration) => Future<void>.delayed(duration);

final class ScriptPlayer {
  ScriptPlayer({
    required this.sessionId,
    required this.emit,
    required this.record,
    Delay delay = realDelay,
  }) : _delay = delay;

  final String sessionId;
  final void Function(ChatEvent event) emit;
  final void Function(TranscriptItem item) record;
  final Delay _delay;

  static const _textChunk = 40;
  static const _textTick = Duration(milliseconds: 30);
  static const _thinkChunk = 12;
  static const _thinkTick = Duration(milliseconds: 40);

  bool _running = false;
  bool _stopped = false;
  int _serial = 0;
  String _reasoning = '';
  final List<String> _steers = [];
  Completer<bool>? _approval;
  String? _approvalId;
  Completer<void>? _secret;
  String? _secretId;

  bool get running => _running;

  Future<void> play(List<DemoStep> steps) async {
    _running = true;
    _stopped = false;
    emit(BusyChanged(sessionId, busy: true));
    final finished = await _run(steps);
    if (_stopped) return;
    if (finished && _steers.isNotEmpty) await _say('');
    if (_stopped) return;
    _flushReasoning();
    _running = false;
    emit(BusyChanged(sessionId, busy: false));
  }

  /// Plays [steps]; false if the turn ended early, by a stop or a failure.
  Future<bool> _run(List<DemoStep> steps) async {
    for (final step in steps) {
      if (_stopped) return false;
      switch (step) {
        case ThinkStep(:final text):
          for (final chunk in _chunks('$text\n', _thinkChunk)) {
            if (_stopped) return false;
            _reasoning += chunk;
            emit(ReasoningDelta(sessionId, chunk));
            await _delay(_thinkTick);
          }
        case ToolStep():
          _flushReasoning();
          final id = '$sessionId-tool-${_serial++}';
          emit(
            ToolStarted(
              sessionId,
              name: step.name,
              toolId: id,
              input: step.input,
            ),
          );
          await _delay(step.duration);
          if (_stopped) return false;
          emit(
            ToolCompleted(
              sessionId,
              name: step.name,
              toolId: id,
              output: step.output,
              failed: step.failed,
            ),
          );
          record(
            ToolCall(
              id: id,
              name: step.name,
              arguments: step.input,
              output: step.output,
              status: step.failed ? ToolStatus.failed : ToolStatus.done,
            ),
          );
        case ApprovalStep():
          _flushReasoning();
          final id = '$sessionId-approval-${_serial++}';
          final answer = _approval = Completer<bool>();
          _approvalId = id;
          emit(
            ApprovalAsked(
              ApprovalRequest(
                sessionId: sessionId,
                command: step.command,
                description: step.description,
                choices: const ['once', 'deny'],
                queueId: id,
              ),
            ),
          );
          final approved = await answer.future;
          _approval = null;
          _approvalId = null;
          if (_stopped) return false;
          if (!await _run(approved ? step.ifApproved : step.ifDenied)) {
            return false;
          }
        case SecretStep(:final command):
          final id = '$sessionId-input-${_serial++}';
          final answer = _secret = Completer<void>();
          _secretId = id;
          emit(
            InputAsked(
              InputRequest(
                requestId: id,
                sessionId: sessionId,
                kind: InputKind.sudo,
                command: command,
              ),
            ),
          );
          await answer.future;
          _secret = null;
          _secretId = null;
          if (_stopped) return false;
        case VaultStep(:final kind, :final name, :final site, :final hint):
          final id = '$sessionId-vault-${_serial++}';
          final answer = _secret = Completer<void>();
          _secretId = id;
          emit(switch (kind) {
            VaultKind.unlock => InputAsked(
              InputRequest(
                requestId: id,
                sessionId: sessionId,
                kind: InputKind.vaultUnlock,
                displayName: name,
              ),
            ),
            VaultKind.code => InputAsked(
              InputRequest(
                requestId: id,
                sessionId: sessionId,
                kind: InputKind.vaultCode,
                site: site,
                hint: hint,
              ),
            ),
            VaultKind.login => LoginAsked(
              LoginRequest(
                requestId: id,
                sessionId: sessionId,
                origin: 'https://${site.toLowerCase()}.com',
                site: site,
              ),
            ),
          });
          await answer.future;
          _secret = null;
          _secretId = null;
          if (_stopped) return false;
        case ConnectStep(:final targets):
          final id = '$sessionId-connect-${_serial++}';
          final answer = _secret = Completer<void>();
          _secretId = id;
          final request = ConnectionRequest.parse(
            Json.of({'op_id': id, 'timeout_seconds': 300, 'targets': targets}),
            sessionId: sessionId,
          );
          if (request != null) emit(ConnectionAsked(request));
          await answer.future;
          _secret = null;
          _secretId = null;
          if (_stopped) return false;
        case SayStep(:final markdown):
          await _say(markdown);
          if (_stopped) return false;
        case ContextStep(:final percent):
          emit(
            ContextChanged(
              sessionId,
              ContextUsage(
                percent: percent,
                used: (percent / 100 * 200000).round(),
                max: 200000,
              ),
            ),
          );
        case FailStep(:final message):
          _flushReasoning();
          emit(TurnFailed(sessionId, message));
          record(
            Notice(
              id: '$sessionId-failed-${_serial++}',
              text: message,
              isError: true,
              retryable: true,
            ),
          );
          return false;
      }
    }
    return true;
  }

  Future<void> _say(String markdown) async {
    final notes = [for (final steer in _steers) '_Noted: $steer._'];
    _steers.clear();
    final text = [...notes, if (markdown.isNotEmpty) markdown].join('\n\n');
    if (text.isEmpty) return;
    emit(MessageStarted(sessionId));
    for (final chunk in _chunks(text, _textChunk)) {
      if (_stopped) return;
      emit(TextDelta(sessionId, chunk));
      await _delay(_textTick);
    }
    if (_stopped) return;
    final reasoning = _reasoning.trim();
    emit(
      MessageCompleted(
        sessionId,
        content: text,
        reasoning: reasoning.isEmpty ? null : reasoning,
      ),
    );
    record(
      AssistantTurn(
        id: '$sessionId-reply-${_serial++}',
        text: text,
        reasoning: reasoning,
      ),
    );
    _reasoning = '';
  }

  /// Thinking with no reply after it yet is kept as its own entry.
  void _flushReasoning() {
    final reasoning = _reasoning.trim();
    if (reasoning.isEmpty) return;
    record(
      AssistantTurn(
        id: '$sessionId-thought-${_serial++}',
        text: '',
        reasoning: reasoning,
      ),
    );
    _reasoning = '';
  }

  /// Stops the turn, as the Stop button does.
  void stop() {
    if (!_running || _stopped) return;
    _stopped = true;
    if (_approvalId case final id?) emit(RequestWithdrawn(sessionId, id));
    if (_secretId case final id?) emit(RequestWithdrawn(sessionId, id));
    _release();
    _reasoning = '';
    emit(TurnInterrupted(sessionId));
    record(Notice(id: '$sessionId-stopped-${_serial++}', text: 'Stopped.'));
    _running = false;
    emit(BusyChanged(sessionId, busy: false));
  }

  void answerApproval({required bool approved}) {
    final answer = _approval;
    if (answer != null && !answer.isCompleted) answer.complete(approved);
  }

  /// Continues after a sudo prompt. The value typed is never passed here.
  void answerSecret() {
    final answer = _secret;
    if (answer != null && !answer.isCompleted) answer.complete();
  }

  /// Notes [text] for the reply being written. False if no turn is running.
  bool steer(String text) {
    if (!_running) return false;
    _steers.add(text);
    return true;
  }

  /// Ends playback silently, for when the demo closes.
  void dispose() {
    _stopped = true;
    _running = false;
    _release();
  }

  void _release() {
    final approval = _approval;
    if (approval != null && !approval.isCompleted) approval.complete(false);
    final secret = _secret;
    if (secret != null && !secret.isCompleted) secret.complete();
  }

  static Iterable<String> _chunks(String text, int size) sync* {
    for (var start = 0; start < text.length; start += size) {
      yield text.substring(start, math.min(start + size, text.length));
    }
  }
}
