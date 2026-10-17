import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/theme/app_theme.dart';
import 'package:Vittam/widgets/app_widgets.dart';

Item _item({double? stock, double? alert, List<ItemVariant> variants = const []}) =>
    Item(
      id: 'i1',
      businessId: 'b1',
      name: 'Rice',
      stockQuantity: stock,
      lowStockThreshold: alert,
      variants: variants,
      isActive: true,
    );

ItemVariant _size(String id, double? stock, {double? alert = 5}) => ItemVariant(
    id: id, itemId: 'i1', label: id, stockQuantity: stock, lowStockThreshold: alert);

void main() {
  test('plain item: none above the alert, orange at it, red at zero', () {
    expect(stockAlertColor(_item(stock: 20, alert: 5)), isNull);
    expect(stockAlertColor(_item(stock: 5, alert: 5)), stockLowColor);
    expect(stockAlertColor(_item(stock: 0, alert: 5)), stockOutColor);
    expect(stockAlertColor(_item(stock: -2, alert: 5)), stockOutColor);
    // Zero is red even without an alert level set.
    expect(stockAlertColor(_item(stock: 0)), stockOutColor);
  });

  test('untracked stock never gets a stripe', () {
    expect(stockAlertColor(_item()), isNull);
  });

  test('sized item: orange if any size is low or out, red only when all are out', () {
    final mixed = _item(variants: [_size('S', 20), _size('M', 0)]);
    expect(stockAlertColor(mixed), stockLowColor);
    expect(stockAlertColor(_item(variants: [_size('S', 20), _size('M', 30)])),
        isNull);
    expect(stockAlertColor(_item(variants: [_size('S', 0), _size('M', 0)])),
        stockOutColor);
    // A size row reports its own stock.
    expect(stockAlertColor(mixed, mixed.variants[1]), stockOutColor);
    expect(stockAlertColor(mixed, mixed.variants[0]), isNull);
  });
}
