/// The call screen's bottom controls: mute, captions, route and end, and the
/// push-to-talk hold button (frames B1 to B10b, B2b).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/components/primitives.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'audio/audio_route.dart';

/// Call controls are bigger than the usual 44: they are used without looking.
const double callControlSize = 56;

/// Chrome labels stop growing here, so a row of four fits at 200% text.
const double _labelScaleCap = 1.3;

/// One round control with its label beneath: [solid] fills it (muted, captions
/// on), [dimmed] fades it and ignores taps.
class CallControl extends StatelessWidget {
  const CallControl({
    required this.controlKey,
    required this.icon,
    required this.label,
    required this.semantic,
    required this.onTap,
    this.solid = false,
    this.dimmed = false,
    super.key,
  });

  final String controlKey;
  final IconData icon;

  /// The uppercase line beneath.
  final String label;

  /// What a screen reader says.
  final String semantic;
  final VoidCallback? onTap;
  final bool solid;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null && !dimmed;
    return Opacity(
      opacity: dimmed ? .4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            enabled: enabled,
            label: semantic,
            excludeSemantics: true,
            onTap: enabled ? onTap : null,
            child: IrisPressable(
              onTap: enabled ? onTap : null,
              ensureTapTarget: false,
              child: Container(
                key: ValueKey('call-$controlKey'),
                width: callControlSize,
                height: callControlSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: solid ? palette.ink : palette.surface,
                  border: Border.all(
                    color: solid ? palette.ink : palette.lineStrong,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: solid ? palette.canvas : palette.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: IrisSpace.sm),
          _ControlLabel(label),
        ],
      ),
    );
  }
}

class _ControlLabel extends StatelessWidget {
  const _ControlLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _labelScaleCap,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: context.type.codeSmall.copyWith(
          fontSize: 10.5,
          letterSpacing: 10.5 * .1,
          color: context.palette.inkMuted,
        ),
      ),
    );
  }
}

/// The red End pill, a third wider than the round controls.
class EndControl extends StatelessWidget {
  const EndControl({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'End call',
          excludeSemantics: true,
          onTap: onTap,
          child: IrisPressable(
            onTap: onTap,
            ensureTapTarget: false,
            child: Container(
              key: const ValueKey('call-end'),
              constraints: const BoxConstraints(maxWidth: 104),
              width: double.infinity,
              height: callControlSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.danger,
                borderRadius: BorderRadius.circular(callControlSize / 2),
              ),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: _labelScaleCap,
                child: Text(
                  'End',
                  style: context.type.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.onDanger,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: IrisSpace.sm),
        const _ControlLabel('END CALL'),
      ],
    );
  }
}

/// What the route control says: the headset's name when one is in, otherwise
/// the loudspeaker or the earpiece.
String routeLabel(RouteInfo route) =>
    (route.headset ?? (route.speaker ? 'Speaker' : 'Earpiece')).toUpperCase();

IconData routeIcon(RouteInfo route) => route.headset != null
    ? Icons.headphones
    : route.speaker
    ? Icons.volume_up_outlined
    : Icons.phone_in_talk_outlined;

/// The row of four. Mute and captions are dimmed while the call cannot hear
/// anyone (reconnecting, paused).
class CallControlsRow extends StatelessWidget {
  const CallControlsRow({
    required this.muted,
    required this.captions,
    required this.route,
    required this.dimmed,
    required this.onMute,
    required this.onCaptions,
    required this.onRoute,
    required this.onEnd,
    super.key,
  });

  final bool muted;
  final bool captions;
  final RouteInfo route;
  final bool dimmed;
  final VoidCallback onMute;
  final VoidCallback onCaptions;
  final VoidCallback onRoute;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IrisSpace.lg,
        IrisSpace.sm,
        IrisSpace.lg,
        IrisSpace.xxl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: CallControl(
              controlKey: 'mute',
              icon: muted ? Icons.mic_off_outlined : Icons.mic_none,
              label: muted ? 'UNMUTE' : 'MUTE',
              semantic: muted ? 'Unmute' : 'Mute',
              solid: muted,
              dimmed: dimmed,
              onTap: onMute,
            ),
          ),
          Expanded(
            flex: 2,
            child: CallControl(
              controlKey: 'captions',
              icon: Icons.closed_caption_outlined,
              label: 'CAPTIONS',
              semantic: captions ? 'Hide captions' : 'Show captions',
              solid: captions,
              dimmed: dimmed,
              onTap: onCaptions,
            ),
          ),
          Expanded(
            flex: 2,
            child: CallControl(
              controlKey: 'route',
              icon: routeIcon(route),
              label: routeLabel(route),
              semantic: 'Audio output: ${routeLabel(route).toLowerCase()}',
              onTap: route.headset != null ? null : onRoute,
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(child: EndControl(onTap: onEnd)),
          ),
        ],
      ),
    );
  }
}

/// B2b's big button: audio goes while it is held, and is sent on release.
class HoldToTalk extends StatefulWidget {
  const HoldToTalk({required this.onHold, required this.active, super.key});

  /// Called with true on press and false on release or cancel.
  final void Function({required bool down}) onHold;

  /// The mic is open for this hold.
  final bool active;

  @override
  State<HoldToTalk> createState() => _HoldToTalkState();
}

class _HoldToTalkState extends State<HoldToTalk> {
  bool _down = false;

  void _set({required bool down}) {
    if (_down == down) return;
    _down = down;
    if (down) HapticFeedback.selectionClick();
    widget.onHold(down: down);
    setState(() {});
  }

  @override
  void dispose() {
    if (_down) widget.onHold(down: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lit = _down || widget.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(IrisSpace.lg, 0, IrisSpace.lg, 8),
      child: Semantics(
        button: true,
        label: 'Hold to talk',
        excludeSemantics: true,
        child: Listener(
          onPointerDown: (_) => _set(down: true),
          onPointerUp: (_) => _set(down: false),
          onPointerCancel: (_) => _set(down: false),
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lit ? palette.accent : palette.accentQuiet,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: palette.accent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_none,
                  size: 20,
                  color: lit ? palette.accentInk : palette.accent,
                ),
                const SizedBox(width: 10),
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _labelScaleCap,
                  child: Text(
                    'Hold to talk',
                    style: context.type.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: lit ? palette.accentInk : palette.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
