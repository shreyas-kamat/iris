/// The live voice screen (frames B1 to B10b, B2b, D3a, D3b): one orb, one line
/// of status and one calm layer of detail over the call's controls.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/voice_providers.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_voice_orb.dart';
import '../../design/components/primitives.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'screen_awake.dart';
import 'spoken.dart';
import 'tool_trail.dart';
import 'voice_call.dart';
import 'voice_controls.dart';
import 'voice_decision_card.dart';

/// How the call screen was left.
enum VoiceCallExit {
  /// The call is over; back to the chat.
  done,

  /// The person asked to start another (B10b's Call again).
  again,
}

/// Pushes the call screen. Leaving it by any route ends the call; the result
/// says whether to start another.
Future<VoiceCallExit> openVoiceCall(
  BuildContext context, {
  required VoiceCall call,
  ScreenAwake awake = const WakelockScreenAwake(),
}) async {
  final exit = await Navigator.of(context).push<VoiceCallExit>(
    IrisPageRoute<VoiceCallExit>(
      builder: (_) => VoiceCallScreen(call: call, awake: awake),
    ),
  );
  return exit ?? VoiceCallExit.done;
}

/// "01:48", or "1:02:03" past the hour.
String callClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = two(d.inSeconds % 60);
  if (d.inHours > 0) return '${d.inHours}:${two(d.inMinutes % 60)}:$seconds';
  return '${two(d.inMinutes)}:$seconds';
}

/// The thinking and tool clocks appear once the wait is long enough to matter.
const _showClockAfter = Duration(seconds: 10);

/// Below this width the orb shrinks so the controls keep their room.
const _narrow = 360.0;

/// What a state says: the mono status, the serif line, and a helper under it.
@immutable
final class CallCopy {
  const CallCopy(this.status, this.line, [this.help]);

  final String status;
  final String line;
  final String? help;
}

String _stepCopy(PreflightStep step) => switch (step) {
  PreflightStep.agent => 'Checking the agent…',
  PreflightStep.speechToText => 'Checking speech-to-text…',
  PreflightStep.textToSpeech => 'Checking text-to-speech…',
  PreflightStep.gptLive => 'Starting GPT-Live…',
};

/// The words for [state]. [reconnectingFor] is how long the link has been
/// down.
CallCopy callCopy(
  VoiceCallState state, {
  required String server,
  Duration reconnectingFor = Duration.zero,
}) {
  String withClock(String status) {
    final working = state.workingFor;
    return working == null || working < _showClockAfter
        ? status
        : '$status · ${callClock(working)}';
  }

  final holdToTalk = state.style == CallStyle.pushToTalk;
  return switch (state.mode) {
    CallMode.connecting => CallCopy(
      'CONNECTING',
      'Connecting to $server…',
      state.step == null ? 'This takes a moment.' : _stepCopy(state.step!),
    ),
    CallMode.listening when holdToTalk && !state.muted => const CallCopy(
      'PUSH TO TALK',
      'Hold the button to speak.',
      'Let go when you’re done and Iris will answer.',
    ),
    CallMode.listening => const CallCopy(
      'LISTENING',
      'I’m listening.',
      'Just start talking.',
    ),
    CallMode.hearing => CallCopy(
      'HEARING YOU',
      holdToTalk ? 'Let go when you’re done.' : 'Pause when you’re done.',
    ),
    CallMode.thinking => CallCopy(
      withClock('THINKING'),
      'Working on it.',
      'This can take a few minutes. You can lock your screen; I’ll keep going.',
    ),
    CallMode.tool => CallCopy(withClock('RUNNING A TOOL'), 'Looking that up.'),
    CallMode.speaking => const CallCopy(
      'SPEAKING',
      'Talk any time to interrupt.',
    ),
    CallMode.interrupted => const CallCopy(
      'INTERRUPTED · LISTENING',
      'Go on.',
      'Iris stopped mid-sentence and is listening.',
    ),
    CallMode.muted => const CallCopy(
      'MUTED',
      'Your mic is off.',
      'Iris can’t hear you. Replies still play.',
    ),
    CallMode.needs => switch (state.decision) {
      final ApprovalDecision approval => CallCopy(
        'NEEDS YOUR OK',
        approval.prompt,
        'Say “approve” or “deny”, or tap.',
      ),
      final QuestionDecision question => CallCopy(
        'IRIS ASKS',
        question.prompt,
        'Say your answer, or tap one.',
      ),
      null => const CallCopy(
        'NEEDS YOUR OK',
        'Iris is waiting for you.',
        'Answer in the chat, or say what you’d like.',
      ),
    },
    CallMode.reconnecting => CallCopy(
      'RECONNECTING · ${callClock(reconnectingFor)}',
      'Connection lost.',
      'Trying again. Your call is paused and nothing is lost.',
    ),
    CallMode.paused when state.paused == PauseReason.unplugged =>
      const CallCopy(
        'PAUSED',
        'Headphones unplugged.',
        'I paused so the reply doesn’t play out loud by surprise. Resume on '
            'the speaker, or plug them back in.',
      ),
    CallMode.paused => const CallCopy(
      'CALL PAUSED',
      'A phone call interrupted us.',
      'Iris stopped listening so the call could use the microphone. Carry on '
          'when you’re ready.',
    ),
    CallMode.error || CallMode.ended => CallCopy(
      'CALL ENDED',
      state.failure ?? 'The call ended unexpectedly.',
      'Your conversation so far is saved in the chat. Start again whenever '
          'you’re ready.',
    ),
  };
}

