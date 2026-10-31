import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// What prints on a bill — the owner's Billing Setup page. Mirrors
/// backend/src/billSettings.js (same keys, same defaults).
///
/// Defaults reproduce the bill as it printed before this setting existed, so
/// a device that never received settings (older backend, not yet synced)
/// prints exactly as before. The logo switch stays the older print_logo
/// flag; [footerNote] is businesses.bill_footer_note (the terms text).
class BillSettings {
  final bool showAddress;
  final bool showPhone;
  final bool showGstin;
  final bool showFssai;
  final bool showCashier;
  final bool showCustomer;
  final bool showTaxSummary;
  final bool showTerms;
  final bool showBank;
  /// Shop-wide note printed on every bill, when [showNote].
  final bool showNote;
  /// Warranty details captured at billing time (a tyre's vehicle KM reading,
  /// etc. — see WarrantyExtraFieldsEditor), printed on the receipt.
  final bool showWarrantyDetails;
  /// A UPI QR for [upiId] with the bill amount filled in — see [upiLink].
  final bool showUpiQr;
  final String upiId;
  /// The item's unit after the quantity on a printed bill — see [qty].
  final bool showUnits;
  final String note;
  /// Second shop number, printed after the main one ("Ph: 98…, 98…").
  final String altPhone;
  /// Printed before [altPhone] ("GPay", "WhatsApp"); empty = no label.
  final String altPhoneLabel;
  /// account_name, account_no, bank_name, branch, ifsc, note.
  final Map<String, String> bank;
  final String? footerNote;

  static const bankKeys = ['account_name', 'account_no', 'bank_name', 'branch', 'ifsc', 'note'];

  const BillSettings({
    this.showAddress = true,
    this.showPhone = true,
    this.showGstin = true,
    this.showFssai = true,
    this.showCashier = true,
    this.showCustomer = true,
    this.showTaxSummary = true,
    this.showTerms = true,
    this.showBank = false,
    this.showNote = false,
    this.showWarrantyDetails = true,
    this.showUpiQr = false,
    this.upiId = '',
    this.showUnits = false,
    this.note = '',
    this.altPhone = '',
    this.altPhoneLabel = '',
    this.bank = const {},
    this.footerNote,
  });

  factory BillSettings.fromJson(Map? j, {String? footerNote}) {
    bool f(String k, bool d) => j?[k] is bool ? j![k] as bool : d;
    final b = j?['bank'] is Map ? j!['bank'] as Map : const {};
    return BillSettings(
      showAddress: f('show_address', true),
      showPhone: f('show_phone', true),
      showGstin: f('show_gstin', true),
      showFssai: f('show_fssai', true),
      showCashier: f('show_cashier', true),
      showCustomer: f('show_customer', true),
      showTaxSummary: f('show_tax_summary', true),
      showTerms: f('show_terms', true),
      showBank: f('show_bank', false),
      showNote: f('show_note', false),
      showWarrantyDetails: f('show_warranty_details', true),
      showUpiQr: f('show_upi_qr', false),
      upiId: j?['upi_id'] is String ? j!['upi_id'] as String : '',
      showUnits: f('show_units', false),
      note: j?['note'] is String ? j!['note'] as String : '',
      altPhone: j?['alt_phone'] is String ? j!['alt_phone'] as String : '',
      altPhoneLabel: j?['alt_phone_label'] is String
          ? j!['alt_phone_label'] as String
          : '',
      bank: {for (final k in bankKeys) k: b[k] is String ? b[k] as String : ''},
      footerNote: footerNote,
    );
  }

  Map<String, dynamic> toJson() => {
        'show_address': showAddress,
        'show_phone': showPhone,
        'show_gstin': showGstin,
        'show_fssai': showFssai,
        'show_cashier': showCashier,
        'show_customer': showCustomer,
        'show_tax_summary': showTaxSummary,
        'show_terms': showTerms,
        'show_bank': showBank,
        'show_note': showNote,
        'show_warranty_details': showWarrantyDetails,
        'show_upi_qr': showUpiQr,
        'upi_id': upiId,
        'show_units': showUnits,
        'note': note,
        'alt_phone': altPhone,
        'alt_phone_label': altPhoneLabel,
        'bank': {for (final k in bankKeys) k: bank[k] ?? ''},
      };

