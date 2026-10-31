import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';

import '../api.dart' as api;
import '../models/models.dart';
import 'barcode_image.dart';

/// A numeric barcode derived from an item's or size's UUID: its first 12 hex
/// characters, with a-f mapped to 0-5. Deterministic, so the same row always
/// gets the same code. Lowercased first: the server sends ids UPPERCASE, and
/// 'C' - 97 gave "-30", so codes came out like "3907-30843-28-2851".
String generateBarcode(String id) {
  final hex = id.replaceAll('-', '').toLowerCase();
  final digits = hex.substring(0, 12).split('').map((c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57 ? c : (code - 97).toString();
  }).join();
  return digits.padLeft(12, '0');
}

/// Give every plain item and every size that has no barcode its generated one,
/// and save it. A sized item's own code is skipped — its sizes are what get
/// scanned. Returns how many saves failed (e.g. a clash with another item's
/// code); those rows are skipped rather than stopping the run.
// ponytail: one PUT per row (~300 for a full menu); add a bulk endpoint if slow.
Future<int> assignMissingBarcodes(
    List<Item> items, void Function(int done, int total) onProgress) async {
  final jobs = <Future<void> Function()>[
    for (final i in items)
      if (!i.hasVariants && i.barcode == null)
        () => api.updateItem(i.id, {'barcode': generateBarcode(i.id)})
      else
        for (final v in i.variants)
          if (v.barcode == null)
            () => api.updateVariant(i.id, v.id, {'barcode': generateBarcode(v.id)}),
  ];
  var failed = 0;
  for (var n = 0; n < jobs.length; n++) {
    onProgress(n, jobs.length);
    try {
      await jobs[n]();
    } catch (_) {
      failed++;
    }
  }
  onProgress(jobs.length, jobs.length);
  return failed;
}

/// "Item - Size - code.png", safe on every file system, unique within [taken].
String labelFileName(String item, String? size, String code, Set<String> taken) {
  final base = [item, if (size != null) size, code]
      .join(' - ')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .trim();
  var name = '$base.png';
  for (var k = 2; !taken.add(name); k++) {
    name = '$base ($k).png';
  }
  return name;
}

/// Which text lines go on each exported label. The bars are always drawn.
typedef LabelFields = ({bool name, bool size, bool price, bool code});

/// One PNG per scannable label — the same image the label printer prints,
/// with only the [fields] picked — bundled into a zip. Rows without a barcode
/// are left out.
Future<Uint8List> buildBarcodeZip(List<Item> items, LabelFields fields) async {
  final archive = Archive();
  final taken = <String>{};
  Future<void> add(Item item, ItemVariant? v, String code) async {
    final image = await BarcodeImage.render(
      barcodeValue: code,
      itemName: fields.name ? item.name : null,
      price: fields.price ? v?.price ?? item.price ?? 0.0 : null,
      subtitle: fields.size ? v?.label : null,
      showValue: fields.code,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = png!.buffer.asUint8List();
    archive.add(ArchiveFile(
        labelFileName(item.name, v?.label, code, taken), bytes.length, bytes));
  }

  for (final i in items) {
    if (!i.hasVariants) {
      if (i.barcode != null) await add(i, null, i.barcode!);
    } else {
      for (final v in i.variants) {
        if (v.barcode != null) await add(i, v, v.barcode!);
      }
    }
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
