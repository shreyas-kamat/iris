/// Wraps the signed-in home and offers the Iris plugin once, when the server is known to lack it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/plugin_providers.dart';
import '../../design/platform/platform_feel.dart';
import 'plugin_onboarding_screen.dart';

class PluginOnboardingHost extends ConsumerStatefulWidget {
  const PluginOnboardingHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PluginOnboardingHost> createState() =>
      _PluginOnboardingHostState();
}

class _PluginOnboardingHostState extends ConsumerState<PluginOnboardingHost> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    // The probe may have answered before this widget existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  void _maybeShow() {
    if (!mounted || _open || !ref.read(pluginOnboardingDueProvider)) return;
    _open = true;
    unawaited(
      Navigator.of(context)
          .push<void>(
            IrisPageRoute<void>(builder: (_) => const PluginOnboardingScreen()),
          )
          .whenComplete(() => _open = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pluginOnboardingDueProvider, (_, due) {
      if (due) _maybeShow();
    });
    return widget.child;
  }
}
