import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Print paper-size options and helpers. The stored value is one of these
/// string constants; `mm58`/`mm80` print thermal ESC/POS, `a5`/`a4` generate a
/// PDF invoice via the OS print dialog.
class PaperSizes {
  static const String mm58 = 'mm58';
  static const String mm80 = 'mm80';
  static const String a5   = 'a5';
  static const String a4   = 'a4';

  static const List<String> all = [mm58, mm80, a5, a4];

  /// True for the ESC/POS thermal roll sizes (as opposed to the PDF page sizes).
  static bool isThermal(String size) => size == mm58 || size == mm80;

  /// Printable dot-width for a thermal size (58mm = 384, 80mm = 576 @ 203dpi).
  /// Defaults to 80mm for any non-thermal value.
  static int thermalDots(String size) => size == mm58 ? 384 : 576;
}

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
  static const _keyRoundOffEnabled  = 'round_off_enabled';
  // Online store master switch. Cached in the session so the shell knows
  // whether to poll the online-order queue at all, without a profile fetch
  // (which is owner-only — a cashier could never answer the question).
  static const _keyStoreEnabled     = 'store_enabled';
  // Cached GST invoice details, refreshed whenever the business profile is
  // fetched — used so the thermal receipt can print GSTIN even offline.
  static const _keyGstNumber        = 'gst_number';
  static const _keyBusinessAddress  = 'business_address';
  // Shop's contact number, printed under the address so a customer holding the
  // receipt can call about an order or a return.
  static const _keyBusinessPhone    = 'business_phone';
  static const _keyDefaultSacCode   = 'default_sac_code';
  // FSSAI license number — printed on the receipt for food businesses when set.
  static const _keyFssaiNumber      = 'fssai_number';
  // Cached bill-number prefix (e.g. 'INV'), so offline receipts use the same
  // invoice prefix as online instead of a jarring 'LOCAL-'. Refreshed whenever
  // the business profile is fetched.
  static const _keyBillPrefix       = 'bill_prefix';
  // Offline bill numbering: 'INV-<deviceTag>-<seq>' e.g. INV-a7f4-0001.
  //   • _keyDeviceTag — a 4-char random tag generated ONCE per install, so two
  //     devices billing offline never produce the same number.
  //   • _keyOfflineSeq — a monotonic 4-digit counter (wraps at 9999) that
  //     persists across offline sessions and continues where it left off.
  // The number is kept as-is on sync (it's printed and given to the customer),
  // so it must be globally unique — the device tag guarantees that.
  static const _keyDeviceTag        = 'offline_device_tag';
  static const _keyOfflineSeq       = 'offline_bill_seq';
  // Chosen print paper size: 'mm58' | 'mm80' | 'a5' | 'a4'. Defaults to 'mm80'
  // (current behaviour). 'mm58'/'mm80' print thermal ESC/POS; 'a5'/'a4' generate
  // a PDF invoice via the OS print dialog.
  static const _keyPaperSize        = 'paper_size';

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
    bool roundOffEnabled = false,
    bool storeEnabled = false,
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
      prefs.setBool(_keyRoundOffEnabled, roundOffEnabled),
      prefs.setBool(_keyStoreEnabled, storeEnabled),
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

  Future<void> updateRoundOffEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRoundOffEnabled, enabled);
  }

  Future<void> updateStoreEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStoreEnabled, enabled);
  }

  /// Cache the GST invoice details from the business profile so the thermal
  /// receipt can print the GSTIN / address / default SAC even without a live
  /// profile fetch. Values are cleared (empty string) when not set.
  Future<void> saveGstProfile({
    String? gstNumber,
    String? businessAddress,
    String? businessPhone,
    String? defaultSacCode,
    String? fssaiNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_keyGstNumber, gstNumber ?? ''),
      prefs.setString(_keyBusinessAddress, businessAddress ?? ''),
      prefs.setString(_keyBusinessPhone, businessPhone ?? ''),
      prefs.setString(_keyDefaultSacCode, defaultSacCode ?? ''),
      prefs.setString(_keyFssaiNumber, fssaiNumber ?? ''),
    ]);
  }

  Future<Map<String, String>> getGstProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'gst_number': prefs.getString(_keyGstNumber) ?? '',
      'business_address': prefs.getString(_keyBusinessAddress) ?? '',
      'business_phone': prefs.getString(_keyBusinessPhone) ?? '',
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

  // Charge-description suggestions (Delivery, Packaging, ...) cached per
  // business as a JSON list, so the billing screen can offer them instantly
  // and while offline. Keyed by business so a different login on the same
  // device never sees another shop's charges.
  static String _keyChargeSuggestions(String businessId) =>
      'charge_suggestions_$businessId';

  // Major-category display order — a PHONE preference, deliberately never
  // synced to the server: two staff on two devices are free to browse the
  // billing screen's chip strip in whatever order suits them, and a new
  // install starts from the plain alphabetical default. Stored as a JSON
  // string list; the provider owns decoding it and merging in majors this
  // device has never seen before. Keyed by business for the same reason as
  // charge suggestions above.
  static String _keyMajorCategoryOrder(String businessId) =>
      'major_category_order_$businessId';

  Future<void> saveMajorCategoryOrder(String businessId, String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMajorCategoryOrder(businessId), json);
  }

  Future<String?> getMajorCategoryOrder(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMajorCategoryOrder(businessId));
  }

  Future<void> saveChargeSuggestions(String businessId, String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyChargeSuggestions(businessId), json);
  }

  Future<String?> getChargeSuggestions(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyChargeSuggestions(businessId));
  }

  /// A stable 4-char UPPERCASE alphanumeric tag unique to THIS install,
  /// generated once and reused. Embedded in offline bill numbers so two devices
  /// billing offline never produce the same number. Existing installs that saved
  /// a lowercase tag are upper-cased on read (no regeneration — that would break
  /// the number's continuity).
  Future<String> getDeviceTag() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyDeviceTag);
    if (existing != null && existing.isNotEmpty) return existing.toUpperCase();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    final tag = List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
    await prefs.setString(_keyDeviceTag, tag);
    return tag;
  }

  /// Builds the next OFFLINE bill number: `INV-<deviceTag>-<seq>`, e.g.
  /// 'INV-a7f4-0001'. The 4-digit counter persists and continues across offline
  /// sessions (wraps at 9999). This number is kept verbatim when the bill later
  /// syncs — it's printed and handed to the customer, so it must not change; the
  /// device tag keeps it globally unique.
  Future<String> nextOfflineBillNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = await getDeviceTag();
    final current = prefs.getInt(_keyOfflineSeq) ?? 0;
    final next = current >= 9999 ? 1 : current + 1;
    await prefs.setInt(_keyOfflineSeq, next);
    return 'INV-$tag-${next.toString().padLeft(4, '0')}';
  }

  Future<void> savePaperSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPaperSize, size);
  }

  /// The chosen print paper size, defaulting to 80mm thermal.
  Future<String> getPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyPaperSize);
    return PaperSizes.all.contains(s) ? s! : PaperSizes.mm80;
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
      'round_off_enabled': prefs.getBool(_keyRoundOffEnabled) ?? false,
      'store_enabled'    : prefs.getBool(_keyStoreEnabled) ?? false,
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
  bool roundOffEnabled = false,
  bool storeEnabled = false,
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
      roundOffEnabled: roundOffEnabled,
      storeEnabled: storeEnabled,
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
Future<void>    saveCachedChargeSuggestions(String businessId, String json) =>
    AuthStorage.instance.saveChargeSuggestions(businessId, json);
