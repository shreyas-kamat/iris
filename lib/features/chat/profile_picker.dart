/// The profile picker, shared by home and settings.
///
/// A profile is a separate agent identity on the server, with its own
/// conversations, memory and model. Both screens that let someone change it
/// open the same sheet, so the choice looks and behaves identically wherever
/// it is made.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/sheet.dart';

/// Opens the profile sheet and selects the chosen profile.
///
/// Does nothing when there is at most one profile, because there is no choice
/// to offer. Callers can therefore wire it up unconditionally, though they will
/// usually hide the affordance as well.
Future<void> showProfilePicker(BuildContext context, WidgetRef ref) async {
  final profiles = ref.read(profilesProvider).value ?? const <AgentProfile>[];
  if (profiles.length <= 1) return;
  final current = ref.read(activeProfileProvider);

  final picked = await showIrisSheet<String>(
    context: context,
    builder: (sheetContext) => IrisSheet(
      title: 'Profile',
      subtitle: 'Each profile has its own conversations, memory and model.',
      child: Column(
        children: [
          for (final profile in profiles)
            IrisListRow(
              title: profile.name,
              subtitle: profile.model,
              selected: profile.name == current,
              onTap: () => Navigator.of(sheetContext).pop(profile.name),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  ref.read(activeProfileProvider.notifier).select(picked);
}