  /// Bank-detail lines to print, or empty when off / no account number.
  /// Same lines as bankLines() in billSettings.js.
  List<String> get bankLines {
    String v(String k) => (bank[k] ?? '').trim();
    if (!showBank || v('account_no').isEmpty) return const [];
    return [
      if (v('account_name').isNotEmpty) 'A/c Name: ${v('account_name')}',
      'A/c No: ${v('account_no')}',
      if (v('bank_name').isNotEmpty)
        'Bank: ${v('bank_name')}${v('branch').isNotEmpty ? ', ${v('branch')}' : ''}'
      else if (v('branch').isNotEmpty)
        'Branch: ${v('branch')}',
      if (v('ifsc').isNotEmpty) 'IFSC: ${v('ifsc')}',
      if (v('note').isNotEmpty) v('note'),
    ];
  }

  /// The shop's number(s) as printed, one per line ('\n'): the alternate
  /// number prints under the main one. Same as shopPhones() in billSettings.js.
  String? shopPhones(String? phone) {
    final alt = altPhone.trim();
    final label = altPhoneLabel.trim();
    final all = [
      phone?.trim() ?? '',
      alt.isNotEmpty && label.isNotEmpty ? '$label: $alt' : alt,
    ].where((p) => p.isNotEmpty);
    return all.isEmpty ? null : all.join('\n');
  }

  /// A printed bill line's quantity: "2 kg" with [showUnits], else just "2".
  String qty(BillItem item, String qty) =>
      showUnits ? receiptQty(item, qty) : qty;

  /// The UPI payment link [bill]'s QR encodes, or null when the QR is off.
  /// The amount is what is still owed on a credit bill, else the printed
  /// total ([grandTotal] as the renderer computed it, plus old dues collected).
  /// No `tn` (note) param: every extra character makes the QR denser, and on
  /// a 2-inch roll it has to stay scannable.
  String? upiLink(Bill bill, String payee, double grandTotal) {
    final id = upiId.trim();
    if (!showUpiQr || id.isEmpty || bill.status == 'quotation') return null;
    final amount = bill.isUnpaidCredit
        ? bill.amountDue
        : grandTotal + bill.collectedTotal;
    if (amount <= 0) return null;
    return 'upi://pay?pa=$id&pn=${Uri.encodeComponent(payee)}'
        '&am=${amount.toStringAsFixed(2)}&cu=INR';
  }

  /// The note to print, or '' when off or empty. Same as noteText() in billSettings.js.
  String get noteText => showNote ? note.trim() : '';

  // ── Device cache ─────────────────────────────────────────────────────────
  // Filled from login, /license and the owner's own save, so staff devices and
  // offline printing follow the owner's choice. Cleared with the rest of the
  // prefs on logout.
  static const _key = 'bill_settings';
  static const _keyNote = 'bill_footer_note';

  /// Cache what the server sent. [data] is a login `business` map or a
  /// /license body. No `bill_settings` key (older backend) → leave the cache
  /// alone, which means defaults = the bill as before.
  static Future<void> sync(Map data) async {
    if (!data.containsKey('bill_settings')) return;
    final prefs = await SharedPreferences.getInstance();
    final s = data['bill_settings'];
    await prefs.setString(_key, jsonEncode(s is Map ? s : const {}));
    final note = data['bill_footer_note'];
    if (note is String) {
      await prefs.setString(_keyNote, note);
    } else {
      await prefs.remove(_keyNote);
    }
  }

  static Future<BillSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    Map? j;
    try {
      final raw = prefs.getString(_key);
      j = raw == null ? null : jsonDecode(raw) as Map?;
    } catch (_) {
      j = null;
    }
    return BillSettings.fromJson(j, footerNote: prefs.getString(_keyNote));
  }
}