Future<String?> getCachedChargeSuggestions(String businessId) =>
    AuthStorage.instance.getChargeSuggestions(businessId);
Future<void>    saveMajorCategoryOrder(String businessId, String json) =>
    AuthStorage.instance.saveMajorCategoryOrder(businessId, json);
Future<String?> getMajorCategoryOrder(String businessId) =>
    AuthStorage.instance.getMajorCategoryOrder(businessId);
Future<String>  nextOfflineBillNumber()        => AuthStorage.instance.nextOfflineBillNumber();
Future<String>  getDeviceTag()                 => AuthStorage.instance.getDeviceTag();
Future<void>    savePaperSize(String size)     => AuthStorage.instance.savePaperSize(size);
Future<String>  getPaperSize()                 => AuthStorage.instance.getPaperSize();
Future<void>    updateInventoryEnabled(bool e) => AuthStorage.instance.updateInventoryEnabled(e);
Future<void>    updateHasBarcodeScanner(bool e) => AuthStorage.instance.updateHasBarcodeScanner(e);
Future<void>    updateGstEnabled(bool e)       => AuthStorage.instance.updateGstEnabled(e);
Future<void>    updateRoundOffEnabled(bool e)  => AuthStorage.instance.updateRoundOffEnabled(e);
Future<void>    updateStoreEnabled(bool e)     => AuthStorage.instance.updateStoreEnabled(e);
Future<void>    saveGstProfile({String? gstNumber, String? businessAddress, String? businessPhone, String? defaultSacCode, String? fssaiNumber}) =>
    AuthStorage.instance.saveGstProfile(gstNumber: gstNumber, businessAddress: businessAddress, businessPhone: businessPhone, defaultSacCode: defaultSacCode, fssaiNumber: fssaiNumber);
Future<Map<String, String>> getGstProfile()    => AuthStorage.instance.getGstProfile();
