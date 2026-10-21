/// Asking for the microphone, in two parts (frames A3a and A3b): a primer
/// before the system's own prompt, so the person knows why, and a plain
/// "it is off" sheet once access is refused or has been turned off.
library;

import 'package:flutter/widgets.dart';
import '../../app/preferences.dart';
import '../../app/scope.dart';
import '../../data/prefs/preferences_store.dart';
import '../../design/components/controls.dart';
import '../../design/components/iris_voice_orb.dart';
import '../../design/components/sheet.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'mic_permission.dart';

enum MicAccess { granted, denied }

/// Makes sure Iris may use the microphone, asking in the right order, and
/// says which way it went.
///
/// - Already allowed: [MicAccess.granted], no sheet.
/// - Never asked: the primer (A3a). "Allow microphone" is the only thing that
///   shows the system prompt. A refusal there goes on to A3b.
/// - Asked before and not allowed (refused, or turned off in system
///   Settings since): A3b, whose one action opens Settings.
///
/// Outside a provider scope there is nothing to ask with, so this answers
/// [MicAccess.granted] and leaves the recorder to refuse in its own way.
Future<MicAccess> ensureMicAccess(BuildContext context) async {
  final container = maybeProviderContainer(context);
  if (container == null) return MicAccess.granted;

  final permission = container.read(micPermissionProvider);
  if (await permission.status() == MicStatus.granted) return MicAccess.granted;
  if (!context.mounted) return MicAccess.denied;

  final preferences = container.read(preferencesProvider.notifier);
  final asked =
      container.read(preferencesProvider)[('', PreferenceKeys.voiceMicAsked)] ==
      'true';

  if (!asked) {
    final allow = await showIrisSheet<bool>(
      context: context,
      builder: (_) => const _MicSheet.primer(),
    );
    if (allow != true || !context.mounted) return MicAccess.denied;
    preferences.set('', PreferenceKeys.voiceMicAsked, 'true');
    if (await permission.request() == MicStatus.granted) {
      return MicAccess.granted;
    }
    if (!context.mounted) return MicAccess.denied;
  }

  final openSettings = await showIrisSheet<bool>(
    context: context,
    builder: (_) => const _MicSheet.denied(),
  );
  if (openSettings == true) await permission.openSettings();
  return MicAccess.denied;
}

/// A3a and A3b share a layout: the orb, a serif line, a reason, and a primary
/// action over a quiet "Not now".
class _MicSheet extends StatelessWidget {
  const _MicSheet.primer() : denied = false;
  const _MicSheet.denied() : denied = true;

  final bool denied;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    return IrisSheet(
      actions: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IrisButton(
            label: denied ? 'Open Settings' : 'Allow microphone',
            tone: IrisButtonTone.primary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: IrisSpace.sm),
          IrisButton(
            label: 'Not now',
            tone: IrisButtonTone.ghost,
            expand: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: IrisSpace.md),
          IrisVoiceOrb(
            mode: denied ? VoiceOrbMode.muted : VoiceOrbMode.listening,
            size: 96,
          ),
          const SizedBox(height: IrisSpace.md),
          Text(
            denied ? 'The microphone is off' : 'Iris needs your microphone',
            textAlign: TextAlign.center,
            style: theme.typography.serif.copyWith(
              fontSize: 30,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: IrisSpace.sm),
          Text(
            denied
                ? 'Iris can’t hear you because access is blocked. Turn it on '
                      'in Settings to dictate or talk.'
                : 'Used only while you dictate or talk. Audio goes to your own '
                      'Hermes server.',
            textAlign: TextAlign.center,
            style: theme.typography.body.copyWith(
              fontSize: 14.5,
              color: palette.inkMuted,
            ),
          ),
          if (denied) ...[
            const SizedBox(height: IrisSpace.md),
            Text(
              'Settings › Iris › Microphone',
              textAlign: TextAlign.center,
              style: theme.typography.codeSmall.copyWith(
                fontSize: 11.5,
                color: palette.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
