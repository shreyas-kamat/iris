/// Proof that the layout survives the conditions a phone actually presents.
///
/// These are the cases that never appear in a design review because the
/// reviewer is looking at a portrait screenshot on a desk: the keyboard taking
/// half the screen, landscape leaving 390pt of height, and a user who has set
/// text to 200% because they cannot read it otherwise. Each one is asserted
/// here by rendering and checking for overflow, which is the only way to know.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/controls.dart';
import 'package:iris/design/components/primitives.dart';
import 'package:iris/design/platform/adaptive.dart';
import 'package:iris/design/platform/iris_scaffold.dart';
import 'package:iris/design/theme/iris_theme.dart';
import 'package:iris/design/tokens/metrics.dart';
import 'package:iris/design/tokens/palette.dart';
import 'package:iris/features/design_gallery/design_gallery.dart';

/// Renders [child] under a specific window shape.
Widget frame(
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
  double keyboard = 0,
  EdgeInsets safeArea = const EdgeInsets.only(top: 47, bottom: 34),
  bool isDark = true,
}) {
  final theme = IrisThemeData(skin: IrisSkin.aperture, isDark: isDark);
  return ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
        padding: safeArea,
        disableAnimations: true,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme,
        home: Material(
          type: MaterialType.transparency,
          child: IrisTheme(data: theme, child: child),
        ),
      ),
    ),
  );
}

/// Fails if anything overflowed during the pump.
void expectNoOverflow(WidgetTester tester) {
  final errors = tester.takeException();
  expect(
    errors,
    isNull,
    reason: 'layout overflowed or threw: $errors',
  );
}

