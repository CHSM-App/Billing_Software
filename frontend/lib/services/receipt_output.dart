import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/models.dart';
import '../storage.dart';
import 'printer_service.dart';
import 'receipt_labels.dart';
import 'invoice_pdf.dart';
import 'bill_settings.dart';

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
  /// The cached shop logo, or null unless the owner opted in to printing it.
  static Future<Uint8List?> _logoBytes() async =>
      await getPrintLogo() ? await getLogoBytes() : null;

  /// [_logoBytes] decoded for the thermal raster. A corrupt cache just means
  /// no logo — it must never stop a bill printing.
  static Future<ui.Image?> _logoImage() async {
    final bytes = await _logoBytes();
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  /// True when the currently-selected paper size is a PDF page size (A5/A4),
  /// i.e. NOT a thermal roll. Callsites use this to decide whether an active
  /// thermal printer is required before emitting.
  /// Billing Setup applied to the shop header: hidden lines are simply not
  /// passed on. The GSTIN is left to the renderers ([BillSettings.showGstin]),
  /// because on thermal it also decides the CGST/SGST split.
  static Future<(BillSettings, String?, String?, String?, String?)> _setup(
      String? address, String? phone, String? fssai, String? footerNote) async {
    final s = await BillSettings.load();
    return (
      s,
      s.showAddress ? address : null,
      s.showPhone ? s.shopPhones(phone) : null,
      s.showFssai ? fssai : null,
      footerNote ?? s.footerNote,
    );
  }

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
    String? businessPhone,
    String? businessGstin,
    String? businessFssai,
    String? defaultSacCode,
    required bool gstEnabled,
    String? footerNote,
    required ReceiptLabels labels,
  }) async {
    // A draft (held order / open table) is not a bill yet — its lines and
    // total can still change — so it must never leave the shop as a receipt.
    // Guarded here, the one place every print path goes through.
    bills = bills.where((b) => b.status != 'draft').toList();
    if (bills.isEmpty) return;
    final size = await getPaperSize();
    final (settings, address, phone, fssai, note) =
        await _setup(businessAddress, businessPhone, businessFssai, footerNote);

    if (PaperSizes.isThermal(size)) {
      await PrinterService.instance.printBills(
        bills,
        businessName: businessName,
        businessAddress: address,
        businessPhone: phone,
        businessGstin: businessGstin,
        businessFssai: fssai,
        gstEnabled: gstEnabled,
        labels: labels,
        logo: await _logoImage(),
        settings: settings,
        paperDots: PaperSizes.thermalDots(size),
      );
      return;
    }

    // PDF page size — one document, a page per bill, one print dialog.
    final bytes = await pdf(bills,
        pageFormat: size == PaperSizes.a5 ? PdfPageFormat.a5 : PdfPageFormat.a4,
        businessName: businessName,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        defaultSacCode: defaultSacCode,
        gstEnabled: gstEnabled,
        footerNote: footerNote);

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Invoice-${bills.first.displayNumber}',
    );
  }

  /// [bills] as one PDF (a page each) — what [emit] prints on A5/A4, also used
  /// to share a quotation as a file.
  static Future<Uint8List> pdf(
    List<Bill> bills, {
    required PdfPageFormat pageFormat,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessGstin,
    String? businessFssai,
    String? defaultSacCode,
    required bool gstEnabled,
    String? footerNote,
  }) async {
    final (settings, address, phone, fssai, note) =
        await _setup(businessAddress, businessPhone, businessFssai, footerNote);
    return InvoicePdf.buildMany(
      bills: bills,
      pageFormat: pageFormat,
      businessName: businessName,
      address: address,
      phone: phone,
      gstin: settings.showGstin ? businessGstin : null,
      fssai: fssai,
      defaultSacCode: defaultSacCode,
      gstEnabled: gstEnabled,
      footerNote: note,
      logo: await _logoBytes(),
      settings: settings,
    );
  }

  /// Emit ONE Payment Receipt for a Credit-tab payment, however many bills it
  /// paid: thermal sizes print it on the roll, A5/A4 open it in the print
  /// dialog as a single page.
  static Future<void> emitSettlement(
    CreditSettlement settlement, {
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessGstin,
    String? businessFssai,
    String? footerNote,
    required ReceiptLabels labels,
  }) async {
    if (settlement.lines.isEmpty) return;
    final size = await getPaperSize();

    if (PaperSizes.isThermal(size)) {
      await PrinterService.instance.printSettlement(
        settlement,
        businessName: businessName,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
        businessGstin: businessGstin,
        businessFssai: businessFssai,
        labels: labels,
        logo: await _logoImage(),
        paperDots: PaperSizes.thermalDots(size),
      );
      return;
    }

    final bytes = await InvoicePdf.buildSettlement(
      settlement: settlement,
      pageFormat: size == PaperSizes.a5 ? PdfPageFormat.a5 : PdfPageFormat.a4,
      businessName: businessName,
      address: businessAddress,
      phone: businessPhone,
      gstin: businessGstin,
      fssai: businessFssai,
      footerNote: footerNote,
      logo: await _logoBytes(),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Payment-Receipt-${settlement.receiptToken}',
    );
  }

  /// Render a single [bill] to a preview for the currently-selected paper size,
  /// WITHOUT printing. Thermal sizes return a receipt PNG; A5/A4 return PDF
  /// bytes. Mirrors [emit] so the preview matches what will actually be printed.
  static Future<ReceiptPreview> buildPreview(
    Bill bill, {
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessGstin,
    String? businessFssai,
    String? defaultSacCode,
    required bool gstEnabled,
    String? footerNote,
    required ReceiptLabels labels,
  }) async {
    final size = await getPaperSize();
    final (settings, address, phone, fssai, note) =
        await _setup(businessAddress, businessPhone, businessFssai, footerNote);

    if (PaperSizes.isThermal(size)) {
      final png = await PrinterService.instance.buildReceiptPreviewPng(
        bill,
        businessName: businessName,
        businessAddress: address,
        businessPhone: phone,
        businessGstin: businessGstin,
        businessFssai: fssai,
        gstEnabled: gstEnabled,
        labels: labels,
        logo: await _logoImage(),
        settings: settings,
        paperDots: PaperSizes.thermalDots(size),
      );
      return ReceiptPreview(bytes: png, isPdf: false);
    }

    final pageFormat = size == PaperSizes.a5 ? PdfPageFormat.a5 : PdfPageFormat.a4;
    final bytes = await InvoicePdf.buildMany(
      bills: [bill],
      pageFormat: pageFormat,
      businessName: businessName,
      address: address,
      phone: phone,
      gstin: settings.showGstin ? businessGstin : null,
      fssai: fssai,
      defaultSacCode: defaultSacCode,
      gstEnabled: gstEnabled,
      footerNote: note,
      logo: await _logoBytes(),
      settings: settings,
    );
    return ReceiptPreview(bytes: bytes, isPdf: true);
  }
}
