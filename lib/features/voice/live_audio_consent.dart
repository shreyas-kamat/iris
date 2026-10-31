import 'package:flutter/widgets.dart';

import '../../design/components/controls.dart';
import '../../design/components/sheet.dart';
import '../../design/tokens/metrics.dart';
import '../chat/links.dart';

/// Ask before opening the direct audio connection, even if microphone access
/// was already granted for dictation or a call through the user's server.
Future<bool> confirmLiveAudio(BuildContext context) async =>
    await showIrisSheet<bool>(
      context: context,
      builder: (context) => IrisSheet(
        title: 'Send call audio to OpenAI?',
        actions: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IrisButton(
              label: 'Continue with GPT-Live',
              tone: IrisButtonTone.primary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: IrisSpace.sm),
            IrisButton(
              label: 'Cancel',
              tone: IrisButtonTone.ghost,
              expand: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'GPT-Live sends your microphone audio directly to OpenAI to '
              'generate spoken replies. Your Hermes server keeps the '
              'conversation history. OpenAI processes audio under its own '
              'privacy policy.',
            ),
            const SizedBox(height: IrisSpace.md),
            IrisButton(
              label: 'OpenAI privacy policy',
              tone: IrisButtonTone.ghost,
              onPressed: () =>
                  openLink('https://openai.com/policies/privacy-policy/'),
            ),
          ],
        ),
      ),
    ) ??
    false;