void main() {
  group('window classification', () {
    test('a phone in portrait is compact in both axes of interest', () {
      expect(WidthClass.fromWidth(390), WidthClass.compact);
      expect(HeightClass.fromHeight(844), HeightClass.regular);
    });

    test('a phone in landscape is short, not narrow', () {
      // The case a width-only breakpoint system gets wrong: plenty of width,
      // almost no height.
      expect(WidthClass.fromWidth(844), WidthClass.expanded);
      expect(HeightClass.fromHeight(390), HeightClass.compact);
    });

    test('a tablet can split; a phone cannot', () {
      expect(WidthClass.fromWidth(390).canSplit, isFalse);
      expect(WidthClass.fromWidth(1024).canSplit, isTrue);
    });

    testWidgets('the keyboard inset is read separately from the safe area', (
      tester,
    ) async {
      late IrisWindow window;
      await tester.pumpWidget(
        frame(
          Builder(
            builder: (context) {
              window = IrisWindow.of(context);
              return const SizedBox();
            },
          ),
          keyboard: 336,
        ),
      );
      expect(window.keyboardVisible, isTrue);
      expect(window.keyboardInset, 336);
      // Conflating the two is what leaves a gap under a composer.
      expect(window.safeArea.bottom, 34);
      expect(window.isCramped, isTrue);
    });
  });

  group('the gallery survives real windows', () {
    testWidgets('portrait phone', (tester) async {
      await tester.pumpWidget(frame(const DesignGallery()));
      await tester.pump(const Duration(milliseconds: 200));
      expectNoOverflow(tester);
    });

    testWidgets('landscape phone', (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        frame(
          const DesignGallery(),
          size: const Size(844, 390),
          safeArea: const EdgeInsets.only(left: 47, right: 47, bottom: 21),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expectNoOverflow(tester);
    });

    testWidgets('smallest supported phone', (tester) async {
      // iPhone SE. The width at which a two-column row stops fitting.
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        frame(const DesignGallery(), size: const Size(320, 568)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expectNoOverflow(tester);
    });

    testWidgets('text at 200 percent', (tester) async {
      // The accessibility setting most likely to break a fixed-height control.
      await tester.pumpWidget(frame(const DesignGallery(), textScale: 2.0));
      await tester.pump(const Duration(milliseconds: 200));
      expectNoOverflow(tester);
    });

    testWidgets('text at 200 percent in landscape', (tester) async {
      // Both constraints at once, which is where fixed heights actually fail.
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        frame(
          const DesignGallery(),
          size: const Size(844, 390),
          textScale: 2.0,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expectNoOverflow(tester);
    });
  });

  group('controls under text scaling', () {
    testWidgets('a button grows instead of clipping its label', (tester) async {
      await tester.pumpWidget(
        frame(
          Center(
            child: IrisButton(label: 'Send to agent', onPressed: () {}),
          ),
          textScale: 2.0,
        ),
      );
      expectNoOverflow(tester);
      final height = tester.getSize(find.byType(IrisButton)).height;
      expect(
        height,
        greaterThan(IrisSize.control),
        reason: 'the button must grow with the text, not clip it',
      );
    });

    testWidgets('a label stops growing before it wraps mid-word', (
      tester,
    ) async {
      // Tracked uppercase mono widens faster than it heightens; past ~1.6x a
      // two-word label breaks. The cap trades label size for content space.
      Future<double> widthAt(double scale) async {
        await tester.pumpWidget(
          frame(
            const Center(child: IrisLabel('Context window')),
            textScale: scale,
          ),
        );
        return tester.getSize(find.byType(IrisLabel)).width;
      }

      final atOne = await widthAt(1.0);
      final atCap = await widthAt(1.6);
      final beyond = await widthAt(3.0);
      expect(atCap, greaterThan(atOne));
      expect(
        beyond,
        closeTo(atCap, 0.5),
        reason: 'label scaling should be capped, not unbounded',
      );
    });
  });

  group('the scaffold handles insets', () {
    testWidgets('the footer rises above the keyboard', (tester) async {
      Future<double> footerBottom({required double keyboard}) async {
        await tester.pumpWidget(
          frame(
            IrisScaffold(
              body: const SizedBox.expand(),
              footer: const SizedBox(height: 56, key: Key('footer')),
            ),
            keyboard: keyboard,
          ),
        );
        await tester.pump();
        return tester.getBottomLeft(find.byKey(const Key('footer'))).dy;
      }

      final closed = await footerBottom(keyboard: 0);
      final open = await footerBottom(keyboard: 336);
      expect(
        open,
        lessThan(closed),
        reason: 'the composer must not sit behind the keyboard',
      );
      expect(closed - open, closeTo(336 - 34, 1));
    });

    testWidgets('the header clears the status bar', (tester) async {
      await tester.pumpWidget(
        frame(
          IrisScaffold(
            header: const SizedBox(height: 44, key: Key('header')),
            body: const SizedBox.expand(),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('header'))).dy,
        47,
        reason: 'the header must start below the notch',
      );
    });

    testWidgets('back is routed through one callback for both platforms', (
      tester,
    ) async {
      var popped = false;
      await tester.pumpWidget(
        frame(
          IrisScaffold(
            body: const SizedBox.expand(),
            onBack: () => popped = true,
          ),
        ),
      );
      // Found by predicate rather than by type: PopScope is generic and the
      // concrete type argument is an implementation detail of the scaffold.
      final scope =
          tester.widgetList(find.byWidgetPredicate((w) => w is PopScope)).single
              as PopScope<Object?>;
      expect(scope.canPop, isFalse);
      scope.onPopInvokedWithResult?.call(false, null);
      expect(popped, isTrue);
    });
  });

  group('touch targets', () {
    testWidgets('a chip is tappable at the platform minimum', (tester) async {
      await tester.pumpWidget(
        frame(Center(child: IrisChip('idle', onTap: () {}))),
      );
      final size = tester.getSize(find.byType(IrisPressable));
      expect(size.height, greaterThanOrEqualTo(IrisSize.minTapTarget));
      expect(size.width, greaterThanOrEqualTo(IrisSize.minTapTarget));
    });

    testWidgets('a non-interactive chip is not padded out', (tester) async {
      // The minimum applies to things you can hit, not to every label.
      await tester.pumpWidget(frame(const Center(child: IrisChip('terminal'))));
      expect(find.byType(IrisPressable), findsNothing);
    });
  });

  group('semantics', () {
    testWidgets('a field announces what it is, not just what is in it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        frame(
          const Center(
            child: IrisField(label: 'Server address', hint: 'https://'),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(IrisField));
      expect(
        node.label,
        contains('Server address'),
        reason: 'a screen reader must be told what the field is for',
      );
      expect(
        node.flagsCollection.isTextField,
        isTrue,
        reason: 'it must be announced as an editable field, not as text',
      );
      handle.dispose();
    });

    testWidgets('an error is announced when it appears', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        frame(
          const Center(
            child: IrisField(label: 'Schedule', errorText: 'Needs five fields.'),
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(IrisField));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(node.value, 'Needs five fields.');
      handle.dispose();
    });

    testWidgets('the aperture describes the agent state in words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        frame(const Center(child: IrisGauge(value: 0.8, label: 'context'))),
      );
      expect(find.bySemanticsLabel('context: 80 percent'), findsOneWidget);
      handle.dispose();
    });
  });
}
