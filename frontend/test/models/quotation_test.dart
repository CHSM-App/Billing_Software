import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/models/models.dart';

void main() {
  // A quotation stores Bill.toSnapshotJson and reads it back through
  // Quotation.fromJson — the cart it reopens and the slip it prints both come
  // from that round trip, so every priced field must survive it.
  test('a bill snapshot round-trips through a quotation', () {
    final bill = Bill(
      id: 'preview',
      businessId: '',
      billNumber: 'PREVIEW',
      customerName: 'Asha',
      customerPhone: '9876543210',
      subtotal: 180,
      taxAmount: 9,
      discountAmount: 10,
      chargesAmount: 20,
      additionalCharges: [BillCharge(name: 'Delivery', amount: 20)],
      total: 209,
      roundOff: 0.4,
      paymentMode: 'cash',
      status: 'quotation',
      priceListId: 'pl-1',
      createdByUserId: '',
      createdAt: DateTime.utc(2026, 10, 27),
      items: [
        BillItem(
          id: 'i1',
          billId: 'preview',
          itemId: 'item-1',
          variantId: 'v-1',
          itemName: 'Tyre (Large)',
          quantity: 2,
          unitPrice: 85,
          taxRate: 5,
          lineTotal: 178.5,
          discountAmount: 10,
        ),
      ],
    );

    final q = Quotation.fromJson({
      'id': 'q-1',
      'quotation_number': 'QT-0007',
      'total': 199.4,
      'created_at': '2026-10-27T10:00:00.000Z',
      'snapshot': bill.toSnapshotJson(),
    });

    expect(q.number, 'QT-0007');
    expect(q.total, 199.4);
    final b = q.bill;
    expect(b.billNumber, 'QT-0007');
    expect(b.status, 'quotation');
    // Printed with its QT- prefix, unlike an invoice number.
    expect(b.displayNumber, 'QT-0007');
    expect(b.customerName, 'Asha');
    expect(b.customerPhone, '9876543210');
    expect(b.discountAmount, 10);
    expect(b.chargesAmount, 20);
    expect(b.additionalCharges.single.name, 'Delivery');
    expect(b.roundOff, 0.4);
    expect(b.grandTotal, closeTo(199.4, 0.001));
    expect(b.priceListId, 'pl-1');
    final i = b.items.single;
    expect(i.itemId, 'item-1');
    expect(i.variantId, 'v-1');
    expect(i.quantity, 2);
    expect(i.unitPrice, 85);
    expect(i.taxRate, 5);
    expect(i.lineTotal, 178.5);
    expect(i.discountAmount, 10);
  });
}
