import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

// On Windows we still fall back to flutter_thermal_printer (BLE/USB).
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart'
    as ftp show FlutterThermalPrinter;
import 'package:flutter_thermal_printer/utils/printer.dart'
    as ftp show Printer, ConnectionType;

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
// Windows        → flutter_thermal_printer (BLE / USB via win_ble / win32)
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
      await ftpInstance.devicesStream.first.timeout(
        const Duration(seconds: 4),
        onTimeout: () => <ftp.Printer>[],
      ).then((devices) {
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
  // Receipt building — TSPL commands for JPL/label mode thermal printers
  //
  // Paper: 72 mm wide, continuous (no gap). Each TEXT command positions
  // text at absolute Y coordinate (dots, 8 dots/mm ≈ 203 dpi).
  // Font "3" = fixed 16×26 dot font (~12pt), fits ~42 chars on 72mm.
  // -------------------------------------------------------------------------

  static const int _cols = 42; // chars that fit on 72mm with font "3"
  static const int _lineSpacing = 30; // dots between lines
  static const int _paperWidth = 72; // mm
  static const String _font = '3';

  List<int> _buildReceipt(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress}) {
    // Build all text lines first so we know the total height
    final lines = <String>[];

    lines.add(_centre(businessName ?? 'BUSINESS', _cols));
    if (businessAddress != null && businessAddress.isNotEmpty) {
      lines.add(_centre(businessAddress, _cols));
    }
    if (businessPhone != null && businessPhone.isNotEmpty) {
      lines.add(_centre('Ph: $businessPhone', _cols));
    }
    lines.add('-' * _cols);
    lines.add('Bill#: ${bill.billNumber}');
    lines.add('Date : ${_formatDate(bill.createdAt.toLocal())}');
    if (bill.customerName != null && bill.customerName!.isNotEmpty) {
      lines.add('Cust : ${bill.customerName}');
    }
    if (bill.customerPhone != null && bill.customerPhone!.isNotEmpty) {
      lines.add('Ph   : ${bill.customerPhone}');
    }
    lines.add('-' * _cols);
    lines.add(_colLine('Item', 'Qty', 'Price', 'Total'));
    lines.add('-' * _cols);
    for (final item in bill.items) {
      final name =
          item.itemName.length > 18 ? item.itemName.substring(0, 18) : item.itemName;
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      lines.add(_colLine(
        name,
        qty,
        item.unitPrice.toStringAsFixed(2),
        item.lineTotal.toStringAsFixed(2),
      ));
    }
    lines.add('-' * _cols);
    if (bill.taxAmount > 0) {
      lines.add(_twoCol('Subtotal:', bill.subtotal.toStringAsFixed(2)));
      lines.add(_twoCol('Tax     :', bill.taxAmount.toStringAsFixed(2)));
    }
    lines.add(_twoCol('TOTAL:', 'Rs.${bill.total.toStringAsFixed(2)}'));
    lines.add(_twoCol('Payment:', bill.paymentMode.toUpperCase()));
    lines.add('-' * _cols);
    lines.add(_centre('Thank you, visit again!', _cols));
    lines.add(''); // blank line at bottom

    // Calculate total height in dots (+20 for bottom margin)
    final totalHeight = lines.length * _lineSpacing + 20;

    // Build TSPL command string
    final sb = StringBuffer();
    sb.write('SIZE $_paperWidth mm,$totalHeight\r\n');
    sb.write('GAP 0 mm,0 mm\r\n');
    sb.write('CODEPAGE 437\r\n');
    sb.write('CLS\r\n');

    int y = 10;
    for (final line in lines) {
      // Escape double-quotes in text
      final escaped = line.replaceAll('"', '\\"');
      sb.write('TEXT 10,$y,"$_font",0,1,1,"$escaped"\r\n');
      y += _lineSpacing;
    }

    sb.write('PRINT 1,1\r\n');

    return _enc(sb.toString());
  }

  /// Encode string to Latin-1 bytes (covers all standard ASCII + extended)
  static List<int> _enc(String s) =>
      s.codeUnits.map((c) => c > 255 ? 0x3F : c).toList(); // ? for non-latin

  /// Centre text within a given column width
  static String _centre(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final pad = (width - text.length) ~/ 2;
    return ' ' * pad + text;
  }

  /// 4-column row: name(18), qty(5), price(9), total(10) = 42 chars
  static String _colLine(String name, String qty, String price, String total) {
    final n = name.padRight(18).substring(0, 18);
    final q = qty.padLeft(5);
    final p = price.padLeft(9);
    final t = total.padLeft(10);
    return '$n$q$p$t';
  }

  /// 2-column row: label left, value right
  static String _twoCol(String label, String value) {
    final space = _cols - label.length - value.length;
    return '$label${' ' * (space < 1 ? 1 : space)}$value';
  }

  // -------------------------------------------------------------------------
  // Printing
  // -------------------------------------------------------------------------

  Future<void> printBill(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress}) async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');
    final bytes = _buildReceipt(bill,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress);
    await _printBytes(printer, bytes);
  }

  Future<void> testPrint() async {
    final printer = await getActivePrinter();
    if (printer == null) throw PrinterException('No printer configured');

    const cmd =
        'SIZE 72 mm,120\r\n'
        'GAP 0 mm,0 mm\r\n'
        'CODEPAGE 437\r\n'
        'CLS\r\n'
        'TEXT 10,10,"3",0,1,1,"   TEST PRINT"\r\n'
        'TEXT 10,40,"3",0,1,1,"Printer is working correctly"\r\n'
        'TEXT 10,70,"3",0,1,1,"--------------------------------"\r\n'
        'PRINT 1,1\r\n';
    await _printBytes(printer, _enc(cmd));
  }

  Future<void> _printBytes(Printer printer, List<int> bytes) async {
    if (_isWindows) {
      await _printWindows(printer, bytes);
    } else {
      await _printClassicBt(printer, bytes);
    }
  }

  Future<void> _printClassicBt(Printer printer, List<int> bytes) async {
    if (printer.address == null) {
      throw PrinterException('Printer address not set');
    }
    try {
      // Check permission first
      final permitted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!permitted) throw PrinterException('Bluetooth permission not granted');

      // Check Bluetooth is on
      final btOn = await PrintBluetoothThermal.bluetoothEnabled;
      if (!btOn) throw PrinterException('Bluetooth is turned off');

      // Disconnect any existing connection first
      final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
      if (alreadyConnected) {
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Connect
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: printer.address!,
      );
      if (!connected) {
        throw PrinterException(
            'Could not connect to printer. Make sure it is powered on and paired.');
      }

      // Wait for connection to stabilise (2s matches reference implementation)
      await Future.delayed(const Duration(seconds: 2));

      final isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        throw PrinterException('Printer disconnected after connect. Try again.');
      }

      // Send in 512-byte chunks — many printers drop data if sent all at once
      const chunkSize = 512;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final chunk = bytes.sublist(i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
        final result = await PrintBluetoothThermal.writeBytes(chunk);
        if (!result) throw PrinterException('Bytes sent but printer did not respond');
        if (i + chunkSize < bytes.length) {
          await Future.delayed(const Duration(milliseconds: 50));
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
      await ftpInstance.printData(ftpPrinter, bytes, longData: true);
    } catch (e) {
      if (e is PrinterException) rethrow;
      throw PrinterException(e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final mo = _monthName(dt.month);
    final h = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$d-$mo-${dt.year} $h:$mi $ampm';
  }

  String _monthName(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

class PrinterException implements Exception {
  final String message;
  PrinterException(this.message);

  @override
  String toString() => message;
}
