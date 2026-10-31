import 'package:archive/archive.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/services/barcode_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generateBarcode gives the same 12 digits for any id case', () {
    const id = '3907C843-EE51-4A2B-9F00-123456789ABC';
    expect(generateBarcode(id), '390728434451');
    expect(generateBarcode(id.toLowerCase()), '390728434451');
    expect(RegExp(r'^\d{12}$').hasMatch(generateBarcode('ABCDEF12-0000-0000-0000-000000000000')), isTrue);
  });

  test('labelFileName strips unsafe characters and de-duplicates', () {
    final taken = <String>{};
    expect(labelFileName('Rum/Cola: "Big"', '30 ml', '111', taken), 'Rum_Cola_ _Big_ - 30 ml - 111.png');
    expect(labelFileName('Tea', null, '222', taken), 'Tea - 222.png');
    expect(labelFileName('Tea', null, '222', taken), 'Tea - 222 (2).png');
  });

  test('buildBarcodeZip has one PNG per coded item and size', () async {
    final items = [
      Item(id: 'i1', businessId: 'b', name: 'Tea', barcode: '111', price: 10, isActive: true),
      Item(id: 'i2', businessId: 'b', name: 'Rum', isActive: true, variants: [
        ItemVariant(id: 'v1', itemId: 'i2', label: '30 ml', price: 90, barcode: '222'),
        ItemVariant(id: 'v2', itemId: 'i2', label: '60 ml', price: 170), // no code → left out
      ]),
    ];
    final zip = ZipDecoder().decodeBytes(await buildBarcodeZip(items, (name: true, size: true, price: true, code: true)));
    expect(zip.files.map((f) => f.name), ['Tea - 111.png', 'Rum - 30 ml - 222.png']);
    for (final f in zip.files) {
      expect(f.content.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // PNG magic
    }
  });

  test('unticked fields make a shorter label; the bars always stay', () async {
    final item = [Item(id: 'i1', businessId: 'b', name: 'Tea', barcode: '111', price: 10, isActive: true)];
    Future<int> height(LabelFields f) async {
      final zip = ZipDecoder().decodeBytes(await buildBarcodeZip(item, f));
      final png = zip.files.single.content;
      return (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23]; // IHDR height
    }
    final full = await height((name: true, size: true, price: true, code: true));
    final barsOnly = await height((name: false, size: false, price: false, code: false));
    expect(barsOnly, lessThan(full));
    expect(barsOnly, greaterThanOrEqualTo(90)); // the 90 px of bars
  });
}
