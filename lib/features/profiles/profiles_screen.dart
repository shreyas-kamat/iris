/// The profiles on this server (frames D1, D1·L).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/chat/chat_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/primitives.dart';
import '../../design/components/settings_list.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/platform/platform_feel.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';
import 'profile_form_screen.dart';

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  Future<void> _open(
    BuildContext context,
    WidgetRef ref, {
    String? editing,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      IrisPageRoute<bool>(builder: (_) => ProfileFormScreen(editing: editing)),
    );
    if (changed == true) ref.invalidate(profilesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final type = context.type;
    final gutter = context.window.gutter;
    final profiles =
        ref.watch(profilesProvider).value ?? const <AgentProfile>[];
    final current = ref.watch(activeProfileProvider);
    final host =
        Uri.tryParse(ref.watch(activeServerProvider)?.baseUrl ?? '')?.host ??
        'this server';

    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.sm,
          gutter,
          IrisSpace.sm,
        ),
        child: Row(
          children: [
            IrisCircleButton(
              icon: Icons.arrow_back_ios_new,
              semanticLabel: 'Back',
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          IrisSpace.xs,
          gutter,
          IrisSpace.xxl,
        ),
        children: [
          Text('Profiles', style: type.serif.copyWith(fontSize: 38, height: 1)),
          const SizedBox(height: IrisSpace.sm),
          Text(
            'On $host. Tap the circle to switch to a profile.',
            style: type.body.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: IrisSpace.xl),
          IrisSettingsGroup(
            title: 'Profiles',
            children: [
              for (final profile in profiles)
                _ProfileRow(
                  profile: profile,
                  current: profile.name == current,
                  onOpen: () =>
                      unawaited(_open(context, ref, editing: profile.name)),
                  onSwitch: () {
                    unawaited(IrisHaptics.selection());
                    ref
                        .read(activeProfileProvider.notifier)
                        .select(profile.name);
                  },
                ),
              IrisSettingsRow(
                label: 'New profile',
                onTap: () => unawaited(_open(context, ref)),
              ),
            ],
          ),
          const SizedBox(height: IrisSpace.md),
          Text(
            "The model comes from each profile's config on the server and "
            "can't be edited here.",
            style: type.caption.copyWith(color: palette.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.current,
    required this.onOpen,
    required this.onSwitch,
  });

  final AgentProfile profile;
  final bool current;
  final VoidCallback onOpen;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = context.type;
    return IrisPressable(
      onTap: onOpen,
      ensureTapTarget: false,
      child: Padding(
        padding: const EdgeInsets.only(left: IrisSpace.lg),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.accentQuiet,
                shape: BoxShape.circle,
              ),
              child: Text(
                profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                style: type.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
            ),
            const SizedBox(width: IrisSpace.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: IrisSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            overflow: TextOverflow.ellipsis,
                            style: type.body.copyWith(
                              fontWeight: FontWeight.w500,
                              color: palette.ink,
                            ),
                          ),
                        ),
                        if (profile.isDefault) ...[
                          const SizedBox(width: IrisSpace.sm),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.surfaceSunken,
                              borderRadius: const BorderRadius.all(
                                IrisRadius.xs,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: IrisSpace.sm - 2,
                                vertical: 2,
                              ),
                              child: Text(
                                'Default',
                                style: type.codeSmall.copyWith(
                                  fontSize: 10.5,
                                  color: palette.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (profile.model case final model?)
                      Text(
                        model,
                        style: type.codeSmall.copyWith(color: palette.inkMuted),
                      ),
                  ],
                ),
              ),
            ),
            // A container of its own: left to merge, a screen reader would hear
            // the switch as part of the row and could not reach it on its own.
            Semantics(
              container: true,
              button: true,
              label: current ? 'Current profile' : 'Switch to ${profile.name}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: current ? null : onSwitch,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(
                    current ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: IrisSize.icon + 2,
                    color: current ? palette.accent : palette.lineStrong,
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
