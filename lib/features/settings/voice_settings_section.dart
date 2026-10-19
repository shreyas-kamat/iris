/// The Voice group in Settings (frames E1a and E1b): how this device likes
/// calls, and the voice the server speaks with.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/voice_providers.dart';
import '../../core/result.dart';
import '../../data/voice/voice_capabilities.dart';
import '../../data/voice/voice_catalog.dart';
import '../../design/components/controls.dart';
import '../../design/components/segmented.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/toast.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import '../chat/chat_controller.dart';
import 'voice_picker_sheet.dart';

/// The voices to offer for what the server is set up with: Iris's own list
/// for the providers it knows, the server's for ElevenLabs, none otherwise.
final voiceChoicesProvider = FutureProvider.autoDispose<List<VoiceChoice>>((
  ref,
) async {
  final caps = await ref.watch(voiceCapabilitiesProvider.future);
  final built = builtInVoices(caps.engine, caps.ttsProvider);
  if (built.isNotEmpty) return built;
  if (caps.engine == VoiceEngine.chained && caps.ttsProvider == 'elevenlabs') {
    final backend = await ref.watch(activeVoiceProvider.future);
    return (await backend?.serverVoices())?.valueOrNull ?? const [];
  }
  return const [];
});

String _callStyleLabel(CallStyle style) => switch (style) {
  CallStyle.handsFree => 'Hands-free',
  CallStyle.pushToTalk => 'Push to talk',
};

class VoiceSettingsSection extends ConsumerStatefulWidget {
  const VoiceSettingsSection({super.key});

  @override
  ConsumerState<VoiceSettingsSection> createState() =>
      _VoiceSettingsSectionState();
}

class _VoiceSettingsSectionState extends ConsumerState<VoiceSettingsSection> {
  @override
  void initState() {
    super.initState();
    // The server's voice setup is read again whenever Settings opens, so a
    // change made elsewhere shows up.
    unawaited(
      Future<void>.microtask(() {
        if (mounted) ref.invalidate(voiceCapabilitiesProvider);
      }),
    );
  }

  Future<void> _pick(VoiceCapabilities caps, List<VoiceChoice> choices) async {
    final key = caps.voiceKey;
    if (key == null) return;
    final server = _host();
    final picked = await showVoicePicker(
      context,
      choices: choices,
      current: caps.currentVoice,
      server: server,
    );
    if (picked == null || picked.id == caps.currentVoice || !mounted) return;
    final backend = await ref.read(activeVoiceProvider.future);
    if (backend == null || !mounted) return;
    final result = await backend.setVoice(key, picked.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(voiceCapabilitiesProvider);
      case Err(:final failure):
        showIrisToast(
          context,
          message:
              "Couldn't change the voice: ${ChatController.describe(failure)}",
        );
    }
  }

  String _host() {
    final server = ref.read(activeServerProvider);
    if (server == null) return 'your server';
    final host = Uri.tryParse(server.baseUrl)?.host ?? '';
    return host.isEmpty ? server.label : host;
  }

  @override
  Widget build(BuildContext context) {
    final caps =
        ref.watch(voiceCapabilitiesProvider).value ?? VoiceCapabilities.none;
    final reason = caps.unavailableReason;

    if (!caps.voiceMode) {
      // A server set to GPT-Live that cannot run it says why; any other
      // server without voice mode has nothing to show.
      if (reason == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: IrisSettingsGroup(
          title: 'Voice',
          children: [IrisSettingsRow(label: reason)],
        ),
      );
    }

    final settings = ref.watch(voiceSettingsProvider);
    final controller = ref.read(voiceSettingsProvider.notifier);
    final choices = ref.watch(voiceChoicesProvider).value ?? const [];
    final hasList = choices.isNotEmpty;
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IrisSettingsGroup(
            title: 'Voice',
            children: [
              _ConversationRow(
                style: settings.style,
                onChanged: controller.setStyle,
              ),
              IrisSettingsRow(
                label: 'Speaker by default',
                sub: 'Otherwise earpiece, or your last route',
                trailing: IrisSwitch(
                  value: settings.speaker,
                  semanticLabel: 'Speaker by default',
                  onChanged: (on) => controller.setSpeaker(speaker: on),
                ),
              ),
              IrisSettingsRow(
                label: 'Captions by default',
                sub: 'Show the live transcript on calls',
                trailing: IrisSwitch(
                  value: settings.captions,
                  semanticLabel: 'Captions by default',
                  onChanged: (on) => controller.setCaptions(captions: on),
                ),
              ),
              if (hasList)
                IrisSettingsRow(
                  label: 'Voice',
                  sub: 'Offered by ${_host()}',
                  value: currentVoiceLabel(choices, caps.currentVoice),
                  onTap: () => unawaited(_pick(caps, choices)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              IrisSpace.sm,
              IrisSpace.sm,
              IrisSpace.sm,
              0,
            ),
            child: Text(
              hasList
                  ? 'Voices come from your server, so this list can change.'
                  : 'Calls use whichever voice your server speaks with.',
              style: context.type.caption.copyWith(
                fontSize: 12,
                color: palette.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hands-free or push to talk, as a row with a two-part control beneath it.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.style, required this.onChanged});

  final CallStyle style;
  final ValueChanged<CallStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IrisSpace.lg,
        vertical: IrisSpace.md + 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversation',
            style: type.body.copyWith(
              fontSize: 14.5,
              height: 1.3,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: IrisSpace.xxs),
          Text(
            'Default for new calls',
            style: type.caption.copyWith(fontSize: 12, color: palette.inkFaint),
          ),
          const SizedBox(height: IrisSpace.md),
          IrisSegmented<CallStyle>(
            values: CallStyle.values,
            selected: style,
            labelOf: _callStyleLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
