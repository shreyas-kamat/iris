import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/attachment.dart';
import 'package:iris/features/chat/attachment_chip.dart';
import 'package:iris/features/chat/attachment_picker.dart';
import 'package:iris/features/chat/composer.dart';

import '../support/harness.dart';

void main() {
  test('a picker is asked for photos or files', () {
    expect(AttachSource.values, [AttachSource.photos, AttachSource.files]);
  });

  testWidgets(
    'a photo chip shows its thumbnail; a file chip a doc glyph and the size',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        themed(
          Row(
            children: [
              AttachmentChip(name: 'panel.jpg', bytes: _png, onRemove: () {}),
              AttachmentChip(name: 'server.log', size: 2048, onRemove: () {}),
            ],
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.text('2 KB'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove panel.jpg'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('a long name is cut at 96', (tester) async {
    await tester.pumpWidget(
      themed(
        const AttachmentChip(
          name: 'a-very-long-file-name-that-keeps-going.txt',
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(Text).first).width,
      lessThanOrEqualTo(96),
    );
  });

  Widget composer({
    List<Attachment> attachments = const [],
    ValueChanged<AttachSource>? onAttach,
  }) => themed(
    Align(
      alignment: Alignment.bottomCenter,
      child: Composer(
        controller: TextEditingController(),
        running: false,
        onSend: () {},
        onStop: () {},
        attachments: attachments,
        onAttach: onAttach,
      ),
    ),
  );

  testWidgets('the + menu offers Photos and Files and the limits', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    AttachSource? chosen;
    await tester.pumpWidget(composer(onAttach: (source) => chosen = source));
    await tester.tap(find.bySemanticsLabel('Attach'));
    await tester.pumpAndSettle();
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);
    expect(find.text('up to 5 files · 20 MB each'), findsOneWidget);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(chosen, AttachSource.files);
    semantics.dispose();
  });

  testWidgets('at five files the + is off and the count shows', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      composer(
        attachments: [
          for (var i = 0; i < 5; i++)
            Attachment(name: 'f$i.txt', bytes: Uint8List(1)),
        ],
        onAttach: (_) {},
      ),
    );
    expect(find.text('5 / 5 FILES'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Attach'));
    await tester.pumpAndSettle();
    expect(find.text('Photos'), findsNothing);
    semantics.dispose();
  });
}

final Uint8List _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xFF,
  0xFF,
  0x3F,
  0x00,
  0x05,
  0xFE,
  0x02,
  0xFE,
  0xA7,
  0x35,
  0x81,
  0x84,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
