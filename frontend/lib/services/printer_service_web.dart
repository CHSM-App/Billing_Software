// Web stub for PrinterService — printing is not supported in the browser.
// All methods throw PrinterException so the UI can handle gracefully.

import 'dart:convert';
import 'dart:ui' as ui show Image;
import 'package:flutter/foundation.dart' show ValueNotifier;
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

  /// Ticks whenever the active printer changes — kept for parity with the
  /// native service so canPrintProvider can listen the same way on all targets.
  final ValueNotifier<int> activePrinterRevision = ValueNotifier<int>(0);

  Future<List<Printer>> listPrinters() async => [];

  Future<void> setActivePrinter(Printer printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(printer.toJson()));
    activePrinterRevision.value++;
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

  /// Printing is unsupported in the browser, so a print can never succeed.
  Future<bool> canPrint() async => false;

  Future<void> clearActivePrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    activePrinterRevision.value++;
  }

  Future<void> printBill(Bill bill,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
      dynamic labels}) async {
    throw PrinterException('Printing is not supported in the browser.');
  }

  Future<void> printBills(List<Bill> bills,
      {String? businessName,
      String? businessPhone,
      String? businessAddress,
      String? businessGstin,
      String? businessFssai,
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
    String? subtitle,
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
