import '../l10n/l10n_ext.dart';

/// Localized strings the printer needs, resolved from [AppLocalizations] at the
/// call site (the printer service runs off the widget tree and has no context).
class ReceiptLabels {
  final String languageCode;
  final String defaultBusiness;
  final String phonePrefix;
  final String billNo;
  final String table;
  final String date;
  final String customer;
  final String customerPhone;
  final String colItem;
  final String colQty;
  final String colPrice;
  final String colTotal;
  // GST% is an acronym — identical across all supported languages, so it isn't
  // routed through the ARB files. Defaults to 'GST%'.
  final String colGst;
  final String subtotal;
  final String tax;
  final String cgst;
  final String sgst;
  final String gstin;
  // FSSAI is a proper acronym — identical across all supported languages, so it
  // isn't routed through the ARB files. Defaults to 'FSSAI:'.
  final String fssai;
  final String discount;
  final String roundOff;
  final String total;
  final String payment;
  final String thankYou;
  // Brand line printed in small text under the thank-you note. It's a product
  // name, so — like FSSAI — it's the same across all languages and isn't routed
  // through the ARB files.
  final String poweredBy;

  const ReceiptLabels({
    required this.languageCode,
    required this.defaultBusiness,
    required this.phonePrefix,
    required this.billNo,
    required this.table,
    required this.date,
    required this.customer,
    required this.customerPhone,
    required this.colItem,
    required this.colQty,
    required this.colPrice,
    required this.colTotal,
    this.colGst = 'GST%',
    required this.subtotal,
    required this.tax,
    required this.cgst,
    required this.sgst,
    required this.gstin,
    this.fssai = 'FSSAI:',
    required this.discount,
    this.roundOff = 'Round Off:',
    required this.total,
    required this.payment,
    required this.thankYou,
    this.poweredBy = 'Powered by Vengurlatech',
  });

  factory ReceiptLabels.from(AppLocalizations l10n, String languageCode) =>
      ReceiptLabels(
        languageCode: languageCode,
        defaultBusiness: l10n.receiptDefaultBusiness,
        phonePrefix: l10n.receiptPhonePrefix,
        billNo: l10n.receiptBillNo,
        table: l10n.receiptTable,
        date: l10n.receiptDate,
        customer: l10n.receiptCustomer,
        customerPhone: l10n.receiptCustomerPhone,
        colItem: l10n.receiptColItem,
        colQty: l10n.receiptColQty,
        colPrice: l10n.receiptColPrice,
        colTotal: l10n.receiptColTotal,
        subtotal: l10n.receiptSubtotal,
        tax: l10n.receiptTax,
        cgst: l10n.receiptCgst,
        sgst: l10n.receiptSgst,
        gstin: l10n.receiptGstin,
        discount: l10n.receiptDiscount,
        roundOff: l10n.receiptRoundOff,
        total: l10n.receiptTotal,
        payment: l10n.receiptPayment,
        thankYou: l10n.receiptThankYou,
      );
}
