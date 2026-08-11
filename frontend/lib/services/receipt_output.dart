import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../storage.dart';
import 'printer_service.dart';
import 'receipt_labels.dart';
import 'invoice_pdf.dart';

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
}
