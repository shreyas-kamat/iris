import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/design/components/segmented.dart';

import '../support/harness.dart';

enum _Tab { one, two, three }

void main() {
  Widget host({
    required ValueChanged<_Tab> onChanged,
    _Tab selected = _Tab.one,
    List<_Tab> values = _Tab.values,
    double width = 390,
    double textScale = 1,
  }) => themed(
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, 844),
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Center(
        child: SizedBox(
          width: width - 40,
          child: IrisSegmented<_Tab>(
            values: values,
            selected: selected,
            labelOf: (t) => t.name,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );

  testWidgets('shows every label and reports a tap', (tester) async {
    _Tab? tapped;
    await tester.pumpWidget(host(onChanged: (t) => tapped = t));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    await tester.tap(find.text('two'));
    expect(tapped, _Tab.two);
  });

  testWidgets('the selected segment is announced as selected', (tester) async {
    await tester.pumpWidget(host(onChanged: (_) {}, selected: _Tab.two));
    expect(
      find.bySemanticsLabel(RegExp('two.*selected', caseSensitive: false)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('one'), findsOneWidget);
  });

  testWidgets('under reduced motion the thumb is on the new segment at once', (
    tester,
  ) async {
    var selected = _Tab.one;
    late StateSetter set;
    await tester.pumpWidget(
      themed(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Center(
              child: SizedBox(
                width: 300,
                child: IrisSegmented<_Tab>(
                  values: _Tab.values,
                  selected: selected,
                  labelOf: (t) => t.name,
                  onChanged: (_) {},
                ),
              ),
            );
          },
        ),
      ),
    );
    final first = tester.getCenter(find.byKey(const Key('segmented-thumb')));
    set(() => selected = _Tab.three);
    await tester.pump();
    final last = tester.getCenter(find.byKey(const Key('segmented-thumb')));
    expect(last.dx, greaterThan(first.dx + 150));
  });

  testWidgets('two segments split the width equally', (tester) async {
    await tester.pumpWidget(
      host(onChanged: (_) {}, values: const [_Tab.one, _Tab.two]),
    );
    final a = tester.getSize(find.text('one')).width;
    final one = tester.getCenter(find.text('one')).dx;
    final two = tester.getCenter(find.text('two')).dx;
    expect(a, lessThan(two - one));
    expect(tester.takeException(), isNull);
  });

  testWidgets('three segments fit at 320 pt', (tester) async {
    await tester.pumpWidget(host(onChanged: (_) {}, width: 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 200% text the segments wrap and stay tappable', (
    tester,
  ) async {
    _Tab? tapped;
    await tester.pumpWidget(
      host(onChanged: (t) => tapped = t, width: 320, textScale: 2),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('three'));
    expect(tapped, _Tab.three);
    expect(find.byKey(const Key('segmented-thumb')), findsNothing);
  });

  testWidgets('every segment is at least 44 pt tall', (tester) async {
    await tester.pumpWidget(host(onChanged: (_) {}));
    for (final label in ['one', 'two', 'three']) {
      final box = tester.getRect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        ).first,
      );
      expect(box.height, greaterThanOrEqualTo(44));
    }
  });
}
