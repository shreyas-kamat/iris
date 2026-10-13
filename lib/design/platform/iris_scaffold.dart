/// The page shell.
///
/// Every screen in Iris sits in one of these, because the things it handles are
/// exactly the things that are invisible until they are wrong: content under
/// the notch, a composer behind the keyboard, a scroll view that ends beneath
/// the home indicator, a back gesture that does nothing.
///
/// Flutter's `SafeArea` covers a third of that. The rest, particularly the
/// distinction between the keyboard inset and the home-indicator inset, has to
/// be handled deliberately.
library;

import 'package:flutter/widgets.dart';

import '../theme/iris_theme.dart';
import '../tokens/motion.dart';
import 'adaptive.dart';

/// A screen.
class IrisScaffold extends StatelessWidget {
  const IrisScaffold({
    required this.body,
    this.header,
    this.footer,
    this.onBack,
    this.resizeForKeyboard = true,
    super.key,
  });

  final Widget body;

  /// Pinned above [body], below the status bar.
  final Widget? header;

  /// Pinned below [body], above the home indicator. The composer lives here.
  ///
  /// Kept out of the scroll view deliberately: a composer that scrolls away is
  /// a composer you have to hunt for while the agent is mid-run.
  final Widget? footer;

  /// Invoked by the system back gesture and by a header's back control.
  ///
  /// Wiring both to one callback is what keeps Android's predictive back and
  /// iOS's edge swipe behaving identically without either being special-cased
  /// at the call site.
  final VoidCallback? onBack;

  /// Whether [footer] rises above the keyboard. True for anything with an
  /// input; false for a static action bar, which should stay put.
  final bool resizeForKeyboard;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final window = IrisWindow.of(context);

    Widget content = Column(
      children: [
        if (header case final header?)
          // The header consumes the status-bar inset itself so its background
          // extends under the clock rather than leaving a stripe of canvas.
          Padding(
            padding: EdgeInsets.only(top: window.safeArea.top),
            child: header,
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            // The header and footer have already accounted for these; leaving
            // them in would pad the body a second time.
            removeTop: header != null,
            removeBottom: true,
            child: body,
          ),
        ),
        if (footer case final footer?)
          AnimatedPadding(
            duration: context.reduceMotion
                ? Duration.zero
                : IrisDurations.normal,
            curve: IrisCurves.standard,
            padding: EdgeInsets.only(
              // Either the keyboard or the home indicator, never both: when the
              // keyboard is up it covers the home indicator, and adding the two
              // leaves a visible gap under the composer.
              bottom: resizeForKeyboard && window.keyboardVisible
                  ? window.keyboardInset
                  : window.safeArea.bottom,
            ),
            child: footer,
          ),
      ],
    );

    if (header == null) {
      content = Padding(
        padding: EdgeInsets.only(top: window.safeArea.top),
        child: content,
      );
    }

    return PopScope(
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: ColoredBox(color: palette.canvas, child: content),
    );
  }
}

/// A scroll view that ends above the home indicator rather than under it.
///
/// The last message in a transcript sitting behind the home bar is the kind of
/// thing that never shows up in a screenshot and is obvious the moment someone
/// scrolls to the bottom on a real phone.
class IrisScrollView extends StatelessWidget {
  const IrisScrollView({
    required this.slivers,
    this.controller,
    this.reverse = false,
    super.key,
  });

  final List<Widget> slivers;
  final ScrollController? controller;

  /// Transcripts scroll from the bottom, so new output appears where the eye
  /// already is.
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final window = IrisWindow.of(context);
    return CustomScrollView(
      controller: controller,
      reverse: reverse,
      slivers: [
        ...slivers,
        SliverToBoxAdapter(
          child: SizedBox(
            height: window.keyboardVisible
                ? window.keyboardInset
                : window.safeArea.bottom,
          ),
        ),
      ],
    );
  }
}
