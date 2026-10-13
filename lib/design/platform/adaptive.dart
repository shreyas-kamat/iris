/// Adapting to the window Iris is given.
///
/// A phone is not one size. It is portrait and landscape, it is a 5.4in SE and
/// a 6.9in Pro Max, it is half a foldable and a floating window on a tablet,
/// and on every one of those the keyboard can take half the screen away without
/// warning. Treating "phone" as a single fixed canvas is what produces an app
/// whose composer sits behind the keyboard and whose transcript is unreadable
/// in landscape.
///
/// The vocabulary here is size *classes*, not pixel breakpoints, because what a
/// layout needs to know is "is there room for a second pane" rather than "is
/// this 768 wide".
library;

import 'package:flutter/widgets.dart';

/// How much horizontal room there is, in terms of what fits.
enum WidthClass {
  /// A phone in portrait, or a narrow floating window. One pane, full bleed.
  compact,

  /// A large phone in landscape, a small tablet, a half-screen split. A list
  /// and a detail can coexist if the detail is the priority.
  medium,

  /// A tablet or desktop window. Two panes side by side, comfortably.
  expanded;

  /// Thresholds follow Material's window size classes, which line up closely
  /// enough with iPadOS size classes that one set serves both.
  static WidthClass fromWidth(double width) => switch (width) {
    < 600 => WidthClass.compact,
    < 840 => WidthClass.medium,
    _ => WidthClass.expanded,
  };

  bool get isCompact => this == WidthClass.compact;
  bool get canSplit => this != WidthClass.compact;
}

/// How much vertical room there is.
///
/// Separate from width because the constraining case is a phone in landscape
/// with the keyboard up, where width is generous and height is nearly gone.
/// A layout that only checks width will happily render a 300pt header there.
enum HeightClass {
  /// Under roughly a landscape phone's height. Collapse headers, hide
  /// decoration, give everything to the content.
  compact,

  /// Normal portrait phone and up.
  regular;

  static HeightClass fromHeight(double height) =>
      height < 480 ? HeightClass.compact : HeightClass.regular;

  bool get isCompact => this == HeightClass.compact;
}

/// The resolved shape of the current window.
@immutable
final class IrisWindow {
  const IrisWindow({
    required this.width,
    required this.height,
    required this.size,
    required this.keyboardInset,
    required this.safeArea,
    required this.textScale,
  });

  factory IrisWindow.of(BuildContext context) {
    final media = MediaQuery.of(context);
    return IrisWindow(
      width: WidthClass.fromWidth(media.size.width),
      height: HeightClass.fromHeight(media.size.height),
      size: media.size,
      // `viewInsets.bottom` is the keyboard; `padding.bottom` is the home
      // indicator. They are different problems and conflating them is why
      // composers end up either behind the keyboard or floating above nothing.
      keyboardInset: media.viewInsets.bottom,
      safeArea: media.padding,
      textScale: media.textScaler.scale(1),
    );
  }

  final WidthClass width;
  final HeightClass height;
  final Size size;

  /// Height currently occupied by the keyboard.
  final double keyboardInset;

  final EdgeInsets safeArea;

  /// The user's text size, as a multiplier. Above about 1.3 the layout has to
  /// give things up rather than scale them.
  final double textScale;

  bool get keyboardVisible => keyboardInset > 0;

  /// Whether to drop decoration and give the space to content. True in
  /// landscape on a phone, and whenever the keyboard has eaten the screen.
  bool get isCramped => height.isCompact || keyboardVisible;

  /// Whether text is large enough that horizontal pairings should stack.
  bool get prefersStacked => textScale >= 1.3;

  /// Horizontal page gutter. Wider windows get more, but not proportionally:
  /// a line of text longer than about 75 characters is harder to read however
  /// much room there is.
  double get gutter => switch (width) {
    WidthClass.compact => 16,
    WidthClass.medium => 24,
    WidthClass.expanded => 32,
  };

  /// The widest a column of prose should be, regardless of window width.
  double get readableWidth => 620;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IrisWindow &&
          other.width == width &&
          other.height == height &&
          other.size == size &&
          other.keyboardInset == keyboardInset &&
          other.safeArea == safeArea &&
          other.textScale == textScale);

  @override
  int get hashCode =>
      Object.hash(width, height, size, keyboardInset, safeArea, textScale);
}

/// Reads the window shape.
extension IrisWindowContext on BuildContext {
  IrisWindow get window => IrisWindow.of(this);
}

/// Constrains prose to a readable measure and centres it in wider windows.
///
/// Applied to the transcript and to any long-form panel. Without it, a tablet
/// renders 140-character lines, which is unreadable for the same reason a
/// newspaper uses columns.
class ReadableColumn extends StatelessWidget {
  const ReadableColumn({required this.child, this.maxWidth, super.key});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? IrisWindow.of(context).readableWidth,
      ),
      child: child,
    ),
  );
}
