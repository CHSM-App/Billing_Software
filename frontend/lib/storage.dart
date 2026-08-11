import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// AuthStorage — single access point for all session persistence.
//
// Security split:
//   flutter_secure_storage  →  access_token, refresh_token
//     • Android: EncryptedSharedPreferences (AES-256, key in Android Keystore)
//     • iOS/macOS: Keychain
//     • Windows: DPAPI
//     • Web: localStorage (no OS keystore available on web)
//
//   SharedPreferences  →  everything else (user name, role, business info)
//     Non-credential metadata; no security benefit from encrypting.
// ---------------------------------------------------------------------------

class AuthStorage {
  AuthStorage._();
  static final AuthStorage instance = AuthStorage._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    wOptions: WindowsOptions(),
  );

  // Secure storage keys
  static const _keyAccessToken  = 'access_token';
  static const _keyRefreshToken = 'refresh_token';

  // SharedPreferences keys
  static const _keyUserId           = 'user_id';
  static const _keyUserName         = 'user_name';
  static const _keyUserRole         = 'user_role';
  static const _keyBusinessId       = 'business_id';
  static const _keyBusinessName     = 'business_name';
  static const _keyBusinessType     = 'business_type';
  static const _keyInventoryEnabled = 'inventory_enabled';
  static const _keyHasBarcodeScanner = 'has_barcode_scanner';
  static const _keyGstEnabled       = 'gst_enabled';
  // Cached GST invoice details, refreshed whenever the business profile is
  // fetched — used so the thermal receipt can print GSTIN even offline.
  static const _keyGstNumber        = 'gst_number';
  static const _keyBusinessAddress  = 'business_address';
  static const _keyDefaultSacCode   = 'default_sac_code';
  // FSSAI license number — printed on the receipt for food businesses when set.
  static const _keyFssaiNumber      = 'fssai_number';
  // Cached bill-number prefix (e.g. 'INV'), so offline receipts use the same
  // invoice prefix as online instead of a jarring 'LOCAL-'. Refreshed whenever
  // the business profile is fetched.
  static const _keyBillPrefix       = 'bill_prefix';

  // -------------------------------------------------------------------------
  // Write
  // -------------------------------------------------------------------------

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String userName,
    required String userRole,
    required String businessId,
    required String businessName,
    required String businessType,
    bool inventoryEnabled = false,
    bool hasBarcodeScanner = false,
    bool gstEnabled = false,
  }) async {
    // Tokens go to secure storage
    await Future.wait([
      _secure.write(key: _keyAccessToken, value: accessToken),
      _secure.write(key: _keyRefreshToken, value: refreshToken),
    ]);

    // Metadata goes to shared prefs
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_keyUserId, userId),
      prefs.setString(_keyUserName, userName),
      prefs.setString(_keyUserRole, userRole),
      prefs.setString(_keyBusinessId, businessId),
      prefs.setString(_keyBusinessName, businessName),
      prefs.setString(_keyBusinessType, businessType),
      prefs.setBool(_keyInventoryEnabled, inventoryEnabled),
      prefs.setBool(_keyHasBarcodeScanner, hasBarcodeScanner),
      prefs.setBool(_keyGstEnabled, gstEnabled),
    ]);
  }

  Future<void> updateBusinessName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBusinessName, name);
  }

  /// Update a cached business flag in the session so its provider reflects the
  /// change immediately (without waiting for a re-login).
  Future<void> updateInventoryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInventoryEnabled, enabled);
  }

  Future<void> updateHasBarcodeScanner(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasBarcodeScanner, enabled);
  }

  Future<void> updateGstEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGstEnabled, enabled);
  }

  /// Cache the GST invoice details from the business profile so the thermal
  /// receipt can print the GSTIN / address / default SAC even without a live
  /// profile fetch. Values are cleared (empty string) when not set.
  Future<void> saveGstProfile({
    String? gstNumber,
    String? businessAddress,
    String? defaultSacCode,
    String? fssaiNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_keyGstNumber, gstNumber ?? ''),
      prefs.setString(_keyBusinessAddress, businessAddress ?? ''),
      prefs.setString(_keyDefaultSacCode, defaultSacCode ?? ''),
      prefs.setString(_keyFssaiNumber, fssaiNumber ?? ''),
    ]);
  }

  Future<Map<String, String>> getGstProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'gst_number': prefs.getString(_keyGstNumber) ?? '',
      'business_address': prefs.getString(_keyBusinessAddress) ?? '',
      'default_sac_code': prefs.getString(_keyDefaultSacCode) ?? '',
      'fssai_number': prefs.getString(_keyFssaiNumber) ?? '',
    };
  }

  Future<void> saveBillPrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBillPrefix, prefix);
  }

  /// The cached invoice prefix, defaulting to 'INV' when unknown.
  Future<String> getBillPrefix() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString(_keyBillPrefix)?.trim();
    return (p == null || p.isEmpty) ? 'INV' : p;
  }

  Future<void> saveAccessToken(String accessToken) =>
      _secure.write(key: _keyAccessToken, value: accessToken);

  Future<void> saveRefreshToken(String refreshToken) =>
      _secure.write(key: _keyRefreshToken, value: refreshToken);

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  Future<String?> getAccessToken() => _secure.read(key: _keyAccessToken);

  Future<String?> getRefreshToken() => _secure.read(key: _keyRefreshToken);

  Future<String?> getBusinessId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBusinessId);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  Future<Map<String, dynamic>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token'            : await _secure.read(key: _keyAccessToken),
      'user_id'          : prefs.getString(_keyUserId),
      'user_name'        : prefs.getString(_keyUserName),
      'user_role'        : prefs.getString(_keyUserRole),
      'business_id'      : prefs.getString(_keyBusinessId),
      'business_name'    : prefs.getString(_keyBusinessName),
      'business_type'    : prefs.getString(_keyBusinessType),
      'inventory_enabled': prefs.getBool(_keyInventoryEnabled) ?? false,
      'has_barcode_scanner': prefs.getBool(_keyHasBarcodeScanner) ?? false,
      'gst_enabled'      : prefs.getBool(_keyGstEnabled) ?? false,
    };
  }

  // -------------------------------------------------------------------------
  // Clear — wipes both stores completely on logout
  // -------------------------------------------------------------------------

  /// Prefs keys that are device preferences, not session data. These are read
  /// back and restored after the wipe so logging out doesn't reset them.
  static const _keysSurvivingLogout = ['app_language'];

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    final preserved = <String, String>{
      for (final key in _keysSurvivingLogout)
        if (prefs.getString(key) != null) key: prefs.getString(key)!,
    };

    await Future.wait([
      _secure.deleteAll(),
      prefs.clear(),
    ]);

    for (final entry in preserved.entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }
}

