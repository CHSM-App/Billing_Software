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
  final String billedBy;
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
  // Billing Setup sections: customer address, terms note, bank details.
  final String address;
  final String terms;
  final String bankDetails;
  final String note;
  // FSSAI is a proper acronym — identical across all supported languages, so it
  // isn't routed through the ARB files. Defaults to 'FSSAI:'.
  final String fssai;
  final String discount;
  final String roundOff;
  final String total;
  final String payment;
  // Printed under a bill with a credit part: what the customer still owes.
  final String balanceDue;
  // An old credit bill paid off with this one: "Prev. Due #0007".
  final String prevDue;
  // This bill plus the old dues it collected.
  final String totalPaid;
  // A payment made on a credit bill: "Paid #0012 CASH".
  final String paid;
  final String thankYou;
  // The Payment Receipt for a Credit-tab payment (several bills, one receipt).
  final String paymentReceipt;
  final String settledInvoices;
  final String colInvoice;
  final String colDate;
  final String colBill;
  final String colPaid;
  final String colBalance;
  final String balDue;
  final String settledTotalPaid;
  final String totalReceived;
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
    required this.billedBy,
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
    this.address = 'Address:',
    this.terms = 'Terms & Conditions',
    this.bankDetails = 'Bank Details',
    this.note = 'Note',
    this.fssai = 'FSSAI:',
    required this.discount,
    this.roundOff = 'Round Off:',
    required this.total,
    required this.payment,
    this.balanceDue = 'Balance Due:',
    this.prevDue = 'Prev. Due',
    this.totalPaid = 'Total:',
    this.paid = 'Paid',
    required this.thankYou,
    this.paymentReceipt = 'PAYMENT RECEIPT',
    this.settledInvoices = 'Settled Invoices',
    this.colInvoice = 'Invoice',
    this.colDate = 'Date',
    this.colBill = 'Bill',
    this.colPaid = 'Paid',
    this.colBalance = 'Balance',
    this.balDue = 'Bal due',
    this.settledTotalPaid = 'Total paid',
    this.totalReceived = 'TOTAL RECEIVED',
    this.poweredBy = 'Powered by Vengurla Tech',
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
        billedBy: l10n.receiptBilledBy,
        colItem: l10n.receiptColItem,
        colQty: l10n.receiptColQty,
        colPrice: l10n.receiptColPrice,
        colTotal: l10n.receiptColTotal,
        subtotal: l10n.receiptSubtotal,
        tax: l10n.receiptTax,
        cgst: l10n.receiptCgst,
        sgst: l10n.receiptSgst,
        gstin: l10n.receiptGstin,
        address: l10n.receiptAddress,
        terms: l10n.receiptTerms,
        bankDetails: l10n.receiptBankDetails,
        note: l10n.receiptNote,
        discount: l10n.receiptDiscount,
        roundOff: l10n.receiptRoundOff,
        total: l10n.receiptTotal,
        payment: l10n.receiptPayment,
        balanceDue: '${l10n.billingBalanceDue}:',
        prevDue: l10n.billingPreviousDue,
        totalPaid: '${l10n.billingTotalPaid}:',
        paid: l10n.billingPaidOnCredit,
        thankYou: l10n.receiptThankYou,
        paymentReceipt: l10n.receiptPaymentReceipt,
        settledInvoices: l10n.receiptSettledInvoices,
        colInvoice: l10n.receiptColInvoice,
        colDate: l10n.receiptColDate,
        colBill: l10n.receiptColBill,
        colPaid: l10n.receiptColPaid,
        colBalance: l10n.receiptColBalance,
        balDue: l10n.receiptBalDue,
        settledTotalPaid: l10n.receiptTotalPaid,
        totalReceived: l10n.receiptTotalReceived,
      );
}
