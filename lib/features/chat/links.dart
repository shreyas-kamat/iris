/// Opening a link from a reply.
library;

import 'package:url_launcher/url_launcher.dart';

/// Opens [href] in the browser or mail app. Only web and mail links open: a
/// reply is text from a model, and `javascript:`, `file:` or `intent:` from
/// one should never run on a tap.
Future<void> openLink(String href) async {
  final uri = Uri.tryParse(href.trim());
  if (uri == null || !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
