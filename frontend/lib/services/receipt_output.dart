import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../storage.dart';
import 'printer_service.dart';
import 'receipt_labels.dart';
import 'invoice_pdf.dart';

/// A rendered preview of a bill, in whichever form matches the chosen paper
/// size: a thermal receipt bitmap ([isPdf] == false) or an A5/A4 PDF invoice
/// ([isPdf] == true). The UI shows the PNG as an image or the PDF in a viewer.
class ReceiptPreview {
  final Uint8List bytes;
  final bool isPdf;
  const ReceiptPreview({required this.bytes, required this.isPdf});
}

/// Single decision point for emitting a bill's receipt/invoice according to the
/// user's chosen paper size:
///   • 'mm58' / 'mm80' → thermal ESC/POS via [PrinterService.printBills]
///   • 'a5'   / 'a4'   → an A5/A4 PDF invoice opened in the OS print dialog
///
/// All three billing callsites (finalize, history reprint, credit settle)
/// gather the same header fields, so they route through here to stay identical.
class ReceiptOutput {
  /// True when the currently-selected paper size is a PDF page size (A5/A4),
  /// i.e. NOT a thermal roll. Callsites use this to decide whether an active
  /// thermal printer is required before emitting.
  static Future<bool> isPdfSelected() async {
    final size = await getPaperSize();
    return !PaperSizes.isThermal(size);
  }

  /// Emit [bills]. For thermal sizes each bill prints as its own receipt; for
  /// PDF sizes all bills are combined into one multi-page document sent to the
  /// print dialog (one dialog, not one per bill).
  static Future<void> emit(
    List<Bill> bills, {
    required String businessName,
    String? businessAddress,
    String? businessGstin,
    String? businessFssai,
    String? defaultSacCode,
    required bool gstEnabled,
    String? footerNote,
    required ReceiptLabels labels,
  }) async {
    if (bills.isEmpty) return;
    final size = await getPaperSize();

    if (PaperSizes.isThermal(size)) {
      await PrinterService.instance.printBills(
        bills,
        businessName: businessName,
        businessAddress: businessAddress,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        gstEnabled: gstEnabled,
        labels: labels,
        paperDots: PaperSizes.thermalDots(size),
      );
      return;
    }

    // PDF page size — one document, a page per bill, one print dialog.
    final pageFormat = size == PaperSizes.a5 ? PdfPageFormat.a5 : PdfPageFormat.a4;
    final bytes = await InvoicePdf.buildMany(
      bills: bills,
      pageFormat: pageFormat,
      businessName: businessName,
      address: businessAddress,
      gstin: businessGstin,
      fssai: businessFssai,
      defaultSacCode: defaultSacCode,
      gstEnabled: gstEnabled,
      footerNote: footerNote,
    );

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Invoice-${bills.first.billNumber}',
    );
  }

  /// Render a single [bill] to a preview for the currently-selected paper size,
  /// WITHOUT printing. Thermal sizes return a receipt PNG; A5/A4 return PDF
  /// bytes. Mirrors [emit] so the preview matches what will actually be printed.
  static Future<ReceiptPreview> buildPreview(
    Bill bill, {
    required String businessName,
    String? businessAddress,
    String? businessGstin,
    String? businessFssai,
    String? defaultSacCode,
    required bool gstEnabled,
    String? footerNote,
    required ReceiptLabels labels,
  }) async {
    final size = await getPaperSize();

    if (PaperSizes.isThermal(size)) {
      final png = await PrinterService.instance.buildReceiptPreviewPng(
        bill,
        businessName: businessName,
        businessAddress: businessAddress,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        gstEnabled: gstEnabled,
        labels: labels,
        paperDots: PaperSizes.thermalDots(size),
      );
      return ReceiptPreview(bytes: png, isPdf: false);
    }

    final pageFormat = size == PaperSizes.a5 ? PdfPageFormat.a5 : PdfPageFormat.a4;
    final bytes = await InvoicePdf.buildMany(
      bills: [bill],
      pageFormat: pageFormat,
      businessName: businessName,
      address: businessAddress,
      gstin: businessGstin,
      fssai: businessFssai,
      defaultSacCode: defaultSacCode,
      gstEnabled: gstEnabled,
      footerNote: footerNote,
    );
    return ReceiptPreview(bytes: bytes, isPdf: true);
  }
}
