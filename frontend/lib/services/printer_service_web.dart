// Web stub for PrinterService — printing is not supported in the browser.
// All methods throw PrinterException so the UI can handle gracefully.

import 'dart:convert';
import 'dart:ui' as ui show Image;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

export 'printer_service_web.dart'
    show ConnectionType, Printer, PrinterService, PrinterException;

enum ConnectionType { ble, usb, classicBt }

class Printer {
  final String? name;
  final String? address;
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
        'ble'       => ConnectionType.ble,
        'usb'       => ConnectionType.usb,
        _           => null,
      };
}

const _prefKey = 'active_printer';

class PrinterService {
  PrinterService._();
  static final PrinterService instance = PrinterService._();

  Future<List<Printer>> listPrinters() async => [];

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

  Future<void> printBill(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      dynamic labels}) async {
    throw PrinterException('Printing is not supported in the browser.');
  }

  Future<void> printBills(List<Bill> bills,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      dynamic labels}) async {
    throw PrinterException('Printing is not supported in the browser.');
  }

  Future<void> testPrint() async {
    throw PrinterException('Printing is not supported in the browser.');
  }

  Future<void> printRawBytes(List<int> bytes, {bool slow = false}) async {
    throw PrinterException('Printing is not supported in the browser.');
  }

  Future<void> printRawBytesTuned(
    List<int> bytes, {
    required int chunkSize,
    required int delayMs,
  }) async {
    throw PrinterException('Printing is not supported in the browser.');
  }

  Future<void> printBarcodeLabel({
    required String barcodeValue,
    required String itemName,
    required double price,
    int copies = 1,
  }) async {
    throw PrinterException('Printing is not supported in the browser.');
  }

  Future<void> printQrImage(ui.Image image) async {
    throw PrinterException('Printing is not supported in the browser.');
  }
}

class PrinterException implements Exception {
  final String message;
  PrinterException(this.message);

  @override
  String toString() => message;
}
