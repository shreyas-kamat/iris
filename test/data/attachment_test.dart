/// Files sent with a prompt, and how they are named in it.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/chat/attachment.dart';

void main() {
  test('kind and data URL follow the extension', () {
    final png = Attachment(name: 'Shot.PNG', bytes: Uint8List.fromList([1, 2]));
    expect(png.isImage, isTrue);
    expect(png.dataUrl, 'data:image/png;base64,AQI=');
    final pdf = Attachment(name: 'r.pdf', bytes: Uint8List(0));
    expect(pdf.isImage, isFalse);
    expect(pdf.mimeType, 'application/pdf');
    expect(
      Attachment(name: 'x.bin', bytes: Uint8List(0)).mimeType,
      'application/octet-stream',
    );
  });

  test('references go first, then a blank line, then the text', () {
    expect(promptWithReferences('hi', []), 'hi');
    expect(promptWithReferences('', ['@file:a.txt']), '@file:a.txt');
    expect(
      promptWithReferences('read these', ['@file:a.txt', '@file:"b c.md"']),
      '@file:a.txt\n@file:"b c.md"\n\nread these',
    );
  });

  test('stored prompts give their files back as names', () {
    final (names, text) = splitReferences(
      '@file:/x/a.txt\n@file:"/x/b c.md"\n\nread these',
    );
    expect(names, ['a.txt', 'b c.md']);
    expect(text, 'read these');
    expect(splitReferences('no files').$1, isEmpty);
    expect(splitReferences('no files').$2, 'no files');
    final (only, rest) = splitReferences('@file:/x/a.txt');
    expect(only, ['a.txt']);
    expect(rest, '');
  });
}
