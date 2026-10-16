import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/chat_models.dart';
import 'package:iris/design/components/send_glyph.dart';

import '../support/harness.dart';

void main() {
  test('each busy mode has its own glyph', () {
    expect(SendKind.forMode(BusyMode.queue), SendKind.queue);
    expect(SendKind.forMode(BusyMode.steer), SendKind.steer);
    expect(SendKind.forMode(BusyMode.interrupt), SendKind.interrupt);
  });

  test('glyphs are announced by what they do', () {
    expect(SendKind.send.semanticLabel, 'Send');
    expect(SendKind.queue.semanticLabel, 'Queue');
    expect(SendKind.steer.semanticLabel, 'Steer');
    expect(SendKind.interrupt.semanticLabel, 'Interrupt');
    expect(SendKind.stop.semanticLabel, 'Stop');
  });

  testWidgets('every glyph paints at its size without error', (tester) async {
    for (final kind in SendKind.values) {
      await tester.pumpWidget(
        themed(Center(child: SendGlyph(kind, color: Colors.white))),
      );
      expect(tester.takeException(), isNull, reason: kind.name);
      expect(tester.getSize(find.byType(SendGlyph)), const Size(24, 24));
    }
  });
}