VoiceOrbMode _orbMode(VoiceCallState state) => switch (state.mode) {
  CallMode.connecting => VoiceOrbMode.connecting,
  CallMode.listening =>
    state.style == CallStyle.pushToTalk && !state.muted
        ? VoiceOrbMode.idle
        : VoiceOrbMode.listening,
  CallMode.hearing => VoiceOrbMode.hearing,
  CallMode.thinking => VoiceOrbMode.thinking,
  CallMode.tool => VoiceOrbMode.tool,
  CallMode.speaking => VoiceOrbMode.speaking,
  CallMode.interrupted => VoiceOrbMode.interrupted,
  CallMode.muted => VoiceOrbMode.muted,
  CallMode.needs => VoiceOrbMode.needs,
  CallMode.reconnecting => VoiceOrbMode.offline,
  CallMode.paused || CallMode.ended => VoiceOrbMode.idle,
  CallMode.error => VoiceOrbMode.error,
};

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({required this.call, required this.awake, super.key});

  final VoiceCall call;
  final ScreenAwake awake;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  bool _leaving = false;

  /// The call clock when the link went down, to count the outage from.
  Duration? _downSince;

  /// The last headset seen, so D3b can say what the route was.
  String? _lastHeadset;

  @override
  void initState() {
    super.initState();
    unawaited(widget.awake.hold());
    widget.call.addListener(_changed);
    _track(widget.call.value);
  }

  @override
  void dispose() {
    widget.call.removeListener(_changed);
    unawaited(widget.awake.release());
    // Leaving by any route ends the call; there is no minimised call.
    unawaited(widget.call.end());
    super.dispose();
  }

  void _track(VoiceCallState state) {
    if (state.route.headset != null) _lastHeadset = state.route.headset;
    if (state.mode == CallMode.reconnecting) {
      _downSince ??= state.elapsed;
    } else {
      _downSince = null;
    }
  }

  void _changed() {
    _track(widget.call.value);
    // A call that ends from outside (a stop phrase, the notification's End)
    // takes the screen with it.
    if (widget.call.value.mode == CallMode.ended) unawaited(_leave());
  }

  Future<void> _leave([VoiceCallExit exit = VoiceCallExit.done]) async {
    if (_leaving) return;
    _leaving = true;
    await widget.call.end();
    if (mounted) Navigator.of(context).pop(exit);
  }

  Future<void> _resume({required bool onSpeaker}) async {
    if (onSpeaker) await widget.call.setSpeaker(on: true);
    await widget.call.resume();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: SafeArea(
          child: ValueListenableBuilder<VoiceCallState>(
            valueListenable: widget.call,
            builder: (context, state, _) => _body(context, state),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, VoiceCallState state) {
    final over = state.mode == CallMode.error || state.mode == CallMode.ended;
    final paused = state.mode == CallMode.paused;
    final copy = callCopy(
      state,
      server: widget.call.server,
      reconnectingFor: _downSince == null
          ? Duration.zero
          : state.elapsed - _downSince!,
    );
    final holdable =
        state.style == CallStyle.pushToTalk &&
        !state.muted &&
        const {
          CallMode.listening,
          CallMode.hearing,
          CallMode.thinking,
          CallMode.tool,
          CallMode.speaking,
          CallMode.interrupted,
        }.contains(state.mode);

    return Column(
      children: [
        _Header(
          title: widget.call.title,
          clock: callClock(state.elapsed),
          style: state.style,
          interactive: !over,
          onBack: _leave,
          onStyle: () => unawaited(
            widget.call.setStyle(
              state.style == CallStyle.handsFree
                  ? CallStyle.pushToTalk
                  : CallStyle.handsFree,
            ),
          ),
        ),
        Expanded(
          child: _Stage(
            state: state,
            copy: copy,
            routeWas: paused && state.paused == PauseReason.unplugged
                ? _lastHeadset
                : null,
            onRetry: () => unawaited(widget.call.retryHeld()),
            onApprove: (verdict) {
              if (state.decision case final ApprovalDecision approval) {
                unawaited(widget.call.approve(approval.request, verdict));
              }
            },
            onAnswer: (answer) {
              if (state.decision case final QuestionDecision question) {
                unawaited(
                  widget.call.answerQuestion(
                    question.request,
                    question.question,
                    answer,
                  ),
                );
              }
            },
          ),
        ),
        if (holdable)
          HoldToTalk(
            active: state.mode == CallMode.hearing,
            onHold: ({required down}) =>
                unawaited(widget.call.hold(down: down)),
          ),
        if (over)
          _Actions(
            primary: 'Call again',
            onPrimary: () => unawaited(_leave(VoiceCallExit.again)),
            secondary: 'Back to chat',
            onSecondary: () => unawaited(_leave()),
          )
        else if (paused)
          _Actions(
            primary: state.paused == PauseReason.unplugged
                ? 'Resume on speaker'
                : 'Resume',
            onPrimary: () => unawaited(
              _resume(onSpeaker: state.paused == PauseReason.unplugged),
            ),
            secondary: state.paused == PauseReason.unplugged
                ? 'End call'
                : 'End',
            onSecondary: () => unawaited(_leave()),
          )
        else
          CallControlsRow(
            muted: state.muted,
            captions: state.captions,
            route: state.route,
            dimmed: state.mode == CallMode.reconnecting,
            onMute: () => unawaited(widget.call.setMuted(muted: !state.muted)),
            onCaptions: widget.call.toggleCaptions,
            onRoute: () =>
                unawaited(widget.call.setSpeaker(on: !state.route.speaker)),
            onEnd: () => unawaited(_leave()),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.clock,
    required this.style,
    required this.interactive,
    required this.onBack,
    required this.onStyle,
  });

  final String title;
  final String clock;
  final CallStyle style;
  final bool interactive;
  final VoidCallback onBack;
  final VoidCallback onStyle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IrisSpace.md,
          vertical: IrisSpace.xs,
        ),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'End call and go back',
              excludeSemantics: true,
              onTap: onBack,
              child: IrisPressable(
                onTap: onBack,
                ensureTapTarget: false,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.surface,
                    border: Border.all(color: palette.line),
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: palette.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: IrisSpace.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.codeSmall.copyWith(
                      fontSize: 10,
                      letterSpacing: 10 * .12,
                      color: palette.inkMuted,
                    ),
                  ),
                  Text(
                    clock,
                    style: type.codeSmall.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: IrisSpace.sm),
            Semantics(
              button: true,
              enabled: interactive,
              label: style == CallStyle.handsFree
                  ? 'Hands-free. Switch to push to talk'
                  : 'Push to talk. Switch to hands-free',
              excludeSemantics: true,
              onTap: interactive ? onStyle : null,
              child: IrisPressable(
                onTap: interactive ? onStyle : null,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: palette.surface,
                    border: Border.all(color: palette.line),
                  ),
                  child: Text(
                    style == CallStyle.handsFree
                        ? 'Hands-free'
                        : 'Push to talk',
                    style: type.label.copyWith(
                      fontSize: 12,
                      color: palette.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The middle: the orb over its words, scrolling when text outgrows the room.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.state,
    required this.copy,
    required this.routeWas,
    required this.onRetry,
    required this.onApprove,
    required this.onAnswer,
  });

  final VoiceCallState state;
  final CallCopy copy;
  final String? routeWas;
  final VoidCallback onRetry;
  final void Function(SpokenVerdict verdict) onApprove;
  final void Function(String answer) onAnswer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    final mode = _orbMode(state);
    final size = MediaQuery.sizeOf(context).width < _narrow ? 168.0 : 232.0;
    final accent = palette.voiceOrbColor(mode);

    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: size + 16,
                    child: Center(
                      child: IrisVoiceOrb(
                        mode: mode,
                        size: size,
                        level: state.level,
                        semanticLabel: copy.status,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    copy.status,
                    textAlign: TextAlign.center,
                    style: type.codeSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 12 * .14,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    copy.line,
                    textAlign: TextAlign.center,
                    style: type.serif.copyWith(
                      fontSize: 28,
                      height: 1.15,
                      fontStyle: FontStyle.italic,
                      color: palette.ink,
                    ),
                  ),
                  if (copy.help != null) ...[
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        copy.help!,
                        textAlign: TextAlign.center,
                        style: type.body.copyWith(
                          fontSize: 14.5,
                          height: 1.5,
                          color: palette.inkMuted,
                        ),
                      ),
                    ),
                  ],
                  if (state.mode == CallMode.needs &&
                      state.decision != null) ...[
                    const SizedBox(height: IrisSpace.lg),
                    VoiceDecisionCard(
                      decision: state.decision!,
                      onApprove: onApprove,
                      onAnswer: onAnswer,
                    ),
                  ],
                  if (state.mode == CallMode.interrupted) ...[
                    const SizedBox(height: 14),
                    const _CutStrip(),
                  ],
                  if (state.mode == CallMode.tool && state.tool != null) ...[
                    const SizedBox(height: 14),
                    ToolPill(tool: state.tool!),
                  ],
                  if (state.mode == CallMode.tool ||
                      state.mode == CallMode.thinking)
                    ToolTrail(tools: state.toolTrail),
                  if (routeWas != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Route was $routeWas',
                      style: type.codeSmall.copyWith(
                        fontSize: 11.5,
                        color: palette.inkMuted,
                      ),
                    ),
                  ],
                  if (state.heldTake && state.mode == CallMode.listening) ...[
                    const SizedBox(height: 14),
                    IrisButton(label: 'Try again', onPressed: onRetry),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// B7's strip: speaking, 120 ms later the cut, then hearing.
class _CutStrip extends StatelessWidget {
  const _CutStrip();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CutStep(VoiceOrbMode.speaking, '0 ms', 'speaking', .8),
            _chevron(palette.inkFaint),
            const _CutStep(VoiceOrbMode.interrupted, '120 ms', 'cut', .5),
            _chevron(palette.inkFaint),
            const _CutStep(VoiceOrbMode.hearing, '300 ms', 'hearing', .6),
          ],
        ),
      ),
    );
  }

  static Widget _chevron(Color color) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Icon(Icons.chevron_right, size: 14, color: color),
  );
}

class _CutStep extends StatelessWidget {
  const _CutStep(this.mode, this.time, this.name, this.level);

  final VoiceOrbMode mode;
  final String time;
  final String name;
  final double level;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          IrisVoiceOrb(
            mode: mode,
            size: 64,
            still: true,
            level: ValueNotifier(level),
          ),
          const SizedBox(height: IrisSpace.xs),
          Text(
            time,
            style: type.codeSmall.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: palette.ink,
            ),
          ),
          Text(
            name,
            style: type.codeSmall.copyWith(
              fontSize: 10,
              color: palette.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// B10b, D3a and D3b swap the controls for two actions.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
  });

  final String primary;
  final VoidCallback onPrimary;
  final String secondary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IrisSpace.lg,
        IrisSpace.sm,
        IrisSpace.lg,
        IrisSpace.xl,
      ),
      // Button labels stop growing at 130%, as the call controls' do, so a
      // long one never outruns the button at 200% text.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IrisButton(
              label: primary,
              tone: IrisButtonTone.primary,
              expand: true,
              onPressed: onPrimary,
            ),
            const SizedBox(height: 10),
            IrisButton(label: secondary, expand: true, onPressed: onSecondary),
          ],
        ),
      ),
    );
  }
}
