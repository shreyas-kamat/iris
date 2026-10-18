/// A conversation as a Markdown file for the system share sheet.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/chat/chat_models.dart';

/// Shares [markdown] as a file. The chat screen takes one so tests do not
/// open a real share sheet.
typedef ShareMarkdown =
    Future<void> Function({
      required String fileName,
      required String title,
      required String markdown,
    });

/// The conversation as Markdown: your turns, Hermes's replies, one quoted line
/// per tool call, and errors. Reasoning is not exported.
String transcriptMarkdown(String title, List<TranscriptItem> items) {
  final heading = title.trim().isEmpty ? 'Chat' : title.trim();
  final out = StringBuffer('# $heading\n');
  for (final item in items) {
    if (item is UserTurn) {
      out.write('\n## You\n\n');
      if (item.text.trim().isNotEmpty) out.write('${item.text.trim()}\n');
      if (item.attachments.isNotEmpty) {
        out.write('\n_Attached: ${item.attachments.join(', ')}_\n');
      }
    } else if (item is AssistantTurn) {
      if (item.text.trim().isEmpty) continue;
      out.write('\n## Hermes\n\n${item.text.trim()}\n');
    } else if (item is ToolCall) {
      final verb = item.status == ToolStatus.failed ? 'Tool failed' : 'Ran';
      out.write('\n> $verb: `${item.name}`\n');
    } else if (item is Notice) {
      if (item.isError) out.write('\n> Error: ${item.text.trim()}\n');
    }
  }
  return out.toString();
}

/// `Investigate heartbeat gaps` as `investigate-heartbeat-gaps.md`.
String exportFileName(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final short = slug.length > 40
      ? slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '')
      : slug;
  return '${short.isEmpty ? 'chat' : short}.md';
}

Future<void> shareMarkdownFile({
  required String fileName,
  required String title,
  required String markdown,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(markdown);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/markdown')],
      subject: title,
    ),
  );
}