// ---------------------------------------------------------------------------
// Top-level shims — keep existing call sites working without changes.
// All delegate to AuthStorage.instance.
// ---------------------------------------------------------------------------

Future<void> saveSession({
  required String accessToken,
  required String refreshToken,
  required String userId,
  required String userName,
  required String userRole,
  required String businessId,
  required String businessName,
  required String businessType,
  bool inventoryEnabled = false,
  bool hasBarcodeScanner = false,
  bool gstEnabled = false,
}) => AuthStorage.instance.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userId,
      userName: userName,
      userRole: userRole,
      businessId: businessId,
      businessName: businessName,
      businessType: businessType,
      inventoryEnabled: inventoryEnabled,
      hasBarcodeScanner: hasBarcodeScanner,
      gstEnabled: gstEnabled,
    );

Future<void> updateBusinessName(String name)   => AuthStorage.instance.updateBusinessName(name);
Future<String?> getToken()                     => AuthStorage.instance.getAccessToken();
Future<String?> getRefreshToken()              => AuthStorage.instance.getRefreshToken();
Future<void>    saveAccessToken(String token)  => AuthStorage.instance.saveAccessToken(token);
Future<Map<String, dynamic>> getSession()      => AuthStorage.instance.getSession();
Future<String?> getBusinessId()                => AuthStorage.instance.getBusinessId();
Future<String?> getUserId()                    => AuthStorage.instance.getUserId();
Future<void>    clearSession()                 => AuthStorage.instance.clearSession();
Future<void>    saveBillPrefix(String prefix)  => AuthStorage.instance.saveBillPrefix(prefix);
Future<String>  getBillPrefix()                => AuthStorage.instance.getBillPrefix();
Future<void>    updateInventoryEnabled(bool e) => AuthStorage.instance.updateInventoryEnabled(e);
Future<void>    updateHasBarcodeScanner(bool e) => AuthStorage.instance.updateHasBarcodeScanner(e);
Future<void>    updateGstEnabled(bool e)       => AuthStorage.instance.updateGstEnabled(e);
Future<void>    saveGstProfile({String? gstNumber, String? businessAddress, String? defaultSacCode, String? fssaiNumber}) =>
    AuthStorage.instance.saveGstProfile(gstNumber: gstNumber, businessAddress: businessAddress, defaultSacCode: defaultSacCode, fssaiNumber: fssaiNumber);
Future<Map<String, String>> getGstProfile()    => AuthStorage.instance.getGstProfile();
