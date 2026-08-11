import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show TextAlign;
import 'dart:ui' as ui show Image;
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
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
import 'barcode_image.dart';

// ---------------------------------------------------------------------------
// Unified Printer model — wraps both BluetoothInfo and ftp.Printer
// ---------------------------------------------------------------------------

enum ConnectionType { ble, usb, classicBt }

/// Monospace column widths for the ASCII receipt, sized to the paper width.
/// The four item columns must sum to [cols] so rows fill the line and totals
/// right-align.
class _ColProfile {
  final int cols;
  final int nameCols;
  final int qtyCols;
  final int priceCols;
  final int totalCols;
  const _ColProfile({
    required this.cols,
    required this.nameCols,
    required this.qtyCols,
    required this.priceCols,
    required this.totalCols,
  });
}

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

  /// Ticks whenever the active printer is selected or cleared. UI providers
  /// (e.g. canPrintProvider) listen to this so removing/changing the printer
  /// anywhere — Settings, the setup page — updates the billing screen live.
  final ValueNotifier<int> activePrinterRevision = ValueNotifier<int>(0);

  void _bumpPrinterRevision() =>
      activePrinterRevision.value = activePrinterRevision.value + 1;

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
    _bumpPrinterRevision();
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

  /// Whether a receipt could actually be printed right now — not just whether a
  /// printer is saved. Checks the live preconditions the print path itself
  /// requires, so the UI reflects reality when Bluetooth is turned off or the
  /// printer is unpaired/out of range:
  ///
  ///   • a printer is configured, AND
  ///   • (Classic-BT / Android) Bluetooth permission is granted AND Bluetooth
  ///     is currently enabled.
  ///
  /// It deliberately does NOT open a connection (that is slow and would churn
  /// the BT link); the actual connect still happens at print time. On Windows
  /// (BLE/USB) reachability is only known at connect time, so "configured" is
  /// treated as printable.
  Future<bool> canPrint() async {
    final printer = await getActivePrinter();
    if (printer == null) return false;
    if (_isWindows) return true;
    try {
      final permitted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!permitted) return false;
      final btOn = await PrintBluetoothThermal.bluetoothEnabled;
      return btOn;
    } catch (_) {
      // If we can't determine BT state, assume not printable so the UI falls
      // back to "Save" rather than promising a print that would fail.
      return false;
    }
  }

  Future<void> clearActivePrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    _bumpPrinterRevision();
  }

  // -------------------------------------------------------------------------
  // Raw-byte receipt builder for Android BT printers
  //
  // Key findings from hardware testing:
  //   - Printer IS ESC/POS capable but ESC @ (reset) causes blank output
  //   - Plain ASCII bytes + 0x0A (LF) line feeds work perfectly
  //   - No cut command needed — paper tears manually
  //   - The app supports 80mm printers only. An 80mm head @ 203dpi prints
  //     576 dots wide; Font A is 12 dots/char → up to 48 characters per line.
  //     _cols is set slightly below the max (46) to leave a small, even margin
  //     on both edges; the four item columns MUST sum to _cols so rows stay
  //     right-aligned to the content block.
  //
  // Column layout depends on paper width (see _ColProfile):
  //   80mm → 46 chars: Name(22) Qty(4) Price(10) Total(10)
  //   58mm → 32 chars: Name(14) Qty(4) Price(7)  Total(7)
  // The 58mm price/total are 7 wide (not 6) so their padLeft keeps a leading
  // space — otherwise "220.00" fills the field and columns visually collide.
  // -------------------------------------------------------------------------

  // Default 80mm profile — used by callers that don't specify a size.
  static const _ColProfile _cols80 =
      _ColProfile(cols: 46, nameCols: 22, qtyCols: 4, priceCols: 10, totalCols: 10);
  static const _ColProfile _cols58 =
      _ColProfile(cols: 32, nameCols: 14, qtyCols: 4, priceCols: 7, totalCols: 7);

  /// Resolve the column profile for a printable dot-width (384 → 58mm, else 80mm).
  static _ColProfile _profileForDots(int dots) => dots <= 384 ? _cols58 : _cols80;

  /// Build the receipt as a list of pre-formatted, column-aligned lines.
  /// Shared by both the ASCII text path and the raster path so the layout is
  /// identical regardless of which is used.
  List<String> _buildReceiptLines(Bill bill, _ColProfile p,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      ReceiptLabels? labels}) {
    final grandTotal = bill.total - bill.discountAmount;
    // GSTIN is passed only when GST is enabled — its presence gates the
    // GSTIN line + the CGST/SGST split. Without it the receipt is as before.
    final gst = businessGstin != null && businessGstin.isNotEmpty;
    final fssai = businessFssai != null && businessFssai.isNotEmpty;
    final lines = <String>[];

    // Header — order: name, address, phone, GSTIN, FSSAI. Only the business
    // name is always shown; every other line prints only when available.
    lines.add(
        _centre(businessName ?? labels?.defaultBusiness ?? 'BUSINESS', p.cols));
    if (businessAddress != null && businessAddress.isNotEmpty) {
      // Address may be multi-line and/or longer than the paper width — wrap and
      // centre each resulting line (plain _centre would truncate + left-align).
      lines.addAll(_centreMultiline(businessAddress, p.cols));
    }
    if (businessPhone != null && businessPhone.isNotEmpty) {
      lines.add(
          _centre('${labels?.phonePrefix ?? 'Ph:'} $businessPhone', p.cols));
    }
    if (gst) {
      lines.add(_centre('${labels?.gstin ?? 'GSTIN:'} $businessGstin', p.cols));
    }
    if (fssai) {
      lines.add(_centre('${labels?.fssai ?? 'FSSAI:'} $businessFssai', p.cols));
    }
    lines.add('-' * p.cols);

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
    lines.add('-' * p.cols);

    // Items header
    lines.add(_itemRow(p, labels?.colItem ?? 'Item', labels?.colQty ?? 'Qty',
        labels?.colPrice ?? 'Price', labels?.colTotal ?? 'Total'));
    lines.add('-' * p.cols);

    // Items
    for (final item in bill.items) {
      final name = item.itemName.length > p.nameCols
          ? item.itemName.substring(0, p.nameCols)
          : item.itemName;
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      lines.add(_itemRow(
        p,
        name,
        qty,
        item.unitPrice.toStringAsFixed(2),
        item.lineTotal.toStringAsFixed(2),
      ));
    }
    lines.add('-' * p.cols);

    // Totals
    lines.add(_twoCol(p, labels?.subtotal ?? 'Subtotal:',
        'Rs.${bill.subtotal.toStringAsFixed(2)}'));

    if (bill.taxAmount > 0) {
      if (gst) {
        // Intra-state split: CGST and SGST are each half the total tax.
        // The rate shown is the effective half-rate derived from the bill's
        // taxable value (subtotal) — e.g. 18% GST prints as CGST 9% / SGST 9%.
        final half = (bill.taxAmount / 2).toStringAsFixed(2);
        final halfRate = _halfGstRateLabel(bill);
        lines.add(_twoCol(p, '${labels?.cgst ?? 'CGST:'}$halfRate', 'Rs.$half'));
        lines.add(_twoCol(p, '${labels?.sgst ?? 'SGST:'}$halfRate', 'Rs.$half'));
      } else {
        lines.add(_twoCol(p,
            labels?.tax ?? 'Tax:', 'Rs.${bill.taxAmount.toStringAsFixed(2)}'));
      }
    }

    if (bill.discountAmount > 0) {
      lines.add(_twoCol(p, labels?.discount ?? 'Discount:',
          '-Rs.${bill.discountAmount.toStringAsFixed(2)}'));
    }

    lines.add(_twoCol(p, labels?.total ?? 'Grand Total:',
        'Rs.${grandTotal.toStringAsFixed(2)}'));

    lines.add(
        _twoCol(p, labels?.payment ?? 'Payment:', bill.paymentMode.toUpperCase()));
    lines.add('-' * p.cols);
    lines.add(_centre(labels?.thankYou ?? 'Thank you, visit again!', p.cols));

    return lines;
  }

  /// Build the receipt as STRUCTURED rows (columns + rules) for the raster
  /// path, so proportional Devanagari/Tamil glyphs align in a real table
  /// (Item / Qty / Price / Total) instead of overflowing space-padded columns.
  List<ReceiptRow> _buildReceiptRows(Bill bill, _ColProfile p,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      ReceiptLabels? labels}) {
    final grandTotal = bill.total - bill.discountAmount;
    final gst = businessGstin != null && businessGstin.isNotEmpty;
    final fssai = businessFssai != null && businessFssai.isNotEmpty;
    final rows = <ReceiptRow>[];

    // Header — order: name, address, phone, GSTIN, FSSAI. Only the business
    // name is always shown; every other line prints only when available.
    rows.add(ReceiptRow.center(
        businessName ?? labels?.defaultBusiness ?? 'BUSINESS',
        size: 34, bold: true));
    if (businessAddress != null && businessAddress.isNotEmpty) {
      // Split a multi-line/CRLF address into separate centred rows so each
      // physical line is centred (a single row with an embedded newline would
      // left-align the wrapped part). Raw (unpadded) lines — ReceiptRow.center
      // handles the centring for the raster path.
      for (final l in _wrapLines(businessAddress, p.cols)) {
        rows.add(ReceiptRow.center(l, size: 26));
      }
    }
    if (businessPhone != null && businessPhone.isNotEmpty) {
      rows.add(ReceiptRow.center(
          '${labels?.phonePrefix ?? 'Ph:'} $businessPhone', size: 26));
    }
    if (gst) {
      rows.add(ReceiptRow.center(
          '${labels?.gstin ?? 'GSTIN:'} $businessGstin', size: 26));
    }
    if (fssai) {
      rows.add(ReceiptRow.center(
          '${labels?.fssai ?? 'FSSAI:'} $businessFssai', size: 26));
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
      if (gst) {
        final half = (bill.taxAmount / 2).toStringAsFixed(2);
        final halfRate = _halfGstRateLabel(bill);
        rows.add(total('${labels?.cgst ?? 'CGST:'}$halfRate', 'Rs.$half'));
        rows.add(total('${labels?.sgst ?? 'SGST:'}$halfRate', 'Rs.$half'));
      } else {
        rows.add(total(labels?.tax ?? 'Tax:',
            'Rs.${bill.taxAmount.toStringAsFixed(2)}'));
      }
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
      String? businessGstin,
      String? businessFssai,
      ReceiptLabels? labels,
      int paperDots = 576}) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    // Column profile (ASCII path) and raster width both follow the paper width:
    // 384 dots → 58mm, otherwise 80mm.
    final profile = _profileForDots(paperDots);

    final lines = _buildReceiptLines(bill, profile,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        labels: labels);

    if (_hasNonAscii(lines)) {
      // The receipt contains at least one non-English character (Marathi,
      // Tamil, …) which the printer's ROM cannot render as text. Render the
      // whole receipt as a raster image with TRUE column alignment so every
      // glyph prints correctly and the table stays aligned.
      // Uses the proven transport: single write, no inter-chunk delay.
      final rows = _buildReceiptRows(bill, profile,
          businessName: businessName,
          businessPhone: businessPhone,
          businessAddress: businessAddress,
          businessGstin: businessGstin,
          businessFssai: businessFssai,
          labels: labels);
      final raster = await RasterLab.rowsToReceiptRaster(rows, width: paperDots);
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

  /// Prints several bills as SEPARATE receipts (never merged), one after
  /// another. Between bills it pauses so the printer's buffer fully drains and
  /// the BT link settles before the next job's connect/disconnect cycle —
  /// without this, back-to-back jobs collide and a later receipt prints garbage.
  Future<void> printBills(List<Bill> bills,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      ReceiptLabels? labels,
      int paperDots = 576}) async {
    for (var i = 0; i < bills.length; i++) {
      await printBill(bills[i],
          businessName: businessName,
          businessPhone: businessPhone,
          businessAddress: businessAddress,
          businessGstin: businessGstin,
          businessFssai: businessFssai,
          labels: labels,
          paperDots: paperDots);
      // Let the printer finish and the SPP link settle before the next job.
      if (i < bills.length - 1) {
        await Future.delayed(const Duration(milliseconds: 1200));
      }
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

  Future<void> testPrint({int paperDots = 576}) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    final cols = _profileForDots(paperDots).cols;
    final lines = [
      _centre('TEST PRINT', cols),
      '-' * cols,
      _centre('Printer is working!', cols),
      '-' * cols,
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
    String? subtitle,
    int copies = 1,
  }) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    // Render an actual Code128 barcode (with name/optional size/price/value) to
    // a 2-inch label image and print it as a raster. We use raster on BOTH
    // Windows and Bluetooth: the thermal printers in the field are ESC/POS, not
    // TSPL label printers, so a TSPL BARCODE command would print as literal text
    // instead of drawing bars. Raster draws the real barcode on any ESC/POS
    // printer. The label preserves its aspect ratio (labelImageToRaster) so the
    // bars aren't squashed.
    final image = await BarcodeImage.render(
      barcodeValue: barcodeValue,
      itemName: itemName,
      price: price,
      subtitle: subtitle,
    );
    final raster = await RasterLab.labelImageToRaster(image);
    image.dispose();

    for (var i = 0; i < copies; i++) {
      if (_isWindows) {
        await _printWindows(printer, raster);
      } else {
        await _sendClassicBtTuned(printer, raster, 0, 0);
      }
      if (i < copies - 1) {
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
  }

  /// Print a QR image (e.g. a table ordering QR) centred on the roll. The image
  /// is rasterised — works on both Windows and Classic-BT thermal printers.
  Future<void> printQrImage(ui.Image image) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');
    final raster = await RasterLab.imageToReceiptRaster(image);
    if (_isWindows) {
      await _printWindows(printer, raster);
    } else {
      await _sendClassicBtTuned(printer, raster, 0, 0);
    }
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

  /// Normalise CRLF/CR to LF, split into logical lines, and word-wrap each to
  /// [width]. Returns the raw (unpadded) lines. Used for the business address,
  /// which can be multi-line (e.g. "Street\r\nArea, City") and exceed one line.
  static List<String> _wrapLines(String text, int width) {
    final out = <String>[];
    for (final rawLine
        in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final words = line.split(RegExp(r'\s+'));
      var current = '';
      for (final w in words) {
        if (current.isEmpty) {
          current = w;
        } else if ((current.length + 1 + w.length) <= width) {
          current = '$current $w';
        } else {
          out.add(current);
          current = w;
        }
      }
      if (current.isNotEmpty) out.add(current);
    }
    return out;
  }

  /// Like [_wrapLines] but each line is space-padded so it centres on the
  /// ASCII text path (which has no printer-side alignment). Plain [_centre]
  /// would truncate a too-long address and lose the centring entirely.
  static List<String> _centreMultiline(String text, int width) =>
      _wrapLines(text, width).map((l) => _centre(l, width)).toList();

  /// 4-column item row sized to the profile: Name / Qty / Price / Total.
  static String _itemRow(
      _ColProfile prof, String name, String qty, String price, String total) {
    final n = name.padRight(prof.nameCols).substring(0, prof.nameCols);
    final q = qty.padLeft(prof.qtyCols);
    final pr = price.padLeft(prof.priceCols);
    final t = total.padLeft(prof.totalCols);
    return '$n$q$pr$t';
  }

  /// 2-column row: label left, value right, spanning the profile width.
  static String _twoCol(_ColProfile prof, String label, String value) =>
      _twoColN(label, value, prof.cols);

  /// 2-column row with explicit width
  static String _twoColN(String label, String value, int width) {
    final space = width - label.length - value.length;
    return '$label${' ' * (space < 1 ? 1 : space)}$value';
  }

  /// The half-GST-rate suffix shown next to CGST/SGST, e.g. " 9%".
  /// Derived from the bill's effective GST rate (tax / taxable value); CGST and
  /// SGST are each half of it. Returns '' when the rate can't be determined so
  /// the label degrades gracefully to just "CGST:".
  String _halfGstRateLabel(Bill bill) {
    if (bill.subtotal <= 0) return '';
    final effectiveRate = bill.taxAmount / bill.subtotal * 100;
    final half = effectiveRate / 2;
    if (half <= 0) return '';
    // Whole numbers print clean (9%), fractional keep one decimal (2.5%).
    final r = half % 1 == 0 ? half.toStringAsFixed(0) : half.toStringAsFixed(1);
    return ' $r%';
  }

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
