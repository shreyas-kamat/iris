/// Choosing files to send. The system picker covers photos and files with
/// no camera or storage permission.
library;

import 'package:file_picker/file_picker.dart';

import '../../data/chat/attachment.dart';

typedef PickFiles = Future<List<Attachment>> Function();

Future<List<Attachment>> pickFiles() async {
  final picked = await FilePicker.pickFiles();
  return [
    for (final file in picked)
      Attachment(name: file.name, bytes: await file.readAsBytes()),
  ];
}
