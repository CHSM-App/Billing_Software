import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the share sheet for an in-memory file under its real [name].
///
/// cross_file ignores `XFile.fromData(name:)` everywhere except web, so without
/// [Share.shareXFiles]'s `fileNameOverrides` the file arrives in WhatsApp etc.
/// as a random UUID ("226-11f1-9d3f-….xlsx"). Every in-memory share goes here.
Future<void> shareFile(Uint8List bytes, String name, String mimeType,
        {String? text}) =>
    Share.shareXFiles(
      [XFile.fromData(bytes, name: name, mimeType: mimeType)],
      fileNameOverrides: [name],
      text: text,
    );

/// "Save as…" dialog for an in-memory file. Returns false when cancelled.
Future<bool> saveFile(Uint8List bytes, String name) async {
  final path = await FilePicker.platform
      .saveFile(dialogTitle: name, fileName: name, bytes: bytes);
  if (path == null) return false;
  // Android/iOS write the bytes themselves; desktop only returns the path.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await File(path).writeAsBytes(bytes);
  }
  return true;
}
