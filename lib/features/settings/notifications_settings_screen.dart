/// Notifications: one master switch, then per event (a reply, an approval, a finished job) whether to tell the person,
/// in which words, and whether the notification also says what happened.
///
/// The words are the person's own. The server renders every notice from these settings, so an event in "Only my text"
/// mode never sends a word of content to the phone.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/push_providers.dart';
import '../../data/push/push_models.dart';
import '../../design/components/controls.dart';
import '../../design/components/segmented.dart';
import '../../design/components/settings_list.dart';
import '../../design/components/toast.dart';
import '../../design/platform/adaptive.dart';
import '../../design/platform/iris_scaffold.dart';
import '../../design/theme/iris_theme.dart';
import '../../design/tokens/metrics.dart';

extension on PushEvent {
  String get title => switch (this) {
    PushEvent.reply => 'A reply',
    PushEvent.approval => 'Needs your approval',
    PushEvent.job => 'A scheduled job finished',
  };

  String get group => switch (this) {
    PushEvent.reply => 'Replies',
    PushEvent.approval => 'Approvals',
    PushEvent.job => 'Scheduled jobs',
  };

  String get sub => switch (this) {
    PushEvent.reply => 'When a chat you are waiting on has an answer',
    PushEvent.approval => 'When Hermes asks before it runs something',
    PushEvent.job => 'When a scheduled job has run',
  };
}

extension on PushMode {
  String get label => switch (this) {
    PushMode.content => "Show what's happening",
    PushMode.text => 'Only my text',
  };
}

class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(pushEnabledProvider);
    final theme = context.iris;
    return IrisScaffold(
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          context.window.gutter,
          IrisSpace.sm,
          context.window.gutter,
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
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          context.window.gutter,
          IrisSpace.xs,
          context.window.gutter,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.xs),
              child: Text(
                'Notifications',
                style: theme.typography.serif.copyWith(fontSize: 34, height: 1),
              ),
            ),
            const SizedBox(height: 22),
            IrisSettingsGroup(
              title: 'Notifications',
              children: [
                IrisSettingsRow(
                  label: 'Notify me',
                  sub: 'Only for chats you have just sent to',
                  trailing: IrisSwitch(
                    value: enabled,
                    semanticLabel: 'Notify me',
                    onChanged: (on) => unawaited(_setEnabled(context, ref, on)),
                  ),
                ),
              ],
            ),
            if (enabled) ...[
              for (final event in PushEvent.values) ...[
                const SizedBox(height: 22),
                _EventGroup(event: event),
              ],
              if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                const SizedBox(height: 22),
                IrisSettingsGroup(
                  title: 'Try it',
                  children: [
                    IrisSettingsRow(
                      label: 'Send a test notification',
                      sub: 'Uses your wording for replies',
                      onTap: () => unawaited(_sendTest(context, ref)),
                    ),
                  ],
                ),
              ],
              if (defaultTargetPlatform != TargetPlatform.iOS) ...[
                const SizedBox(height: 22),
                const IrisSettingsGroup(
                  title: 'Connection',
                  children: [
                    // Task 9 supplies the live state; until then there is none to show.
                    IrisSettingsRow(
                      label: 'Connection to your server',
                      value: '—',
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    final result = await ref
        .read(pushEnabledProvider.notifier)
        .set(enabled: on);
    if (on && result.isErr && context.mounted) {
      showIrisToast(
        context,
        message: "Couldn't turn notifications on. Check the connection.",
      );
    }
  }

  static Future<void> _sendTest(BuildContext context, WidgetRef ref) async {
    final controller = await ref.read(pushControllerProvider.future);
    final result = await controller?.sendTest();
    if (!context.mounted) return;
    showIrisToast(
      context,
      message: result == null || result.isErr
          ? "The server couldn't send it. Check that APNs is set up."
          : 'Sent. It should arrive in a moment.',
    );
  }
}

/// One event: its switch, the person's words and the mode.
class _EventGroup extends ConsumerStatefulWidget {
  const _EventGroup({required this.event});

  final PushEvent event;

  @override
  ConsumerState<_EventGroup> createState() => _EventGroupState();
}

class _EventGroupState extends ConsumerState<_EventGroup> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: ref.read(pushSettingsProvider).of(widget.event).text,
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save(PushEventSettings Function(PushEventSettings) change) {
    final notifier = ref.read(pushSettingsProvider.notifier);
    notifier.update(
      widget.event,
      change(ref.read(pushSettingsProvider).of(widget.event)),
    );
  }

  /// Keeps the field at 100 characters (an emoji counts once) without trimming what is being typed.
  void _onText(String value) {
    final runes = value.runes;
    if (runes.length > PushEventSettings.maxText) {
      final clipped = String.fromCharCodes(
        runes.take(PushEventSettings.maxText),
      );
      _text.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
      value = clipped;
    }
    _save((s) => s.copyWith(text: PushEventSettings.cleanText(value)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(pushSettingsProvider).of(widget.event);
    final theme = context.iris;
    return IrisSettingsGroup(
      title: widget.event.group,
      children: [
        IrisSettingsRow(
          label: widget.event.title,
          sub: widget.event.sub,
          trailing: IrisSwitch(
            value: settings.on,
            semanticLabel: widget.event.title,
            onChanged: (on) => _save((s) => s.copyWith(on: on)),
          ),
        ),
        if (settings.on)
          Padding(
            padding: const EdgeInsets.all(IrisSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your words',
                  style: theme.typography.label.copyWith(
                    color: theme.palette.inkMuted,
                  ),
                ),
                const SizedBox(height: IrisSpace.xs),
                IrisField(
                  controller: _text,
                  hint: PushEventSettings.defaultText,
                  onChanged: _onText,
                ),
                const SizedBox(height: IrisSpace.md),
                IrisSegmented<PushMode>(
                  values: PushMode.values,
                  selected: settings.mode,
                  labelOf: (mode) => mode.label,
                  onChanged: (mode) => _save((s) => s.copyWith(mode: mode)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
