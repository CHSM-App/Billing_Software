import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show TextAlign;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

// On Windows we still fall back to flutter_thermal_printer (BLE/USB).
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart' as ftp
    show FlutterThermalPrinter;
import 'package:flutter_thermal_printer/utils/printer.dart' as ftp
    show Printer, ConnectionType;

import 'receipt_labels.dart';
import 'raster_lab.dart';

// ---------------------------------------------------------------------------
// Unified Printer model — wraps both BluetoothInfo and ftp.Printer
// ---------------------------------------------------------------------------

enum ConnectionType { ble, usb, classicBt }

class Printer {
  final String? name;
  final String? address; // MAC address
  final ConnectionType? connectionType;

  const Printer({this.name, this.address, this.connectionType});

  factory Printer.fromJson(Map<String, dynamic> j) => Printer(
        name: j['name'] as String?,
        address: j['address'] as String?,
        connectionType: _ctFromString(j['connectionType'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'connectionType': connectionType?.name,
      };

  static ConnectionType? _ctFromString(String? s) => switch (s) {
        'classicBt' => ConnectionType.classicBt,
        'ble' => ConnectionType.ble,
        'usb' => ConnectionType.usb,
        _ => null,
      };
}

// ---------------------------------------------------------------------------
// PrinterService
//
// Android / iOS  → print_bluetooth_thermal (Classic BT / SPP)
//                  Raw bytes: plain ASCII text + 0x0A line feeds (NO ESC @ reset)
// Windows        → flutter_thermal_printer (BLE / USB) with TSPL commands
// ---------------------------------------------------------------------------

const _prefKey = 'active_printer';

bool get _isWindows {
  try {
    return !kIsWeb && Platform.isWindows;
  } catch (_) {
    return false;
  }
}

class PrinterService {
  PrinterService._();
  static final PrinterService instance = PrinterService._();

  // -------------------------------------------------------------------------
  // Discovery
  // -------------------------------------------------------------------------

  Future<List<Printer>> listPrinters() async {
    if (_isWindows) {
      return _listWindows();
    } else {
      return _listClassicBt();
    }
  }

  Future<List<Printer>> _listClassicBt() async {
    try {
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      return paired
          .map((d) => Printer(
                name: d.name,
                address: d.macAdress,
                connectionType: ConnectionType.classicBt,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Printer>> _listWindows() async {
    final found = <Printer>[];
    try {
      final ftpInstance = ftp.FlutterThermalPrinter.instance;
      await ftpInstance.getPrinters(
        refreshDuration: const Duration(seconds: 3),
        connectionTypes: [ftp.ConnectionType.BLE, ftp.ConnectionType.USB],
      );
      await ftpInstance.devicesStream.first
          .timeout(
        const Duration(seconds: 4),
        onTimeout: () => <ftp.Printer>[],
      )
          .then((devices) {
        for (final d in devices) {
          found.add(Printer(
            name: d.name,
            address: d.address,
            connectionType: d.connectionType == ftp.ConnectionType.USB
                ? ConnectionType.usb
                : ConnectionType.ble,
          ));
        }
      });
    } catch (_) {}
    return found;
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> setActivePrinter(Printer printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(printer.toJson()));
  }

  Future<Printer?> getActivePrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return null;
    try {
      return Printer.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearActivePrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // -------------------------------------------------------------------------
  // Raw-byte receipt builder for Android BT printers
  //
  // Key findings from hardware testing:
  //   - Printer IS ESC/POS capable but ESC @ (reset) causes blank output
  //   - Plain ASCII bytes + 0x0A (LF) line feeds work perfectly
  //   - No cut command needed — paper tears manually
  //   - 32 chars fits safely on 58mm paper; 42 chars on 80mm
  //
  // Column layout (32 chars for 58mm safety):
  //   Name(16) Qty(4) Price(6) Total(6) = 32
  // -------------------------------------------------------------------------

  static const int _cols = 42;
  static const int _nameCols = 20;
  static const int _qtyCols = 4;
  static const int _priceCols = 9;
  static const int _totalCols = 9;

  /// Build the receipt as a list of pre-formatted, column-aligned lines.
  /// Shared by both the ASCII text path and the raster path so the layout is
  /// identical regardless of which is used.
  List<String> _buildReceiptLines(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      ReceiptLabels? labels}) {
    final grandTotal = bill.total - bill.discountAmount;
    final lines = <String>[];

    // Header
    lines.add(
        _centre(businessName ?? labels?.defaultBusiness ?? 'BUSINESS', _cols));
    if (businessAddress != null && businessAddress.isNotEmpty) {
      lines.add(_centre(businessAddress, _cols));
    }
    if (businessPhone != null && businessPhone.isNotEmpty) {
      lines.add(
          _centre('${labels?.phonePrefix ?? 'Ph:'} $businessPhone', _cols));
    }
    lines.add('-' * _cols);

    // Bill info
    lines.add('${labels?.billNo ?? 'Bill#:'} ${bill.billNumber}');
    // Table orders print their table number so the receipt is identifiable.
    if (bill.tableNumber != null && bill.tableNumber!.isNotEmpty) {
      lines.add('${labels?.table ?? 'Table:'} ${bill.tableNumber}');
    }
    lines.add(
        '${labels?.date ?? 'Date:'} ${_formatDate(bill.createdAt.toLocal())}');
    if (bill.customerName != null && bill.customerName!.isNotEmpty) {
      lines.add('${labels?.customer ?? 'Cust:'} ${bill.customerName}');
    }
    if (bill.customerPhone != null && bill.customerPhone!.isNotEmpty) {
      lines.add('${labels?.customerPhone ?? 'Ph:'} ${bill.customerPhone}');
    }
    lines.add('-' * _cols);

    // Items header
    lines.add(_itemRow(labels?.colItem ?? 'Item', labels?.colQty ?? 'Qty',
        labels?.colPrice ?? 'Price', labels?.colTotal ?? 'Total'));
    lines.add('-' * _cols);

    // Items
    for (final item in bill.items) {
      final name = item.itemName.length > _nameCols
          ? item.itemName.substring(0, _nameCols)
          : item.itemName;
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      lines.add(_itemRow(
        name,
        qty,
        item.unitPrice.toStringAsFixed(2),
        item.lineTotal.toStringAsFixed(2),
      ));
    }
    lines.add('-' * _cols);

    // Totals
    lines.add(_twoCol(labels?.subtotal ?? 'Subtotal:',
        'Rs.${bill.subtotal.toStringAsFixed(2)}'));

    if (bill.taxAmount > 0) {
      lines.add(_twoCol(
          labels?.tax ?? 'Tax:', 'Rs.${bill.taxAmount.toStringAsFixed(2)}'));
    }

    if (bill.discountAmount > 0) {
      lines.add(_twoCol(labels?.discount ?? 'Discount:',
          '-Rs.${bill.discountAmount.toStringAsFixed(2)}'));
    }

    lines.add(_twoCol(labels?.total ?? 'Grand Total:',
        'Rs.${grandTotal.toStringAsFixed(2)}'));

    lines.add(
        _twoCol(labels?.payment ?? 'Payment:', bill.paymentMode.toUpperCase()));
    lines.add('-' * _cols);
    lines.add(_centre(labels?.thankYou ?? 'Thank you, visit again!', _cols));

    return lines;
  }

  /// Build the receipt as STRUCTURED rows (columns + rules) for the raster
  /// path, so proportional Devanagari/Tamil glyphs align in a real table
  /// (Item / Qty / Price / Total) instead of overflowing space-padded columns.
  List<ReceiptRow> _buildReceiptRows(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      ReceiptLabels? labels}) {
    final grandTotal = bill.total - bill.discountAmount;
    final rows = <ReceiptRow>[];

    // Header
    rows.add(ReceiptRow.center(
        businessName ?? labels?.defaultBusiness ?? 'BUSINESS',
        size: 34, bold: true));
    if (businessAddress != null && businessAddress.isNotEmpty) {
      rows.add(ReceiptRow.center(businessAddress, size: 26));
    }
    if (businessPhone != null && businessPhone.isNotEmpty) {
      rows.add(ReceiptRow.center(
          '${labels?.phonePrefix ?? 'Ph:'} $businessPhone', size: 26));
    }
    rows.add(ReceiptRow.rule());

    // Bill info (label left, value right)
    rows.add(ReceiptRow.cols([
      ReceiptCell('${labels?.billNo ?? 'Bill#:'} ${bill.billNumber}',
          widthFraction: 1.0),
    ], size: 26));
    if (bill.tableNumber != null && bill.tableNumber!.isNotEmpty) {
      rows.add(ReceiptRow.cols([
        ReceiptCell('${labels?.table ?? 'Table:'} ${bill.tableNumber}',
            widthFraction: 1.0),
      ], size: 26));
    }
    rows.add(ReceiptRow.cols([
      ReceiptCell(
          '${labels?.date ?? 'Date:'} ${_formatDate(bill.createdAt.toLocal())}',
          widthFraction: 1.0),
    ], size: 26));
    if (bill.customerName != null && bill.customerName!.isNotEmpty) {
      rows.add(ReceiptRow.cols([
        ReceiptCell('${labels?.customer ?? 'Cust:'} ${bill.customerName}',
            widthFraction: 1.0),
      ], size: 26));
    }
    if (bill.customerPhone != null && bill.customerPhone!.isNotEmpty) {
      rows.add(ReceiptRow.cols([
        ReceiptCell('${labels?.customerPhone ?? 'Ph:'} ${bill.customerPhone}',
            widthFraction: 1.0),
      ], size: 26));
    }
    rows.add(ReceiptRow.rule());

    // Item table: Name(.46) Qty(.14,center) Price(.20,right) Total(.20,right)
    ReceiptRow itemRow(String n, String q, String p, String t,
            {bool bold = false}) =>
        ReceiptRow.cols([
          ReceiptCell(n, widthFraction: 0.46),
          ReceiptCell(q, align: TextAlign.center, widthFraction: 0.14),
          ReceiptCell(p, align: TextAlign.right, widthFraction: 0.20),
          ReceiptCell(t, align: TextAlign.right, widthFraction: 0.20),
        ], size: 26, bold: bold);

    rows.add(itemRow(labels?.colItem ?? 'Item', labels?.colQty ?? 'Qty',
        labels?.colPrice ?? 'Price', labels?.colTotal ?? 'Total',
        bold: true));
    rows.add(ReceiptRow.rule());

    for (final item in bill.items) {
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      rows.add(itemRow(
        item.itemName,
        qty,
        item.unitPrice.toStringAsFixed(2),
        item.lineTotal.toStringAsFixed(2),
      ));
    }
    rows.add(ReceiptRow.rule());

    // Totals (label left, amount right)
    ReceiptRow total(String l, String r, {bool bold = false, double size = 22}) =>
        ReceiptRow.cols([
          ReceiptCell(l, widthFraction: 0.55),
          ReceiptCell(r, align: TextAlign.right, widthFraction: 0.45),
        ], size: size, bold: bold);

    rows.add(total(labels?.subtotal ?? 'Subtotal:',
        'Rs.${bill.subtotal.toStringAsFixed(2)}'));
    if (bill.taxAmount > 0) {
      rows.add(total(labels?.tax ?? 'Tax:',
          'Rs.${bill.taxAmount.toStringAsFixed(2)}'));
    }
    if (bill.discountAmount > 0) {
      rows.add(total(labels?.discount ?? 'Discount:',
          '-Rs.${bill.discountAmount.toStringAsFixed(2)}'));
    }
    rows.add(total(labels?.total ?? 'Grand Total:',
        'Rs.${grandTotal.toStringAsFixed(2)}',
        bold: true, size: 32));
    rows.add(total(labels?.payment ?? 'Payment:',
        bill.paymentMode.toUpperCase()));
    rows.add(ReceiptRow.rule());
    rows.add(ReceiptRow.center(
        labels?.thankYou ?? 'Thank you, visit again!', size: 26));

    return rows;
  }

  /// Pack ASCII-only receipt [lines] into plain ESC/POS text bytes (fast path).
  List<int> _linesToAsciiBytes(List<String> lines) {
    final bytes = <int>[];
    for (final line in lines) {
      for (final c in line.codeUnits) {
        bytes.add(c > 127 ? 63 : c); // replace any stray non-ASCII with '?'
      }
      bytes.add(0x0A); // LF
    }
    // 4 extra feeds to advance paper past the print head for tearing.
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
    return bytes;
  }

  /// True if any line contains a non-ASCII character (e.g. Marathi/Tamil/…),
  /// meaning the printer can't render it as text and we must rasterize.
  static bool _hasNonAscii(List<String> lines) {
    for (final line in lines) {
      for (final u in line.codeUnits) {
        if (u > 127) return true;
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // TSPL receipt builder — Windows USB/BLE printers only
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Printing dispatch
  // -------------------------------------------------------------------------

  Future<void> printBill(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      ReceiptLabels? labels}) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    final lines = _buildReceiptLines(bill,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress,
        labels: labels);

    if (_hasNonAscii(lines)) {
      // The receipt contains at least one non-English character (Marathi,
      // Tamil, …) which the printer's ROM cannot render as text. Render the
      // whole receipt as a raster image with TRUE column alignment so every
      // glyph prints correctly and the table stays aligned.
      // Uses the proven transport: single write, no inter-chunk delay.
      final rows = _buildReceiptRows(bill,
          businessName: businessName,
          businessPhone: businessPhone,
          businessAddress: businessAddress,
          labels: labels);
      final raster = await RasterLab.rowsToReceiptRaster(rows);
      if (_isWindows) {
        await _printWindows(printer, raster);
      } else {
        await _sendClassicBtTuned(printer, raster, 0, 0);
      }
    } else {
      // Pure English/numbers → fast native ESC/POS text.
      await _printBytes(printer, _linesToAsciiBytes(lines));
    }
  }

  /// Send a pre-built ESC/POS byte stream to the active printer as-is.
  /// Used by the Marathi print-test page to compare rendering strategies.
  /// [slow] uses smaller BT chunks with longer delays so the printer's buffer
  /// doesn't overrun (which drops raster rows → faint/partial images).
  Future<void> printRawBytes(List<int> bytes, {bool slow = false}) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');
    await _printBytes(printer, bytes, slow: slow);
  }

  /// Raster-lab tuned send: explicit [chunkSize] and inter-chunk [delayMs] so
  /// Stage 5 can measure throughput and find the smallest clean chunk/delay.
  /// Android/Classic-BT only; Windows ignores the tuning and uses its own path.
  Future<void> printRawBytesTuned(
    List<int> bytes, {
    required int chunkSize,
    required int delayMs,
  }) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');
    if (_isWindows) {
      await _printWindows(printer, bytes);
      return;
    }
    await _sendClassicBtTuned(printer, bytes, chunkSize, delayMs);
  }

  Future<void> testPrint() async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    final lines = [
      _centre('TEST PRINT', _cols),
      '-' * _cols,
      _centre('Printer is working!', _cols),
      '-' * _cols,
    ];
    final bytes = <int>[];
    for (final line in lines) {
      for (final c in line.codeUnits) {
        bytes.add(c > 127 ? 63 : c);
      }
      bytes.add(0x0A);
    }
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
    await _printBytes(printer, bytes);
  }

  // -------------------------------------------------------------------------
  // Barcode label
  // -------------------------------------------------------------------------

  Future<void> printBarcodeLabel({
    required String barcodeValue,
    required String itemName,
    required double price,
    int copies = 1,
  }) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    final List<int> bytes;
    if (_isWindows) {
      // TSPL label with actual barcode graphic
      final name = itemName.length > 38 ? itemName.substring(0, 38) : itemName;
      final priceStr = 'Rs.${price.toStringAsFixed(2)}';
      final sb = StringBuffer();
      sb.write('SIZE 72 mm,40 mm\r\n');
      sb.write('GAP 2 mm,0 mm\r\n');
      sb.write('CODEPAGE 437\r\n');
      sb.write('CLS\r\n');
      sb.write('TEXT 10,10,"3",0,1,1,"${name.replaceAll('"', '\\"')}"\r\n');
      sb.write(
          'TEXT 480,10,"3",0,1,1,"${priceStr.replaceAll('"', '\\"')}"\r\n');
      sb.write('BARCODE 10,40,"128",80,1,0,2,2,"$barcodeValue"\r\n');
      sb.write('PRINT $copies,1\r\n');
      bytes = _enc(sb.toString());
    } else {
      // Raw text label for BT printer (no barcode graphic — print value as text)
      final name =
          itemName.length > _cols ? itemName.substring(0, _cols) : itemName;
      final b = <int>[];
      void addLine(String s) {
        for (final c in s.codeUnits) {
          b.add(c > 127 ? 63 : c);
        }
        b.add(0x0A);
      }

      addLine(_centre(name, _cols));
      addLine(_centre('Rs.${price.toStringAsFixed(2)}', _cols));
      addLine('-' * _cols);
      addLine(_centre(barcodeValue, _cols));
      b.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
      bytes = b;
    }
    await _printBytes(printer, bytes);
  }

  // -------------------------------------------------------------------------
  // Low-level send
  // -------------------------------------------------------------------------

  Future<void> _printBytes(Printer printer, List<int> bytes,
      {bool slow = false}) async {
    if (_isWindows) {
      await _printWindows(printer, bytes);
    } else {
      await _printClassicBt(printer, bytes, slow: slow);
    }
  }

  Future<void> _printClassicBt(Printer printer, List<int> bytes,
      {bool slow = false}) async {
    if (printer.address == null) {
      throw PrinterException('Printer address not set');
    }
    try {
      final permitted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!permitted) {
        throw PrinterException('Bluetooth permission not granted');
      }

      final btOn = await PrintBluetoothThermal.bluetoothEnabled;
      if (!btOn) throw PrinterException('Bluetooth is turned off');

      final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
      if (alreadyConnected) {
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: printer.address!,
      );
      if (!connected) {
        throw PrinterException(
            'Could not connect to printer. Make sure it is powered on and paired.');
      }

      await Future.delayed(const Duration(seconds: 2));

      // Chunking strategy:
      //  - fast (default): big chunks, no per-chunk delay → prints raster at
      //    full head speed, matching professional POS apps. SPP flow-control in
      //    print_bluetooth_thermal blocks writeBytes until the buffer drains, so
      //    large chunks are safe and far faster than many tiny delayed writes.
      //  - slow: small chunks + pauses, kept only as a fallback for flaky links.
      final chunkSize = slow ? 256 : 2048;
      final gapMs = slow ? 40 : 0;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, bytes.length);
        // writeBytes expects a plain Dart List<int>. A Uint8List sublist crosses
        // the method channel as a Java byte[], which the plugin tries to cast to
        // List → ClassCastException (raster/Marathi prints silently fail). Force
        // a growable List<int> so it marshals as a Java List.
        final chunk = List<int>.from(bytes.sublist(i, end));
        final result = await PrintBluetoothThermal.writeBytes(chunk);
        if (!result) throw PrinterException('Write failed at chunk $i');
        if (gapMs > 0 && end < bytes.length) {
          await Future.delayed(Duration(milliseconds: gapMs));
        }
      }
    } catch (e) {
      if (e is PrinterException) rethrow;
      throw PrinterException(e.toString());
    }
  }

