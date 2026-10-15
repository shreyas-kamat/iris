/// The bundled fonts' licences appear with every other licence in the app.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the fonts are listed with their licence text', () async {
    registerFontLicenses();
    final listed = <String, String>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      for (final package in entry.packages) {
        listed[package] = text;
      }
    }
    expect(
      listed.keys,
      containsAll(['Geist', 'Geist Mono', 'Instrument Serif']),
    );
    expect(listed['Geist'], contains('SIL OPEN FONT LICENSE'));
    expect(listed['Instrument Serif'], contains('SIL OPEN FONT LICENSE'));
  });
}
