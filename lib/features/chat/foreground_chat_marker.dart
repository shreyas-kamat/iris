/// Tells the app which chat is on screen, for notification suppression: no notice for the chat the person is reading.
///
/// It reaches the provider container directly instead of through a `ConsumerWidget`, so a chat built without a
/// `ProviderScope` (a test, a preview) simply marks nothing.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/push_providers.dart';

class ForegroundChatMarker extends StatefulWidget {
  const ForegroundChatMarker({
    required this.storedId,
    required this.child,
    super.key,
  });

  /// The conversation's stored id; null for a new chat that has not been sent yet.
  final String? storedId;
  final Widget child;

  @override
  State<ForegroundChatMarker> createState() => _ForegroundChatMarkerState();
}

class _ForegroundChatMarkerState extends State<ForegroundChatMarker> {
  ProviderContainer? _container;
  String? _marked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = _find(context);
    _sync();
  }

  static ProviderContainer? _find(BuildContext context) {
    try {
      return ProviderScope.containerOf(context, listen: false);
    } on StateError {
      return null;
    }
  }

  @override
  void didUpdateWidget(ForegroundChatMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    final marked = _marked;
    _marked = null;
    if (marked != null) _change((chat) => chat.leave(marked));
    super.dispose();
  }

  void _sync() {
    final next = widget.storedId;
    if (next == _marked) return;
    final previous = _marked;
    _marked = next;
    _change((chat) {
      if (previous != null) chat.leave(previous);
      if (next != null) chat.enter(next);
    });
  }

  /// A provider is not changed in the middle of a build, so the change waits for the end of this microtask turn.
  void _change(void Function(ForegroundChat chat) apply) {
    final container = _container;
    if (container == null) return;
    scheduleMicrotask(() {
      try {
        apply(container.read(foregroundChatProvider.notifier));
      } on StateError {
        // The container was disposed first (the whole app is going); nothing to keep in step.
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
