import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;
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
  final int gstCols;
  final int totalCols;
  const _ColProfile({
    required this.cols,
    required this.nameCols,
    required this.qtyCols,
    required this.priceCols,
    required this.gstCols,
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
  //   80mm → 46 chars: Name(14)|Qty(4)|Price(8)|GST%(6)|Total(10)
  //   58mm → 32 chars: Name(13)|Qty(3)|Price(6)|Total(7)
  // The 58mm price/total are 7 wide (not 6) so their padLeft keeps a leading
  // space — otherwise "220.00" fills the field and columns visually collide.
  // 58mm has gstCols: 0 — the narrow paper has no room for a fifth column, so
  // the GST% column is dropped there and the layout is unchanged from before.
  // -------------------------------------------------------------------------

  // Baseline profiles. These are STARTING points — _fitProfile() re-sizes the
  // item columns to each bill's actual values before rendering, so what prints
  // is usually wider in the name column than the numbers below.
  //
  // The data columns sum to `cols` MINUS one char per vertical separator
  // ('|' between each pair), so a full item row lands exactly on the paper
  // edge: 80mm → 14+4+8+6+10 = 42, +4 separators = 46.
  //        58mm → 13+3+6+0+7 = 29, +3 separators = 32.
  static const _ColProfile _cols80 = _ColProfile(
      cols: 46,
      nameCols: 14,
      qtyCols: 4,
      priceCols: 8,
      gstCols: 6,
      totalCols: 10);
  static const _ColProfile _cols58 = _ColProfile(
      cols: 32,
      nameCols: 13,
      qtyCols: 3,
      priceCols: 6,
      gstCols: 0,
      totalCols: 7);

  /// Resolve the column profile for a printable dot-width (384 → 58mm, else 80mm).
  static _ColProfile _profileForDots(int dots) => dots <= 384 ? _cols58 : _cols80;

  /// Fit the item-table columns to what this particular bill actually contains.
  ///
  /// The static profiles above are sized for the worst case ("1446.00"), which
  /// wastes space on the common bill where every price is two or three digits.
  /// Here each numeric column is shrunk to its widest ACTUAL value (never below
  /// its header, so the heading always fits) and every character saved is handed
  /// to the name column — the only column that benefits from extra room.
  ///
  /// The result always satisfies the profile invariant: data columns + one
  /// separator per gap == [_ColProfile.cols], so rows still end exactly on the
  /// paper edge.
  static _ColProfile _fitProfile(
      _ColProfile base, Bill bill, bool gstEnabled, ReceiptLabels? labels) {
    if (bill.items.isEmpty) return base;
    // The GST% column prints only when the paper has room for it AND GST is
    // actually in use. Sizing it on paper width alone left an empty column on
    // every bill after the GST toggle was switched off. It is also dropped when
    // GST is on but no item on this bill carries a rate, since the column would
    // be entirely blank.
    final withGst = base.gstCols > 0 &&
        gstEnabled &&
        bill.items.any((i) => _itemGstLabel(i, gstEnabled).isNotEmpty);

    // Widest rendered value per column, floored by the header width so the
    // column heading is never truncated.
    var qty = (labels?.colQty ?? 'Qty').length;
    var price = (labels?.colPrice ?? 'Price').length;
    var gst = withGst ? (labels?.colGst ?? 'GST%').length : 0;
    var total = (labels?.colTotal ?? 'Total').length;

    for (final item in bill.items) {
      final q = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      if (q.length > qty) qty = q.length;
      final pr = item.unitPrice.toStringAsFixed(2);
      if (pr.length > price) price = pr.length;
      if (withGst) {
        final g = _itemGstLabel(item, gstEnabled);
        if (g.length > gst) gst = g.length;
      }
      final t = (item.unitPrice * item.quantity).toStringAsFixed(2);
      if (t.length > total) total = t.length;
    }

    // Padding per numeric column. Two characters, not one: on the raster path
    // these counts become width FRACTIONS, and each cell also loses a fixed
    // pixel padding on both sides of its separator. A single space leaves a
    // narrow column (e.g. "230.00" in 7) close enough to the edge that the
    // proportional font can still wrap the last digit — which is exactly the
    // bug the fixed profiles were widened to fix. The ASCII path just gets a
    // slightly roomier column, which costs nothing.
    qty += 2;
    price += 2;
    if (withGst) gst += 2;
    total += 2;

    final separators = withGst ? 4 : 3;
    var name = base.cols - separators - qty - price - gst - total;

    // Extreme values (huge totals on narrow paper) can demand more width than
    // the paper has. Falling back to the static profile would be WRONG here —
    // its columns are narrower still, so padLeft would overflow and the row
    // would run past the paper edge and wrap. Instead pin the name column at
    // its minimum and take the shortfall out of the widest numeric column,
    // repeatedly, until the row fits. Values may end up truncated, but the
    // table stays aligned and every row is exactly `cols` wide.
    if (name < _minNameCols) {
      var deficit = _minNameCols - name;
      name = _minNameCols;
      while (deficit > 0) {
        // Shrink whichever numeric column is currently widest, never below the
        // room needed for a bare "0.00" plus its separator padding.
        final widest = [price, total, gst, qty].reduce((a, b) => a > b ? a : b);
        if (widest <= 5) break; // nothing left to give
        if (price == widest) {
          price--;
        } else if (total == widest) {
          total--;
        } else if (gst == widest) {
          gst--;
        } else {
          qty--;
        }
        deficit--;
      }
      // If the columns could not give up enough, absorb the rest from the name
      // column so the invariant (data + separators == cols) always holds.
      name -= deficit;
      if (name < 1) return base;
    }

    return _ColProfile(
        cols: base.cols,
        nameCols: name,
        qtyCols: qty,
        priceCols: price,
        gstCols: gst,
        totalCols: total);
  }

  /// Never shrink the item-name column below this many characters — beyond this
  /// point names wrap so aggressively the table stops being readable.
  static const int _minNameCols = 10;

  /// Build the receipt as a list of pre-formatted, column-aligned lines.
  /// Shared by both the ASCII text path and the raster path so the layout is
  /// identical regardless of which is used.
  /// Build the receipt and draw a box around the whole thing.
  ///
  /// The body is built at a width two characters narrower than the paper, then
  /// every line is framed with '|' and capped with a '+---+' rule top and
  /// bottom. Building narrow first means all the layout logic below (column
  /// fitting, centring, name wrapping) is unchanged and simply works inside the
  /// box.
  // Retained for the commented-out ASCII text path in printBill().
  // ignore: unused_element
  List<String> _buildReceiptLines(Bill bill, _ColProfile basep,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      bool gstEnabled = true,
      ReceiptLabels? labels}) {
    final inner = _ColProfile(
      cols: basep.cols - 2,
      nameCols: basep.nameCols - 2,
      qtyCols: basep.qtyCols,
      priceCols: basep.priceCols,
      gstCols: basep.gstCols,
      totalCols: basep.totalCols,
    );
    // Too narrow to frame (shouldn't happen on 58/80mm, but keep the receipt
    // printable rather than emitting a broken box).
    if (inner.nameCols < 1) {
      return _buildReceiptBody(bill, basep,
          businessName: businessName,
          businessPhone: businessPhone,
          businessAddress: businessAddress,
          businessGstin: businessGstin,
          businessFssai: businessFssai,
          gstEnabled: gstEnabled,
          labels: labels);
    }

    final body = _buildReceiptBody(bill, inner,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        gstEnabled: gstEnabled,
        labels: labels);

    final edge = '+${'-' * inner.cols}+';
    final divider = '-' * inner.cols;
    final out = <String>[edge];
    for (final l in body) {
      // A full-width horizontal rule meets the frame at a '+' junction rather
      // than butting into the '|' edges.
      if (l == divider) {
        out.add(edge);
        continue;
      }
      // The bold marker must stay at the START of the line for the ESC/POS
      // emphasis wrapper to find it, so lift it outside the frame.
      if (l.startsWith(_boldLineMarker)) {
        final text = l.substring(_boldLineMarker.length);
        out.add('$_boldLineMarker|${_exact(text, inner.cols)}|');
      } else {
        out.add('|${_exact(l, inner.cols)}|');
      }
    }
    out.add(edge);
    return out;
  }

  /// Pad or trim [s] to exactly [width] characters so the frame's right edge
  /// lands in the same column on every line.
  static String _exact(String s, int width) =>
      s.length >= width ? s.substring(0, width) : s.padRight(width);

  List<String> _buildReceiptBody(Bill bill, _ColProfile basep,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      bool gstEnabled = true,
      ReceiptLabels? labels}) {
    // Size the item columns to this bill's actual values, giving the slack to
    // the name column. Falls back to the static profile when it can't improve.
    final p = _fitProfile(basep, bill, gstEnabled, labels);
    // GSTIN is passed only when GST is enabled — its presence gates the
    // GSTIN line + the CGST/SGST split. Without it the receipt is as before.
    final gst = businessGstin != null && businessGstin.isNotEmpty;
    // Master GST toggle. When off, tax is ignored ENTIRELY — no tax line prints
    // and the tax is stripped from the payable, even for an older bill whose
    // stored tax_amount is non-zero from when GST was on. This keeps the printed
    // Grand Total equal to the Net Payable shown on the order card.
    final showTax = gstEnabled && bill.taxAmount > 0;
    // Grand total is the final payable: total - discount + round_off, less any
    // tax that must be ignored because GST is off.
    final grandTotal =
        bill.grandTotal - (gstEnabled ? 0.0 : bill.taxAmount);
    final fssai = businessFssai != null && businessFssai.isNotEmpty;
    final lines = <String>[];

    // Header — order: name, address, phone, GSTIN, FSSAI. Only the business
    // name is always shown; every other line prints only when available.
    //
    // The business name is printed BOLD (same normal size and centring as
    // before). It's tagged with [_boldLineMarker] so _linesToAsciiBytes wraps it
    // in the ESC/POS emphasis on/off commands. It's space-centred normally here
    // (bold doesn't change the character cell width, so the padding still lines
    // up).
    lines.add(_boldLineMarker +
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
    lines.add('${labels?.billNo ?? 'Bill#:'} ${bill.displayNumber}');
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

    // Items header — titles centred in their columns.
    lines.add(_itemRow(
        p,
        labels?.colItem ?? 'Item',
        labels?.colQty ?? 'Qty',
        labels?.colPrice ?? 'Price',
        labels?.colGst ?? 'GST%',
        labels?.colTotal ?? 'Total',
        heading: true));
    lines.add('-' * p.cols);

    // Items
    for (var i = 0; i < bill.items.length; i++) {
      final item = bill.items[i];
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      // Wrap the name within its column instead of truncating, so a long name
      // prints in full across several lines while staying inside the name
      // column (qty/price/total sit on the first line only).
      final nameLines = _wrapNameToCol(item.itemName, p.nameCols);
      final firstName = nameLines.isEmpty ? '' : nameLines.first;
      // Total column shows the NET line price (unit price × qty, before tax) —
      // consistent for retail and restaurant. Tax is summed once at the bottom.
      final netLine = item.unitPrice * item.quantity;
      lines.add(_itemRow(
        p,
        firstName,
        qty,
        item.unitPrice.toStringAsFixed(2),
        _itemGstLabel(item, gstEnabled),
        netLine.toStringAsFixed(2),
      ));
      // Continuation lines: remaining name segments, name column only.
      for (final cont in nameLines.skip(1)) {
        lines.add(_itemRow(p, cont, '', '', '', ''));
      }
      // Separator between items. Skipped after the last one — the rule that
      // closes the table below already provides it.
      if (i < bill.items.length - 1) lines.add('-' * p.cols);
    }
    lines.add('-' * p.cols);

    // Totals — order: Sub Total, Discount, then tax (CGST/SGST when GST is on),
    // Round Off, Grand Total. Discount is shown before tax because it reduces the
    // taxable amount; tax is charged on the discounted net. When GST is off,
    // bill.taxAmount is 0 (tax ignored entirely) so no tax line prints.
    lines.add(_twoCol(p, labels?.subtotal ?? 'Subtotal:',
        'Rs.${bill.subtotal.toStringAsFixed(2)}'));

    if (bill.discountAmount > 0) {
      lines.add(_twoCol(p, labels?.discount ?? 'Discount:',
          '-Rs.${bill.discountAmount.toStringAsFixed(2)}'));
    }

    if (showTax) {
      if (gst) {
        // Intra-state split: CGST and SGST are each half the total tax.
        // Only the amount is printed — the percentage is deliberately omitted
        // (the per-item GST% column already shows the rate).
        final (cgst, sgst) = _gstHalves(bill.taxAmount);
        lines.add(_twoCol(p, labels?.cgst ?? 'CGST:', 'Rs.$cgst'));
        lines.add(_twoCol(p, labels?.sgst ?? 'SGST:', 'Rs.$sgst'));
      } else {
        lines.add(_twoCol(p,
            labels?.tax ?? 'Tax:', 'Rs.${bill.taxAmount.toStringAsFixed(2)}'));
      }
    }

    if (bill.roundOff != 0) {
      final sign = bill.roundOff < 0 ? '-' : '+';
      lines.add(_twoCol(p, labels?.roundOff ?? 'Round Off:',
          '${sign}Rs.${bill.roundOff.abs().toStringAsFixed(2)}'));
    }

    lines.add(_twoCol(p, labels?.total ?? 'Grand Total:',
        'Rs.${grandTotal.toStringAsFixed(2)}'));

    lines.add(
        _twoCol(p, labels?.payment ?? 'Payment:', bill.paymentMode.toUpperCase()));
    lines.add('-' * p.cols);
    lines.add(_centre(labels?.thankYou ?? 'Thank you, visit again!', p.cols));
    // Brand line under the thank-you note. The plain-text path has no per-line
    // font sizing, so it prints at normal size (the raster path renders it small).
    lines.add(_centre(labels?.poweredBy ?? 'Powered by Vengurlatech', p.cols));

    return lines;
  }

  /// Build the receipt as STRUCTURED rows (columns + rules) for the raster
  /// path, so proportional Devanagari/Tamil glyphs align in a real table
  /// (Item / Qty / Price / Total) instead of overflowing space-padded columns.
  List<ReceiptRow> _buildReceiptRows(Bill bill, _ColProfile basep,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      bool gstEnabled = true,
      ReceiptLabels? labels}) {
    // Same content-fitted columns as the ASCII path, so both renderings of a
    // given bill divide the paper identically.
    final p = _fitProfile(basep, bill, gstEnabled, labels);
    final gst = businessGstin != null && businessGstin.isNotEmpty;
    // GST off → tax ignored entirely: no tax line, and the stored tax is
    // stripped from the payable (see _buildReceiptLines for the rationale).
    final showTax = gstEnabled && bill.taxAmount > 0;
    // Grand total is the final payable: total - discount + round_off, less any
    // tax that must be ignored because GST is off.
    final grandTotal =
        bill.grandTotal - (gstEnabled ? 0.0 : bill.taxAmount);
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
      ReceiptCell('${labels?.billNo ?? 'Bill#:'} ${bill.displayNumber}',
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

    // Item table:
    // Column fractions are derived from the content-fitted character widths
    // above, so a bill of small numbers gives its spare width to the item name
    // instead of padding the numeric columns. The separators consume no
    // fraction of their own (they are drawn ON the boundaries), so the
    // character counts are scaled by the data columns only.
    final showGstCol = p.gstCols > 0;
    final dataCols =
        p.nameCols + p.qtyCols + p.priceCols + p.gstCols + p.totalCols;
    double fr(int cols) => cols / dataCols;
    // [heading] centres every cell — used for the column-title row only. Data
    // rows keep their natural alignment (name left, numbers right) so the
    // digits still line up on the decimal.
    ReceiptRow itemRow(String n, String q, String pr, String g, String t,
            {bool bold = false, bool heading = false}) =>
        ReceiptRow.cols([
          ReceiptCell(n,
              align: heading ? TextAlign.center : TextAlign.left,
              widthFraction: fr(p.nameCols)),
          ReceiptCell(q, align: TextAlign.center, widthFraction: fr(p.qtyCols)),
          ReceiptCell(pr,
              align: heading ? TextAlign.center : TextAlign.right,
              widthFraction: fr(p.priceCols)),
          if (showGstCol)
            ReceiptCell(g,
                align: heading ? TextAlign.center : TextAlign.right,
                widthFraction: fr(p.gstCols)),
          ReceiptCell(t,
              align: heading ? TextAlign.center : TextAlign.right,
              widthFraction: fr(p.totalCols)),
        ], size: 26, bold: bold, verticalRules: true);

    rows.add(itemRow(
        labels?.colItem ?? 'Item',
        labels?.colQty ?? 'Qty',
        labels?.colPrice ?? 'Price',
        labels?.colGst ?? 'GST%',
        labels?.colTotal ?? 'Total',
        bold: true,
        heading: true));
    rows.add(ReceiptRow.rule());

    for (var i = 0; i < bill.items.length; i++) {
      final item = bill.items[i];
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      // Total column shows the NET line price (unit price × qty, before tax) —
      // consistent for retail and restaurant. Tax is summed once at the bottom.
      final netLine = item.unitPrice * item.quantity;
      rows.add(itemRow(
        item.itemName,
        qty,
        item.unitPrice.toStringAsFixed(2),
        _itemGstLabel(item, gstEnabled),
        netLine.toStringAsFixed(2),
      ));
      // Separator between items, so each line item reads as its own row of the
      // table. The last item is skipped — the rule that closes the table below
      // already provides it, and emitting both would double the line.
      if (i < bill.items.length - 1) {
        rows.add(ReceiptRow.rule(light: true));
      }
    }
    rows.add(ReceiptRow.rule());

    // Totals (label left, amount right)
    ReceiptRow total(String l, String r, {bool bold = false, double size = 22}) =>
        ReceiptRow.cols([
          ReceiptCell(l, widthFraction: 0.55),
          ReceiptCell(r, align: TextAlign.right, widthFraction: 0.45),
        ], size: size, bold: bold);

    // Order: Sub Total, Discount, then tax (CGST/SGST when GST on), Round Off,
    // Grand Total. Discount precedes tax because tax is charged on the discounted
    // net. GST off → bill.taxAmount is 0, so no tax line prints.
    rows.add(total(labels?.subtotal ?? 'Subtotal:',
        'Rs.${bill.subtotal.toStringAsFixed(2)}'));
    if (bill.discountAmount > 0) {
      rows.add(total(labels?.discount ?? 'Discount:',
          '-Rs.${bill.discountAmount.toStringAsFixed(2)}'));
    }
    if (showTax) {
      if (gst) {
        // Amount only — the percentage is deliberately omitted (the per-item
        // GST% column already shows the rate).
        final (cgst, sgst) = _gstHalves(bill.taxAmount);
        rows.add(total(labels?.cgst ?? 'CGST:', 'Rs.$cgst'));
        rows.add(total(labels?.sgst ?? 'SGST:', 'Rs.$sgst'));
      } else {
        rows.add(total(labels?.tax ?? 'Tax:',
            'Rs.${bill.taxAmount.toStringAsFixed(2)}'));
      }
    }
    if (bill.roundOff != 0) {
      final sign = bill.roundOff < 0 ? '-' : '+';
      rows.add(total(labels?.roundOff ?? 'Round Off:',
          '${sign}Rs.${bill.roundOff.abs().toStringAsFixed(2)}'));
    }
    rows.add(total(labels?.total ?? 'Grand Total:',
        'Rs.${grandTotal.toStringAsFixed(2)}',
        bold: true, size: 32));
    rows.add(total(labels?.payment ?? 'Payment:',
        bill.paymentMode.toUpperCase()));
    rows.add(ReceiptRow.rule());
    rows.add(ReceiptRow.center(
        labels?.thankYou ?? 'Thank you, visit again!', size: 26));
    // Small italic brand line under the thank-you note.
    rows.add(ReceiptRow.center(labels?.poweredBy ?? 'Powered by Vengurlatech',
        size: 18, italic: true));

    return rows;
  }

  /// Sentinel prefix on a receipt line meaning "print this BOLD" via the ESC/POS
  /// emphasis commands (no size or alignment change). Used for the business name
  /// so it stands out on the plain-text receipt. It's a control char (0x01) that
  /// never appears in real receipt text.
  static const String _boldLineMarker = '\x01';

  /// Pack ASCII-only receipt [lines] into plain ESC/POS text bytes (fast path).
  /// Retained for the commented-out ASCII text path in printBill().
  // ignore: unused_element
  List<int> _linesToAsciiBytes(List<String> lines) {
    // ESC/POS emphasis (bold) on/off.
    const emphOn = [0x1B, 0x45, 0x01]; // ESC E 1
    const emphOff = [0x1B, 0x45, 0x00]; // ESC E 0

    final bytes = <int>[];
    for (final line in lines) {
      if (line.startsWith(_boldLineMarker)) {
        // Bold line (business name), already space-centred by the caller. Bold
        // doesn't change the character cell width, so nothing else shifts — just
        // wrap the text in emphasis on/off.
        final text = line.substring(_boldLineMarker.length);
        bytes.addAll(emphOn);
        for (final c in text.codeUnits) {
          bytes.add(c > 127 ? 63 : c);
        }
        bytes.addAll(emphOff);
        bytes.add(0x0A); // LF
        continue;
      }
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
  /// Retained for the commented-out ASCII text path in printBill().
  // ignore: unused_element
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

  /// Build an on-screen PNG preview of [bill]'s thermal receipt — the exact
  /// layout that would print, rendered through the same raster pipeline. Does
  /// NOT touch the printer, so it works with no printer paired. [paperDots]
  /// selects the width (384 → 58mm, else 80mm).
  Future<Uint8List> buildReceiptPreviewPng(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      bool gstEnabled = true,
      ReceiptLabels? labels,
      int paperDots = 576}) async {
    final profile = _profileForDots(paperDots);
    final rows = _buildReceiptRows(bill, profile,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        gstEnabled: gstEnabled,
        labels: labels);
    return RasterLab.receiptPreviewPng(rows, width: paperDots);
  }

  Future<void> printBill(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      bool gstEnabled = true,
      ReceiptLabels? labels,
      int paperDots = 576}) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    // Column profile (ASCII path) and raster width both follow the paper width:
    // 384 dots → 58mm, otherwise 80mm.
    final profile = _profileForDots(paperDots);

    // Building the ASCII lines is only needed by the commented-out text path
    // below; skip the work while raster printing is in force.
    //
    // final lines = _buildReceiptLines(bill, profile,
    //     businessName: businessName,
    //     businessPhone: businessPhone,
    //     businessAddress: businessAddress,
    //     businessGstin: businessGstin,
    //     businessFssai: businessFssai,
    //     gstEnabled: gstEnabled,
    //     labels: labels);

    // ALL receipts — English included — now print as a raster image. The image
    // path is the only one that can draw the real table (vertical column rules,
    // the outer border) and it renders proportional fonts, so English bills get
    // the same layout as Marathi/Tamil instead of a space-padded approximation.
    //
    // The English ESC/POS text path is kept below, commented out, because it is
    // measurably faster on Bluetooth and is the fallback if raster printing
    // turns out to be too slow on some hardware.
    final rows = _buildReceiptRows(bill, profile,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        gstEnabled: gstEnabled,
        labels: labels);
    final raster = await RasterLab.rowsToReceiptRaster(rows, width: paperDots);
    if (_isWindows) {
      await _printWindows(printer, raster);
    } else {
      await _sendClassicBtTuned(printer, raster, 0, 0);
    }

    // --- Previous behaviour: raster only for non-English, ASCII text for -----
    // --- English. Restore this block to go back to text printing.        -----
    //
    // if (_hasNonAscii(lines)) {
    //   // The receipt contains at least one non-English character (Marathi,
    //   // Tamil, …) which the printer's ROM cannot render as text. Render the
    //   // whole receipt as a raster image with TRUE column alignment so every
    //   // glyph prints correctly and the table stays aligned.
    //   // Uses the proven transport: single write, no inter-chunk delay.
    //   final rows = _buildReceiptRows(bill, profile,
    //       businessName: businessName,
    //       businessPhone: businessPhone,
    //       businessAddress: businessAddress,
    //       businessGstin: businessGstin,
    //       businessFssai: businessFssai,
    //       gstEnabled: gstEnabled,
    //       labels: labels);
    //   final raster = await RasterLab.rowsToReceiptRaster(rows, width: paperDots);
    //   if (_isWindows) {
    //     await _printWindows(printer, raster);
    //   } else {
    //     await _sendClassicBtTuned(printer, raster, 0, 0);
    //   }
    // } else {
    //   // Pure English/numbers → fast native ESC/POS text.
    //   await _printBytes(printer, _linesToAsciiBytes(lines));
    // }
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
      bool gstEnabled = true,
      ReceiptLabels? labels,
      int paperDots = 576}) async {
    for (var i = 0; i < bills.length; i++) {
      await printBill(bills[i],
          businessName: businessName,
          businessPhone: businessPhone,
          businessAddress: businessAddress,
          businessGstin: businessGstin,
          businessFssai: businessFssai,
          gstEnabled: gstEnabled,
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

  /// Word-wrap an item name to [width] columns, hard-breaking any single word
  /// that is itself longer than [width] (e.g. a run-on name with no spaces).
  /// Unlike [_wrapLines], this guarantees no returned segment exceeds [width],
  /// so the whole name prints in full without being truncated by the column.
  static List<String> _wrapNameToCol(String name, int width) {
    if (width <= 0) return [name];
    final out = <String>[];
    var current = '';
    for (final word in name.trim().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      // A word longer than the column: flush the current line, then emit the
      // word in width-sized chunks (the last chunk becomes the new current).
      if (word.length > width) {
        if (current.isNotEmpty) {
          out.add(current);
          current = '';
        }
        var rest = word;
        while (rest.length > width) {
          out.add(rest.substring(0, width));
          rest = rest.substring(width);
        }
        current = rest;
        continue;
      }
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        out.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) out.add(current);
    return out.isEmpty ? [''] : out;
  }

  /// Like [_wrapLines] but each line is space-padded so it centres on the
  /// ASCII text path (which has no printer-side alignment). Plain [_centre]
  /// would truncate a too-long address and lose the centring entirely.
  static List<String> _centreMultiline(String text, int width) =>
      _wrapLines(text, width).map((l) => _centre(l, width)).toList();

  /// Item row sized to the profile: Name / Qty / Price / [GST%] / Total.
  /// The GST% column is emitted only when the profile allows room for it
  /// (gstCols > 0) — 58mm paper keeps the original 4-column layout.
  ///
  /// Set [heading] for the column-title row: every cell is centred in its
  /// column instead of the data alignment (name left, numbers right).
  static String _itemRow(_ColProfile prof, String name, String qty,
      String price, String gst, String total, {bool heading = false}) {
    // padLeft only ever GROWS a string, so a value wider than its column would
    // push the row past the paper edge and wrap. Keep the last `width` chars
    // (the least significant digits) so the row width is guaranteed.
    String fixed(String v, int width) {
      final p = v.padLeft(width);
      return p.length <= width ? p : p.substring(p.length - width);
    }

    // Centre within an exact-width field: split the slack, extra space on the
    // right so a column with odd slack leans left rather than drifting right.
    String mid(String v, int width) {
      if (v.length >= width) return v.substring(0, width);
      final left = (width - v.length) ~/ 2;
      return (' ' * left + v).padRight(width);
    }

    final n = heading
        ? mid(name, prof.nameCols)
        : name.padRight(prof.nameCols).substring(0, prof.nameCols);
    final q = heading ? mid(qty, prof.qtyCols) : fixed(qty, prof.qtyCols);
    final pr =
        heading ? mid(price, prof.priceCols) : fixed(price, prof.priceCols);
    final g = prof.gstCols > 0
        ? (heading ? mid(gst, prof.gstCols) : fixed(gst, prof.gstCols))
        : '';
    final t =
        heading ? mid(total, prof.totalCols) : fixed(total, prof.totalCols);
    // Vertical separators between columns. The profile's column widths already
    // reserve room for these (they sum to cols minus the separator count), so
    // the row still ends exactly at the paper edge and never wraps.
    return prof.gstCols > 0
        ? '$n|$q|$pr|$g|$t'
        : '$n|$q|$pr|$t';
  }

  /// 2-column row: label left, value right, spanning the profile width.
  static String _twoCol(_ColProfile prof, String label, String value) =>
      _twoColN(label, value, prof.cols);

  /// 2-column row with explicit width
  static String _twoColN(String label, String value, int width) {
    final space = width - label.length - value.length;
    return '$label${' ' * (space < 1 ? 1 : space)}$value';
  }

  /// Split [tax] into the CGST and SGST halves that PRINT, as (cgst, sgst)
  /// strings already fixed to 2 decimals.
  ///
  /// Naively printing (tax / 2) twice loses or gains a paisa whenever the tax
  /// has an odd number of paise — 0.95 prints as 0.47 + 0.47 = 0.94 — so the
  /// receipt's Subtotal + CGST + SGST then disagrees with its Grand Total by
  /// 0.01. Rounding in paise and giving the remainder to CGST guarantees the
  /// two halves always add back to exactly [tax].
  static (String, String) _gstHalves(double tax) {
    final paise = (tax * 100).round();
    final cgst = (paise + 1) ~/ 2; // takes the odd paisa
    final sgst = paise ~/ 2;
    return (
      (cgst / 100).toStringAsFixed(2),
      (sgst / 100).toStringAsFixed(2),
    );
  }

  /// The per-item GST% cell, e.g. "5.00". Empty when GST is off or the item
  /// carries no tax rate, so the column simply stays blank on that row rather
  /// than printing a misleading 0.
  static String _itemGstLabel(BillItem item, bool gstEnabled) {
    if (!gstEnabled) return '';
    final rate = item.taxRate;
    if (rate == null || rate <= 0) return '';
    return rate.toStringAsFixed(2);
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
