import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/secure_store_backup_stub.dart'
    if (dart.library.io) 'services/secure_store_backup_io.dart' as backup;

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
// SecureStore — the ONE FlutterSecureStorage the app uses, with every call
// run strictly one after another.
//
// Why: on Windows, flutter_secure_storage keeps every key in a single DPAPI-
// encrypted file, and each write is load-whole-file → change one key →
// rewrite-whole-file, with no locking. Two overlapping calls (the license
// cache writes 8 keys at once; login writes both tokens at once; API calls
// read the token meanwhile) either lose each other's keys, or a read lands on
// a half-written file — which the plugin treats as corrupt and DELETES,
// wiping the tokens. Next launch finds no session: "logged out on restart".
// Serializing all access through one queue removes the race on every
// platform; the cost is microseconds per call. A kill mid-write is handled by
// the backup in secure_store_backup_io.dart.
// ---------------------------------------------------------------------------

class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    wOptions: WindowsOptions(),
  );

  Future<void> _tail = Future.value();
  bool _checkedLive = false;

  /// Runs [op] after every previously queued call has finished. A failing call
  /// is reported to its own caller only and never blocks the queue.
  ///
  /// Serializing alone is not enough on Windows: the app can still be killed
  /// mid-write, tearing the file (see secure_store_backup_io.dart). So a call
  /// that fails is retried once from the last good backup, and every write
  /// refreshes that backup.
  Future<T> _serial<T>(Future<T> Function() op, {bool mutates = false}) {
    final result = _tail.then((_) async {
      if (!_checkedLive) {
        _checkedLive = true;
        // A torn file deleted by the plugin on an earlier run.
        if (await backup.liveMissing()) await backup.restore('file missing');
      }
      T value;
      try {
        value = await op();
      } catch (e) {
        if (!await backup.restore(e)) rethrow;
        value = await op();
      }
      if (mutates) {
        try {
          await backup.snapshot();
        } catch (e) {
          debugPrint('[SECURE] backup failed: $e'); // never fail the write
        }
      }
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<String?> read({required String key}) =>
      _serial(() => _storage.read(key: key));

  Future<void> write({required String key, required String value}) =>
      _serial(() => _storage.write(key: key, value: value), mutates: true);

  Future<void> delete({required String key}) =>
      _serial(() => _storage.delete(key: key), mutates: true);

  Future<void> deleteAll() =>
      _serial(() => _storage.deleteAll(), mutates: true);
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

  static final _secure = SecureStore.instance;

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
  // Admin entitlement for Customers & campaigns (subscriptions.allow_customers).
  // Absent on sessions saved before it existed — read as enabled.
  static const _keyCustomersEnabled = 'customers_enabled';
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
  // Kitchen (KOT) printing. Independent of the billing paper size above: the
  // kitchen commonly runs a second, narrower roll, and a shop that prints
  // A4 invoices still wants a thermal ticket for the cooks.
  static const _keyKitchenAutoPrint = 'kitchen_auto_print';
  static const _keyKitchenPaperSize = 'kitchen_paper_size';
  static const _keyRecentNetworkPrinters = 'recent_network_printers';

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
    bool customersEnabled = true,
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
      prefs.setBool(_keyCustomersEnabled, customersEnabled),
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

  Future<void> updateCustomersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCustomersEnabled, enabled);
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

  // How often this device has settled bills in each payment mode, as a JSON
  // map mode → count. The billing screen's "+" (add a payment) picks the
  // most-used mode not already on the bill. Per device and per business, like
  // the major-category order: it describes this counter's habits.
  static String _keyPaymentModeUse(String businessId) =>
      'payment_mode_use_$businessId';

  Future<void> savePaymentModeUse(String businessId, String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPaymentModeUse(businessId), json);
  }

  Future<String?> getPaymentModeUse(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPaymentModeUse(businessId));
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

  Future<void> saveKitchenAutoPrint(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKitchenAutoPrint, on);
  }

  /// Whether a kitchen ticket prints by itself when a new order arrives.
  /// Off by default — a shop that has never set up a kitchen printer must not
  /// start firing failed print jobs after an update.
  Future<bool> getKitchenAutoPrint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKitchenAutoPrint) ?? false;
  }

  Future<void> saveKitchenPaperSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyKitchenPaperSize, size);
  }

  /// Kitchen roll width. Thermal only — a KOT is a slip torn off at the pass,
  /// so the A5/A4 PDF path the billing size allows is meaningless here and an
  /// A4 value left over from the billing setting must never leak in.
  Future<String> getKitchenPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyKitchenPaperSize);
    return (s != null && PaperSizes.isThermal(s)) ? s : PaperSizes.mm80;
  }

  /// Wi-Fi/LAN printer addresses ("ip:port") added on this device, newest
  /// first — offered as one-tap fills in the add-printer dialog so an IP is
  /// typed once, not every time.
  Future<List<String>> getRecentNetworkPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyRecentNetworkPrinters) ?? const [];
  }

  Future<void> rememberNetworkPrinter(String address) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getStringList(_keyRecentNetworkPrinters) ?? const [];
    await prefs.setStringList(_keyRecentNetworkPrinters,
        [address, ...previous.where((a) => a != address)].take(5).toList());
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

  /// The session as the app sees it — prefs only. Deliberately does NOT touch
  /// secure storage: whether someone is logged in must not hinge on a token
  /// read succeeding at startup (requests read the token themselves).
  Future<Map<String, dynamic>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
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
      'customers_enabled': prefs.getBool(_keyCustomersEnabled) ?? true,
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
    // The printers on this shop's network don't change with who is signed in.
    final recentPrinters = prefs.getStringList(_keyRecentNetworkPrinters);

    await Future.wait([
      _secure.deleteAll(),
      prefs.clear(),
    ]);

    for (final entry in preserved.entries) {
      await prefs.setString(entry.key, entry.value);
    }
    if (recentPrinters != null) {
      await prefs.setStringList(_keyRecentNetworkPrinters, recentPrinters);
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
  bool customersEnabled = true,
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
      customersEnabled: customersEnabled,
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
Future<void>    savePaymentModeUse(String businessId, String json) =>
    AuthStorage.instance.savePaymentModeUse(businessId, json);
Future<String?> getPaymentModeUse(String businessId) =>
    AuthStorage.instance.getPaymentModeUse(businessId);
Future<String>  nextOfflineBillNumber()        => AuthStorage.instance.nextOfflineBillNumber();
Future<String>  getDeviceTag()                 => AuthStorage.instance.getDeviceTag();
Future<void>    savePaperSize(String size)     => AuthStorage.instance.savePaperSize(size);
Future<String>  getPaperSize()                 => AuthStorage.instance.getPaperSize();
Future<void>    saveKitchenAutoPrint(bool on)  => AuthStorage.instance.saveKitchenAutoPrint(on);
Future<bool>    getKitchenAutoPrint()          => AuthStorage.instance.getKitchenAutoPrint();
Future<void>    saveKitchenPaperSize(String s) => AuthStorage.instance.saveKitchenPaperSize(s);
Future<String>  getKitchenPaperSize()          => AuthStorage.instance.getKitchenPaperSize();
Future<List<String>> getRecentNetworkPrinters() => AuthStorage.instance.getRecentNetworkPrinters();
Future<void>    rememberNetworkPrinter(String address) =>
    AuthStorage.instance.rememberNetworkPrinter(address);
Future<void>    updateInventoryEnabled(bool e) => AuthStorage.instance.updateInventoryEnabled(e);
Future<void>    updateHasBarcodeScanner(bool e) => AuthStorage.instance.updateHasBarcodeScanner(e);
Future<void>    updateGstEnabled(bool e)       => AuthStorage.instance.updateGstEnabled(e);
Future<void>    updateRoundOffEnabled(bool e)  => AuthStorage.instance.updateRoundOffEnabled(e);
Future<void>    updateStoreEnabled(bool e)     => AuthStorage.instance.updateStoreEnabled(e);
Future<void>    updateCustomersEnabled(bool e) => AuthStorage.instance.updateCustomersEnabled(e);
Future<void>    saveGstProfile({String? gstNumber, String? businessAddress, String? businessPhone, String? defaultSacCode, String? fssaiNumber}) =>
    AuthStorage.instance.saveGstProfile(gstNumber: gstNumber, businessAddress: businessAddress, businessPhone: businessPhone, defaultSacCode: defaultSacCode, fssaiNumber: fssaiNumber);
Future<Map<String, String>> getGstProfile()    => AuthStorage.instance.getGstProfile();
