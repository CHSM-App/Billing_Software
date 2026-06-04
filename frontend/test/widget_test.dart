// Unit tests for model parsing — no platform plugins required.
import 'package:billmate/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ----------------------------------------------------------------
  // User
  // ----------------------------------------------------------------
  group('User.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'user-1',
        'name': 'Alice',
        'phone': '9876543210',
        'role': 'owner',
      };
      final user = User.fromJson(json);
      expect(user.id, 'user-1');
      expect(user.name, 'Alice');
      expect(user.phone, '9876543210');
      expect(user.role, 'owner');
    });
  });

  // ----------------------------------------------------------------
  // Business
  // ----------------------------------------------------------------
  group('Business.fromJson', () {
    test('parses required fields', () {
      final json = {
        'id': 'biz-1',
        'name': 'Test Shop',
        'business_type': 'retail',
        'address': '123 Main St',
        'inventory_enabled': true,
        'has_barcode_scanner': false,
      };
      final biz = Business.fromJson(json);
      expect(biz.id, 'biz-1');
      expect(biz.businessType, 'retail');
      expect(biz.inventoryEnabled, isTrue);
      expect(biz.hasBarcodeScanner, isFalse);
    });

    test('address is nullable', () {
      final json = {
        'id': 'biz-2',
        'name': 'No Address Shop',
        'business_type': 'restaurant_no_tables',
        'address': null,
        'inventory_enabled': false,
        'has_barcode_scanner': false,
      };
      final biz = Business.fromJson(json);
      expect(biz.address, isNull);
    });
  });

  // ----------------------------------------------------------------
  // Item
  // ----------------------------------------------------------------
  group('Item.fromJson', () {
    test('parses all fields including optional ones', () {
      final json = {
        'id': 'item-1',
        'business_id': 'biz-1',
        'name': 'Rice',
        'barcode': '123456',
        'category': 'Grains',
        'price': 50.0,
        'tax_rate': 5.0,
        'stock_quantity': 100.0,
        'is_active': 1,
      };
      final item = Item.fromJson(json);
      expect(item.name, 'Rice');
      expect(item.price, 50.0);
      expect(item.taxRate, 5.0);
      expect(item.stockQuantity, 100.0);
      expect(item.isActive, isTrue);
    });

    test('optional fields default to null', () {
      final json = {
        'id': 'item-2',
        'business_id': 'biz-1',
        'name': 'Salt',
        'barcode': null,
        'category': null,
        'price': '10',
        'tax_rate': null,
        'stock_quantity': null,
        'is_active': true,
      };
      final item = Item.fromJson(json);
      expect(item.barcode, isNull);
      expect(item.category, isNull);
      expect(item.taxRate, isNull);
      expect(item.stockQuantity, isNull);
      expect(item.price, 10.0);
    });

    test('is_active handles both bool true and int 1', () {
      final fromBool = Item.fromJson({
        'id': 'x', 'business_id': 'b', 'name': 'A', 'barcode': null,
        'category': null, 'price': 1, 'tax_rate': null, 'stock_quantity': null,
        'is_active': true,
      });
      final fromInt = Item.fromJson({
        'id': 'x', 'business_id': 'b', 'name': 'A', 'barcode': null,
        'category': null, 'price': 1, 'tax_rate': null, 'stock_quantity': null,
        'is_active': 1,
      });
      expect(fromBool.isActive, isTrue);
      expect(fromInt.isActive, isTrue);
    });
  });
}
