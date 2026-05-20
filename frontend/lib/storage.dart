import 'package:shared_preferences/shared_preferences.dart';

const _keyToken = 'auth_token';
const _keyUserName = 'user_name';
const _keyUserRole = 'user_role';
const _keyBusinessName = 'business_name';
const _keyBusinessType = 'business_type';
const _keyBusinessId = 'business_id';
const _keyUserId = 'user_id';
const _keyInventoryEnabled = 'inventory_enabled';
const _keyHasBarcodeScanner = 'has_barcode_scanner';

Future<void> saveSession({
  required String token,
  required String userId,
  required String userName,
  required String userRole,
  required String businessId,
  required String businessName,
  required String businessType,
  bool inventoryEnabled = false,
  bool hasBarcodeScanner = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyToken, token);
  await prefs.setString(_keyUserId, userId);
  await prefs.setString(_keyUserName, userName);
  await prefs.setString(_keyUserRole, userRole);
  await prefs.setString(_keyBusinessId, businessId);
  await prefs.setString(_keyBusinessName, businessName);
  await prefs.setString(_keyBusinessType, businessType);
  await prefs.setBool(_keyInventoryEnabled, inventoryEnabled);
  await prefs.setBool(_keyHasBarcodeScanner, hasBarcodeScanner);
}

Future<String?> getToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_keyToken);
}

Future<Map<String, dynamic>> getSession() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'token': prefs.getString(_keyToken),
    'user_id': prefs.getString(_keyUserId),
    'user_name': prefs.getString(_keyUserName),
    'user_role': prefs.getString(_keyUserRole),
    'business_id': prefs.getString(_keyBusinessId),
    'business_name': prefs.getString(_keyBusinessName),
    'business_type': prefs.getString(_keyBusinessType),
    'inventory_enabled': prefs.getBool(_keyInventoryEnabled) ?? false,
    'has_barcode_scanner': prefs.getBool(_keyHasBarcodeScanner) ?? false,
  };
}

Future<void> clearSession() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}
