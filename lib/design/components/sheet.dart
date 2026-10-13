/// Bottom sheets.
///
/// The overlay plane. Everything that interrupts the conversation arrives here:
/// the approval gate, pickers, the add-server flow. They share one presentation
/// so that "something is asking me a question" always looks the same, whatever
/// is asking.
///
/// Sheets open from the bottom rather than the centre because this is a phone
/// held in one hand, and the bottom of the screen is the only part of it a
/// thumb reliably reaches.
library;

import 'package:flutter/widgets.dart';

import '../platform/adaptive.dart';
import '../theme/iris_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'primitives.dart';

/// Presents [builder] as an Iris sheet.
///
/// Returns the value the sheet was popped with, or null if it was dismissed.
Future<T?> showIrisSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final palette = context.palette;
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: dismissible,
      barrierColor: palette.scrim,
      barrierLabel: dismissible ? 'Dismiss' : null,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) =>
          _SheetHost(dismissible: dismissible, child: Builder(builder: builder)),
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: IrisCurves.standard,
              reverseCurve: IrisCurves.exit,
            ),
          ),
          child: child,
        );
      },
    ),
  );
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.child, required this.dismissible});

  final Widget child;
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final window = IrisWindow.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // Never taller than most of the screen: a sheet that fills the
          // viewport is a page, and should have been pushed as one.
          maxHeight: window.size.height * 0.92,
          maxWidth: window.width.canSplit ? 520 : double.infinity,
        ),
        child: Padding(
          // Rises with the keyboard, so a sheet with a field in it stays usable.
          padding: EdgeInsets.only(bottom: window.keyboardInset),
          child: child,
        ),
      ),
    );
  }
}

/// The body of a sheet: a grabber, an optional title, and content.
class IrisSheet extends StatelessWidget {
  const IrisSheet({
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  /// Pinned to the bottom, above the home indicator.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;
    final depth = theme.depth(IrisPlane.overlay);
    final window = IrisWindow.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: IrisRadius.sheet),
        boxShadow: depth.shadows,
        border: depth.border == null
            ? null
            : Border(top: BorderSide(color: depth.border!)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Grabber(),
          if (title != null || subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IrisSpace.lg,
                IrisSpace.sm,
                IrisSpace.lg,
                IrisSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title case final title?)
                    Text(title, style: theme.typography.title),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: IrisSpace.xs),
                    Text(
                      subtitle,
                      style: theme.typography.body.copyWith(
                        color: palette.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: IrisSpace.lg),
              child: child,
            ),
          ),
          if (actions case final actions?)
            Padding(
              padding: EdgeInsets.fromLTRB(
                IrisSpace.lg,
                IrisSpace.lg,
                IrisSpace.lg,
                IrisSpace.lg +
                    (window.keyboardVisible ? 0 : window.safeArea.bottom),
              ),
              child: actions,
            )
          else
            SizedBox(
              height:
                  IrisSpace.lg +
                  (window.keyboardVisible ? 0 : window.safeArea.bottom),
            ),
        ],
      ),
    );
  }
}

/// The drag handle.
///
/// Decorative in the sense that nothing is wired to it yet, but load-bearing as
/// an affordance: it is how a person knows the panel can be pushed away.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: IrisSpace.sm),
    child: Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: context.palette.lineStrong,
          borderRadius: const BorderRadius.all(IrisRadius.full),
        ),
      ),
    ),
  );
}

/// A row of sheet actions: a primary on the right, an optional cancel.
class IrisSheetActions extends StatelessWidget {
  const IrisSheetActions({required this.primary, this.secondary, super.key});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final window = IrisWindow.of(context);
    // Stacked when text is large: two buttons side by side at 200% either clip
    // or wrap, and a wrapped button label is a broken control.
    if (window.prefersStacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          if (secondary case final secondary?) ...[
            const SizedBox(height: IrisSpace.sm),
            secondary,
          ],
        ],
      );
    }
    return Row(
      children: [
        if (secondary case final secondary?) ...[
          Expanded(child: secondary),
          const SizedBox(width: IrisSpace.sm),
        ],
        Expanded(flex: secondary == null ? 1 : 2, child: primary),
      ],
    );
  }
}

/// A tappable row inside a sheet or a settings list.
class IrisListRow extends StatelessWidget {
  const IrisListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = context.iris;
    final palette = theme.palette;

    final row = Container(
      constraints: const BoxConstraints(minHeight: IrisSize.minTapTarget + 8),
      padding: const EdgeInsets.symmetric(
        horizontal: IrisSpace.md,
        vertical: IrisSpace.sm,
      ),
      decoration: BoxDecoration(
        color: selected ? palette.accentQuiet : null,
        borderRadius: const BorderRadius.all(IrisRadius.sm),
      ),
      child: Row(
        children: [
          if (leading case final leading?) ...[
            leading,
            const SizedBox(width: IrisSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.typography.heading),
                if (subtitle case final subtitle?) ...[
                  const SizedBox(height: IrisSpace.xxs),
                  Text(
                    subtitle,
                    style: theme.typography.caption.copyWith(
                      color: palette.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: IrisSpace.md),
            trailing,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return IrisPressable(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      ensureTapTarget: false,
      child: row,
    );
  }
}
