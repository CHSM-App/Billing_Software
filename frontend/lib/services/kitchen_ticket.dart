import 'package:flutter/material.dart' show TextAlign;
import 'package:intl/intl.dart';

import 'raster_lab.dart';

/// Builds the content of a KOT (Kitchen Order Ticket) — the slip that tells the
/// cooks what to make.
///
/// Emits the same structured [ReceiptRow] model that `printBill` uses, NOT
/// space-padded monospace lines. That matters: a proportional font (and every
/// Devanagari dish name is one) overflows a monospace column and the paragraph
/// silently re-wraps mid-word, which is what makes such a slip unreadable.
/// [ReceiptRow.cols] gives each cell a real fraction of the paper and wraps
/// inside it, and the renderer shrinks the whole table if it still will not fit.
///
/// DESIGN, and why it is not a receipt:
///   • No money. A cook prices nothing, and a ticket carrying totals invites
///     being handed to a customer as a bill.
///   • The destination (table) is the largest thing on the slip — that is the
///     ticket's whole job.
///   • Quantity in its own narrow right-aligned column so the left edge reads
///     as a column of counts, the one thing scanned in a hurry.
///   • Dish names are big and bold; everything administrative is small.
class KitchenTicket {
  /// Type scale, in the same units as [ReceiptRow.size] (receipts use 24).
  /// A ticket is read at arm's length across a hot pass, so the two things that
  /// matter — where it goes and what to cook — are set well above body size.
  static const double _destinationSize = 40;
  static const double _dishSize = 30;
  static const double _headerSize = 26;
  static const double _adminSize = 20;

  /// Share of the paper given to the quantity column. Enough for "1.5 x"
  /// without stealing width from long dish names.
  static const double _qtyFraction = 0.24;

  /// Renders [order] — one entry from `GET /api/kitchen/orders`.
  static List<ReceiptRow> build(
    Map<String, dynamic> order, {
    bool reprint = false,
  }) {
    final rows = <ReceiptRow>[];
    final lines = items(order);

    // A QR order is normally one diner ordering several dishes, and repeating
    // their name under every line made the slip mostly name. When the whole
    // order is theirs, say it once under the destination instead.
    final diners = lines.map(_diner).toSet();
    final sharedDiner =
        diners.length == 1 && diners.first.isNotEmpty ? diners.first : null;

    rows.add(ReceiptRow.center('*** KITCHEN ***',
        size: _headerSize, bold: true));
    if (reprint) {
      rows.add(ReceiptRow.center('(REPRINT)', size: _adminSize, bold: true));
    }

    // Where the food goes. A table order says the table; a counter or parcel
    // order has none, so it falls back to the customer's name and then to a
    // plain PARCEL — never leaving the cook without a hand-off label.
    final table = '${order['table_number'] ?? ''}'.trim();
    final customer = '${order['customer_name'] ?? ''}'.trim();
    rows.add(ReceiptRow.center(
      table.isNotEmpty
          ? 'TABLE $table'
          : customer.isNotEmpty
              ? customer.toUpperCase()
              : 'PARCEL',
      size: _destinationSize,
      bold: true,
    ));

    final billNo = '${order['bill_number'] ?? ''}'.trim();
    if (billNo.isNotEmpty) {
      rows.add(ReceiptRow.center(billNo, size: _adminSize));
    }
    final placed = _parseTime(order['created_at']);
    if (placed != null) {
      rows.add(ReceiptRow.center(
          DateFormat('dd MMM  hh:mm a').format(placed), size: _adminSize));
    }

    if (sharedDiner != null) {
      rows.add(ReceiptRow.center(sharedDiner, size: _adminSize));
    }

    rows.add(ReceiptRow.rule(bold: true));

    // Only when the order is split between diners, and only when it changes:
    // a run of dishes from the same person needs the name once, not per line.
    String? attributed = sharedDiner;
    for (final it in lines) {
      final name = '${it['item_name'] ?? ''}'.trim();
      rows.add(ReceiptRow.cols([
        ReceiptCell('${_trimZeros(_num(it['quantity']))} x',
            align: TextAlign.right, widthFraction: _qtyFraction),
        ReceiptCell(name,
            align: TextAlign.left, widthFraction: 1 - _qtyFraction),
      ], size: _dishSize, bold: true));

      // Who ordered it, when a diner self-ordered from their phone. Small and
      // indented into the name column so it cannot read as another dish.
      final diner = _diner(it);
      if (diner.isNotEmpty && diner != attributed) {
        attributed = diner;
        rows.add(ReceiptRow.cols([
          const ReceiptCell('', widthFraction: _qtyFraction),
          ReceiptCell('- $diner',
              align: TextAlign.left, widthFraction: 1 - _qtyFraction),
        ], size: _adminSize));
      }
    }

    // The customer's instruction for the whole order. Printed under the dishes
    // and boxed by rules so it cannot be mistaken for one — a chef reading a
    // ticket top to bottom has to see "NO ONIONS" before plating, and until now
    // an online-store note never reached the kitchen, let alone the paper.
    final note = '${order['notes'] ?? ''}'.trim();
    if (note.isNotEmpty) {
      rows.add(ReceiptRow.rule());
      rows.add(ReceiptRow.cols([
        ReceiptCell('NOTE', align: TextAlign.left, widthFraction: 1),
      ], size: _adminSize, bold: true));
      rows.add(ReceiptRow.cols([
        ReceiptCell(note, align: TextAlign.left, widthFraction: 1),
      ], size: _dishSize, bold: true));
    }

    rows.add(ReceiptRow.rule());
    final count = lines.fold<double>(0, (s, it) => s + _num(it['quantity']));
    rows.add(
        ReceiptRow.center('${_trimZeros(count)} item(s)', size: _adminSize));

    return rows;
  }

  /// The order's line items, tolerant of a missing or malformed `items` key —
  /// a ticket that throws is a ticket that never prints.
  static List<Map<String, dynamic>> items(Map<String, dynamic> order) =>
      (order['items'] as List? ?? const [])
          .whereType<Map>()
          .cast<Map<String, dynamic>>()
          .toList();

  static String _diner(Map<String, dynamic> it) =>
      '${it['diner_name'] ?? ''}'.trim();

  static double _num(Object? v) =>
      v == null ? 0 : double.tryParse(v.toString()) ?? 0;

  /// "2" not "2.0", but "1.5" survives — some kitchens sell by weight.
  static String _trimZeros(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static DateTime? _parseTime(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
}