  /// Connect + send with explicit chunk size and delay (Stage 5 tuning).
  /// chunkSize <= 0 means a single write of the whole payload.
  Future<void> _sendClassicBtTuned(
      Printer printer, List<int> bytes, int chunkSize, int delayMs) async {
    if (printer.address == null) {
      throw PrinterException('Printer address not set');
    }
    try {
      final permitted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!permitted) throw PrinterException('Bluetooth permission not granted');
      final btOn = await PrintBluetoothThermal.bluetoothEnabled;
      if (!btOn) throw PrinterException('Bluetooth is turned off');

      final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
      if (alreadyConnected) {
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: printer.address!);
      if (!connected) {
        throw PrinterException(
            'Could not connect to printer. Make sure it is powered on and paired.');
      }
      await Future.delayed(const Duration(seconds: 2));

      final step = chunkSize <= 0 ? bytes.length : chunkSize;
      for (var i = 0; i < bytes.length; i += step) {
        final end = (i + step).clamp(0, bytes.length);
        final chunk = List<int>.from(bytes.sublist(i, end));
        final ok = await PrintBluetoothThermal.writeBytes(chunk);
        if (!ok) throw PrinterException('Write failed at chunk $i');
        if (delayMs > 0 && end < bytes.length) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    } catch (e) {
      if (e is PrinterException) rethrow;
      throw PrinterException(e.toString());
    }
  }

