/// The app shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/image_host_scope.dart';
import '../design/platform/platform_feel.dart';
import '../design/theme/iris_theme.dart';
import '../features/chat/conversation_list_screen.dart';
import '../features/servers/server_gate.dart';
import 'device_state.dart';
import 'theme_controller.dart';

class IrisApp extends ConsumerWidget {
  const IrisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(themeControllerProvider);

    return Builder(
      builder: (context) {
        final theme = preference.resolve(
          MediaQuery.platformBrightnessOf(context),
        );

        // The status bar belongs to the page it sits on, so its icon brightness
        // follows the resolved theme rather than the platform's.
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: const Color(0x00000000),
            statusBarIconBrightness: theme.isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: theme.isDark
                ? Brightness.dark
                : Brightness.light,
            systemNavigationBarColor: theme.palette.canvas,
            systemNavigationBarIconBrightness: theme.isDark
                ? Brightness.light
                : Brightness.dark,
          ),
        );

        return MaterialApp(
          title: 'Iris',
          debugShowCheckedModeBanner: false,
          theme: theme.materialTheme,
          // Applied once at the root so no individual list has to remember to
          // bounce on iOS and clamp on Android.
          scrollBehavior: const IrisScrollBehavior(),
          // Above the Navigator, so pushed routes (the chat screen, the link
          // status screen) get both, not only the home route.
          //
          // Iris draws its own surfaces, but Flutter still requires a Material
          // ancestor for text to render normally — without one every Text gets
          // the yellow "missing material" underline. Transparent, so it
          // contributes nothing but that.
          builder: (context, navigator) => AnimatedIrisTheme(
            data: theme,
            // Hosts the person said to load images from without asking.
            child: ImageHostScope(
              hosts: ref.watch(imageHostsProvider),
              onAllow: ref.read(imageHostsProvider.notifier).allow,
              child: Material(
                type: MaterialType.transparency,
                child: navigator,
              ),
            ),
          ),
          home: ServerGate(
            // Conversations are home; the link status screen opens from the
            // list's header.
            connected: (context) => const ConversationListScreen(),
          ),
        );
      },
    );
  }
}
