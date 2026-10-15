/// The licences of what Iris bundles, for the "Open source licences" screen.
///
/// Flutter collects the licences of the packages the app depends on by itself.
/// The fonts are not packages, so their licence texts, which ship in
/// `assets/fonts/`, are added here.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled fonts' licences to Flutter's licence registry. Call once,
/// before the licence screen can be opened.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Geist', 'Geist Mono'],
      await rootBundle.loadString('assets/fonts/GEIST-OFL.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Instrument Serif'],
      await rootBundle.loadString('assets/fonts/INSTRUMENT-SERIF-OFL.txt'),
    );
  });
}
