import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// One row recovered from a purchase-list PDF: an item name plus the quantity
/// (and unit, if the parser could isolate one) to purchase. [quantity] is null
/// when the trailing number couldn't be parsed — the row still needs manual
/// review before it's usable.
class ParsedPurchaseRow {
  final String name;
  final double? quantity;
  final String? unit;

  ParsedPurchaseRow({required this.name, this.quantity, this.unit});
}

/// Recovers item/quantity rows from a PDF built by [PurchaseListPdf.build].
///
/// This is text-extraction, not structured data — the PDF has no machine
/// tags, only the text a person reads. Each purchase-list row was printed as
/// `"<name> <qty> <unit>"` (see purchase_list_pdf.dart), so a row is recovered
/// by splitting the trailing `"<number> <word>"` off the end of the line; the
/// wording of the document's page footer/title/header is excluded by an exact
/// match rather than a guess, so an unexpected item named e.g. "Purchase" is
/// never silently dropped.
///
/// Deliberately best-effort: this never throws for a line it can't parse —
/// callers show every recovered row for the user to confirm or discard before
/// it reaches a real form, since a misread quantity would otherwise flow
/// straight into a purchase record.
class PurchaseListPdfImporter {
  static final _trailingQty =
      RegExp(r'^(.*\S)\s+([0-9]+(?:\.[0-9]+)?)\s+(\S+)$');

  // Lines the exporter always prints that are not purchase rows. Matched
  // case-insensitively and trimmed, so page-number variants ("Page 2 of 3")
  // are also excluded via a prefix check below.
  static const _skipExact = {'purchase list', 'item qty to purchase'};

  static Future<List<ParsedPurchaseRow>> parse(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    return parseBytes(bytes);
  }

  static List<ParsedPurchaseRow> parseBytes(List<int> bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final lines = PdfTextExtractor(doc).extractTextLines();
      final rows = <ParsedPurchaseRow>[];
      for (final line in lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        final lower = text.toLowerCase();
        if (_skipExact.contains(lower)) continue;
        if (lower.startsWith('page ')) continue;
        // The exporter's placeholder row for an empty list.
        if (text == '—' || lower == '— —') continue;

        final match = _trailingQty.firstMatch(text);
        if (match == null) {
          // Couldn't isolate a trailing quantity — keep the row so the user
          // sees it was found, but they must fill in the quantity themselves.
          rows.add(ParsedPurchaseRow(name: text));
          continue;
        }
        rows.add(ParsedPurchaseRow(
          name: match.group(1)!.trim(),
          quantity: double.tryParse(match.group(2)!),
          unit: match.group(3),
        ));
      }
      return rows;
    } finally {
      doc.dispose();
    }
  }
}
