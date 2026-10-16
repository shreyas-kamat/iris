/// Choosing files to send. The system picker covers photos and files with
/// no camera or storage permission.
library;

import 'package:file_picker/file_picker.dart';

import '../../data/chat/attachment.dart';

/// What the person asked the picker for from the "+" menu.
enum AttachSource { photos, files }

typedef PickFiles = Future<List<Attachment>> Function(AttachSource source);

Future<List<Attachment>> pickFiles(AttachSource source) async {
  final picked = await FilePicker.pickFiles(
    type: source == AttachSource.photos ? FileType.image : FileType.any,
  );
  return [
    for (final file in picked)
      Attachment(name: file.name, bytes: await file.readAsBytes()),
  ];
}
