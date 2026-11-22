/// The Notifications group in Settings: shown when the hermes-iris plugin on the server can send them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/push_providers.dart';
import '../../demo/demo_mode.dart';
import '../../design/components/settings_list.dart';
import '../../design/platform/platform_feel.dart';
import 'notifications_settings_screen.dart';

class NotificationsSettingsSection extends ConsumerWidget {
  const NotificationsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The demo has no server to notify from, and a plugin without push has nothing to offer.
    if (ref.watch(demoModeProvider) || !ref.watch(pushAvailableProvider)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: IrisSettingsGroup(
        title: 'Notifications',
        children: [
          IrisSettingsRow(
            label: 'Notifications',
            sub: 'Hear about replies, approvals and finished jobs',
            value: ref.watch(pushEnabledProvider) ? 'On' : 'Off',
            onTap: () => unawaited(
              Navigator.of(context).push(
                IrisPageRoute<void>(
                  builder: (_) => const NotificationsSettingsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
