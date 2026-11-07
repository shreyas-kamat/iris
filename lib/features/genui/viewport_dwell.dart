/// Tells when something has been in view long enough to count as seen: inside its scroll view, on the current screen,
/// with the app in front. Time spent out of view does not add up; leaving starts the count again.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class ViewportDwell extends StatefulWidget {
  const ViewportDwell({
    required this.onDwell,
    required this.child,
    this.duration = const Duration(seconds: 2),
    super.key,
  });

  /// Called once, when [child] has been in view for [duration].
  final VoidCallback onDwell;
  final Duration duration;
  final Widget child;

  @override
  State<ViewportDwell> createState() => _ViewportDwellState();
}

class _ViewportDwellState extends State<ViewportDwell> {
  static const _tick = Duration(milliseconds: 250);

  Timer? _timer;
  int _inView = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    if (!_visible()) {
      _inView = 0;
      return;
    }
    _inView++;
    if (_tick * _inView >= widget.duration) {
      _timer?.cancel();
      _timer = null;
      widget.onDwell();
    }
  }

  bool _visible() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final area = box.localToGlobal(Offset.zero) & box.size;
    if (area.height <= 0 || area.width <= 0) return false;

    final viewportBox = Scrollable.maybeOf(context)?.context.findRenderObject();
    final window = viewportBox is RenderBox && viewportBox.hasSize
        ? viewportBox.localToGlobal(Offset.zero) & viewportBox.size
        : Offset.zero & MediaQuery.sizeOf(context);
    final shown = area.intersect(window);
    if (shown.height <= 0 || shown.width <= 0) return false;
    // Half of the display, or half of a window that is smaller than it.
    return shown.height >= math.min(area.height, window.height) * 0.5;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