  Future<void> _printWindows(Printer printer, List<int> bytes) async {
    try {
      final ftpPrinter = ftp.Printer(
        name: printer.name,
        address: printer.address,
        connectionType: printer.connectionType == ConnectionType.usb
            ? ftp.ConnectionType.USB
            : ftp.ConnectionType.BLE,
      );
      final ftpInstance = ftp.FlutterThermalPrinter.instance;
      final connected = await ftpInstance.connect(ftpPrinter);
      if (!connected) throw PrinterException('Could not connect to printer');
      // This printer connects over BLE on Windows. BLE is packet-based and the
      // write size is capped by the ATT MTU — chunks larger than ~512 bytes make
      // writeCharacteristic.write() fail silently (nothing prints). So keep 512
      // (safe, proven) and just drop the artificial per-chunk delay for smooth
      // feed: longData:false removes the 10ms sleep the package adds after every
      // chunk (that sleep was what made the print head keep stopping / banding).
      await ftpInstance.printData(
        ftpPrinter,
        bytes,
        longData: false,
        chunkSize: 512,
      );
    } catch (e) {
      if (e is PrinterException) rethrow;
      throw PrinterException(e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Centre text within width
  static String _centre(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final pad = (width - text.length) ~/ 2;
    return ' ' * pad + text;
  }

  /// 4-column item row for 32-char receipt
  /// Name(16) Qty(4) Price(6) Total(6)
  static String _itemRow(String name, String qty, String price, String total) {
    final n = name.padRight(_nameCols).substring(0, _nameCols);
    final q = qty.padLeft(_qtyCols);
    final p = price.padLeft(_priceCols);
    final t = total.padLeft(_totalCols);
    return '$n$q$p$t';
  }

  /// 2-column row: label left, value right (32-char)
  static String _twoCol(String label, String value) =>
      _twoColN(label, value, _cols);

  /// 2-column row with explicit width
  static String _twoColN(String label, String value, int width) {
    final space = width - label.length - value.length;
    return '$label${' ' * (space < 1 ? 1 : space)}$value';
  }

  /// Encode string to Latin-1 bytes (for TSPL commands)
  static List<int> _enc(String s) =>
      s.codeUnits.map((c) => c > 255 ? 0x3F : c).toList();

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = _monthName(dt.month);
    final h =
        (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$d-$mo-${dt.year} $h:$mi $ampm';
  }

  String _monthName(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m];
}

class PrinterException implements Exception {
  final String message;
  PrinterException(this.message);

  @override
  String toString() => message;
}
