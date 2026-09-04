import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api.dart';
import '../storage.dart';
import '../utils/platform_utils.dart' show isDesktopDevice;

// ---------------------------------------------------------------------------
// LicenseStatus — result of a license check
// ---------------------------------------------------------------------------

enum LicenseState {
  /// Subscription active, within offline limit — allow app
  allowed,
  /// Subscription active, offline limit exceeded but within grace period
  /// — allow app but show warning banner
  grace,
  /// Offline limit + grace both exceeded — hard block until online
  blockedOffline,
  /// Subscription expired or suspended — hard block
  blockedSubscription,
  /// No subscription row yet (pending review) — hard block
  blockedPending,
  /// This business isn't allowed to use the app on the current device type
  /// (mobile vs desktop, per the subscription's allow_mobile/allow_desktop) —
  /// hard block. Going online can't fix it; it's an entitlement mismatch.
  blockedDevice,
}

class LicenseStatus {
  final LicenseState state;
  final int? daysUntilExpiry;      // for warning banner
  final int? graceDaysRemaining;   // how many grace days left
  /// The subscription's actual expiry date — set on [LicenseState.allowed] and
  /// [LicenseState.grace] so the Profile screen can show "Active till DATE"
  /// without re-deriving it from [daysUntilExpiry] (which is truncated days,
  /// not the real timestamp).
  final DateTime? expiresAt;
  /// Platform-admin kill switch for the online store (subscriptions.
  /// allow_online_store, migration 039) — separate from the OWNER's own
  /// businesses.store_enabled toggle. Only meaningful on [LicenseState.allowed]
  /// / [LicenseState.grace]: a blocked state never lets the user reach
  /// Settings anyway, so it is not threaded through the block logic at all —
  /// unlike allowMobile/allowDesktop this never changes [state] itself.
  /// Defaults true so an unset/never-cached value never hides the feature.
  final bool allowOnlineStore;
  /// True when the check failed because the local session (access/refresh
  /// token) is invalid or unreadable rather than because the device is
  /// offline. Callers should send the user to the login screen instead of
  /// showing an "offline"/"go online" message, since reconnecting can't fix
  /// a corrupted or expired local session.
  final bool sessionInvalid;

  const LicenseStatus(
    this.state, {
    this.daysUntilExpiry,
    this.graceDaysRemaining,
    this.expiresAt,
    this.allowOnlineStore = true,
    this.sessionInvalid = false,
  });
}

// ---------------------------------------------------------------------------
// LicenseService
// ---------------------------------------------------------------------------

class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    wOptions: WindowsOptions(),
  );

  // Keys in secure storage
  static const _keyStatus           = 'lic_status';
  static const _keyExpiresAt        = 'lic_expires_at';
  static const _keyMaxOfflineDays   = 'lic_max_offline_days';
  static const _keyGracePeriodDays  = 'lic_grace_period_days';
  static const _keyVerifiedAt       = 'lic_verified_at';
  static const _keyAllowMobile      = 'lic_allow_mobile';
  static const _keyAllowDesktop     = 'lic_allow_desktop';
  static const _keyAllowOnlineStore = 'lic_allow_online_store';

  // -------------------------------------------------------------------------
  // check() — call on every app startup after login
  //
  // If online:  fetch from server, update local cache, evaluate state
  // If offline: use cached data, evaluate against last_verified_at
  // -------------------------------------------------------------------------
  Future<LicenseStatus> check({required bool isOnline}) async {
    // Always try the online check first. `isOnline` is only a hint derived from a
    // DB-dependent /health probe with a short timeout, which false-negatives on a
    // slow/cold database even when the network and the license endpoint are fine
    // — that was falsely blocking users with "Go Online to Continue". _checkOnline
    // fetches the real license and, only if that request itself fails, falls back
    // to the cached offline evaluation. So attempting it is safe regardless of the
    // hint; we skip it only when we already know we're offline AND have a cache to
    // evaluate against.
    if (isOnline) return await _checkOnline();

    // Offline hint: if we have never cached a license there is nothing to evaluate
    // offline, so still try online once (the health probe may simply have timed
    // out). Otherwise trust the cache.
    final hasCache = (await _secure.read(key: _keyVerifiedAt)) != null;
    if (!hasCache) return await _checkOnline();
    return await _checkOffline();
  }

  // Last error message — shown on the blocked screen when online check fails
  String? lastOnlineError;

  Future<LicenseStatus> _checkOnline() async {
    lastOnlineError = null;
    try {
      final data = await getLicense();
      // ignore: avoid_print
      print('[LICENSE] server response: $data');

      // Device-access flags. Absent (older backend) → default allowed so we
      // never block on a field the server didn't send.
      final allowMobile  = data['allow_mobile']  as bool? ?? true;
      final allowDesktop = data['allow_desktop'] as bool? ?? true;
      final allowOnlineStore = data['allow_online_store'] as bool? ?? true;

      // Save to secure storage
      await Future.wait([
        _secure.write(key: _keyStatus,          value: data['status'] as String),
        _secure.write(key: _keyExpiresAt,        value: data['expires_at'] as String),
        _secure.write(key: _keyMaxOfflineDays,   value: '${data['max_offline_days']}'),
        _secure.write(key: _keyGracePeriodDays,  value: '${data['grace_period_days']}'),
        _secure.write(key: _keyVerifiedAt,       value: data['verified_at'] as String),
        _secure.write(key: _keyAllowMobile,      value: allowMobile  ? '1' : '0'),
        _secure.write(key: _keyAllowDesktop,     value: allowDesktop ? '1' : '0'),
        _secure.write(key: _keyAllowOnlineStore, value: allowOnlineStore ? '1' : '0'),
      ]);

      final result = _evaluate(
        status:          data['status'] as String,
        expiresAt:       DateTime.parse(data['expires_at'] as String),
        maxOfflineDays:  data['max_offline_days'] as int,
        gracePeriodDays: data['grace_period_days'] as int,
        verifiedAt:      DateTime.parse(data['verified_at'] as String),
        allowMobile:     allowMobile,
        allowDesktop:    allowDesktop,
        allowOnlineStore: allowOnlineStore,
      );

      // If server says blocked, clear local cache so offline fallback also blocks
      if (result.state == LicenseState.blockedSubscription ||
          result.state == LicenseState.blockedPending) {
        await clear();
      }

      return result;
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        final body = e.serverMessage ?? '';
        if (body.contains('no_subscription')) {
          return const LicenseStatus(LicenseState.blockedPending);
        }
        return const LicenseStatus(LicenseState.blockedSubscription);
      }
      // 401 means the access token was rejected and the auto-refresh in
      // api.dart also failed to recover it (refresh token expired, revoked,
      // or — on Windows — unreadable because the DPAPI-encrypted secure
      // storage blob was corrupted/rotated). None of those are fixed by
      // going online, so flag it distinctly instead of falling into the
      // "offline too long" bucket.
      if (e.statusCode == 401) {
        lastOnlineError = 'Server error (${e.statusCode}): ${e.message}';
        final offlineResult = await _checkOffline();
        return LicenseStatus(
          offlineResult.state,
          daysUntilExpiry: offlineResult.daysUntilExpiry,
          graceDaysRemaining: offlineResult.graceDaysRemaining,
          sessionInvalid: true,
        );
      }
      // Other API error (500 etc.) — store error and fall back to cached
      lastOnlineError = 'Server error (${e.statusCode}): ${e.message}';
      return await _checkOffline();
    } catch (e) {
      // Network error — store error and fall back to cached.
      lastOnlineError = e.toString();
      final offlineResult = await _checkOffline();

      // Distinguish a genuine network outage from a lost local credential.
      // On Windows the DPAPI-backed secure store can become unreadable (blob
      // rotated/corrupted, profile moved) while the SharedPreferences session
      // metadata survives — so the app looks "logged in" but every request
      // fails auth. Going online can never fix that, yet the user would be
      // stuck on the "Go Online to Continue" screen forever. Detect it: if the
      // refresh token can't be read, flag the session invalid so the caller
      // routes to the login screen instead.
      if (!await _hasReadableRefreshToken()) {
        return LicenseStatus(
          offlineResult.state,
          daysUntilExpiry: offlineResult.daysUntilExpiry,
          graceDaysRemaining: offlineResult.graceDaysRemaining,
          sessionInvalid: true,
        );
      }
      return offlineResult;
    }
  }

  /// True when a refresh token is present and readable in secure storage.
  /// Returns false both when the token is genuinely absent and when the
  /// secure store throws trying to decrypt it (the Windows DPAPI failure).
  Future<bool> _hasReadableRefreshToken() async {
    try {
      final token = await getRefreshToken();
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<LicenseStatus> _checkOffline() async {
    final values = await Future.wait([
      _secure.read(key: _keyStatus),
      _secure.read(key: _keyExpiresAt),
      _secure.read(key: _keyMaxOfflineDays),
      _secure.read(key: _keyGracePeriodDays),
      _secure.read(key: _keyVerifiedAt),
      _secure.read(key: _keyAllowMobile),
      _secure.read(key: _keyAllowDesktop),
      _secure.read(key: _keyAllowOnlineStore),
    ]);

    final status          = values[0];
    final expiresAtStr    = values[1];
    final maxOfflineDays  = int.tryParse(values[2] ?? '') ?? 30;
    final gracePeriodDays = int.tryParse(values[3] ?? '') ?? 5;
    final verifiedAtStr   = values[4];
    // Absent cache (old install, never fetched) → default allowed, so a missing
    // value never locks the user out of their own device.
    final allowMobile     = values[5] != '0';
    final allowDesktop    = values[6] != '0';
    // Absent (never cached) defaults open, same as allowMobile/allowDesktop.
    final allowOnlineStore = values[7] != '0';

    // Device-access is enforced FIRST — before the "no license cache" bailout —
    // so a forbidden device is blocked even when we're offline and the rest of
    // the license cache is missing. The device policy is a local fact once known.
    if (_deviceForbidden(allowMobile: allowMobile, allowDesktop: allowDesktop)) {
      return const LicenseStatus(LicenseState.blockedDevice);
    }

    // No cached license at all — never verified online
    if (status == null || expiresAtStr == null || verifiedAtStr == null) {
      return const LicenseStatus(LicenseState.blockedOffline);
    }

    return _evaluate(
      status:          status,
      expiresAt:       DateTime.parse(expiresAtStr),
      maxOfflineDays:  maxOfflineDays,
      gracePeriodDays: gracePeriodDays,
      verifiedAt:      DateTime.parse(verifiedAtStr),
      allowMobile:     allowMobile,
      allowDesktop:    allowDesktop,
      allowOnlineStore: allowOnlineStore,
    );
  }

  LicenseStatus _evaluate({
    required String status,
    required DateTime expiresAt,
    required int maxOfflineDays,
    required int gracePeriodDays,
    required DateTime verifiedAt,
    bool allowMobile = true,
    bool allowDesktop = true,
    bool allowOnlineStore = true,
  }) {
    // Device-access entitlement — checked first because it's independent of the
    // subscription's time/status. "Desktop" = Windows native or web; everything
    // else (Android/iOS) is mobile. A forbidden device is a hard block that
    // going online can't fix.
    final onDesktop = kIsWeb || isDesktopDevice;
    if (onDesktop && !allowDesktop) {
      return const LicenseStatus(LicenseState.blockedDevice);
    }
    if (!onDesktop && !allowMobile) {
      return const LicenseStatus(LicenseState.blockedDevice);
    }

    final now = DateTime.now().toUtc();

    // Subscription expired or suspended
    if (status == 'expired' || status == 'suspended') {
      return const LicenseStatus(LicenseState.blockedSubscription);
    }
    if (status == 'pending') {
      return const LicenseStatus(LicenseState.blockedPending);
    }

    // Subscription itself expired (client-side check)
    if (expiresAt.isBefore(now)) {
      return const LicenseStatus(LicenseState.blockedSubscription);
    }

    // Days since last online verification
    final offlineDays = now.difference(verifiedAt).inDays;

    if (offlineDays <= maxOfflineDays) {
      // Within offline limit — allowed
      final daysUntilExpiry = expiresAt.difference(now).inDays;
      return LicenseStatus(LicenseState.allowed,
          daysUntilExpiry: daysUntilExpiry, expiresAt: expiresAt,
          allowOnlineStore: allowOnlineStore);
    }

    final totalAllowed = maxOfflineDays + gracePeriodDays;
    if (offlineDays <= totalAllowed) {
      // In grace period — show warning
      final graceDaysRemaining = totalAllowed - offlineDays;
      return LicenseStatus(LicenseState.grace,
          graceDaysRemaining: graceDaysRemaining, expiresAt: expiresAt,
          allowOnlineStore: allowOnlineStore);
    }

    // Exceeded offline limit + grace — hard block
    return const LicenseStatus(LicenseState.blockedOffline);
  }

  /// True when the current build is running on a "desktop" device (Windows
  /// native or web). Android/iOS report false. This is a purely local fact —
  /// it never depends on the network.
  static bool get isDesktop => kIsWeb || isDesktopDevice;

  /// Whether the current device type is blocked given a device policy.
  /// Returns true when this device is NOT allowed.
  static bool _deviceForbidden({required bool allowMobile, required bool allowDesktop}) {
    final onDesktop = isDesktop;
    if (onDesktop && !allowDesktop) return true;
    if (!onDesktop && !allowMobile) return true;
    return false;
  }

  /// Persist the device policy (called from login and every /license fetch) so
  /// it survives offline relaunches and mid-session resume checks. `null` means
  /// "unknown" and is stored as allowed.
  Future<void> cacheDevicePolicy({bool? allowMobile, bool? allowDesktop}) async {
    await Future.wait([
      _secure.write(key: _keyAllowMobile,  value: (allowMobile  ?? true) ? '1' : '0'),
      _secure.write(key: _keyAllowDesktop, value: (allowDesktop ?? true) ? '1' : '0'),
    ]);
  }

  /// Immediate, network-free device-access check against an explicit policy
  /// (e.g. the flags returned in the login response). Also caches the policy.
  /// Returns [LicenseState.blockedDevice] if this device isn't allowed, else
  /// null (caller proceeds with the normal license flow).
  Future<LicenseState?> checkDevicePolicy({bool? allowMobile, bool? allowDesktop}) async {
    await cacheDevicePolicy(allowMobile: allowMobile, allowDesktop: allowDesktop);
    final forbidden = _deviceForbidden(
      allowMobile: allowMobile ?? true,
      allowDesktop: allowDesktop ?? true,
    );
    // ignore: avoid_print
    print('[LICENSE] device check — isDesktop=$isDesktop '
        'allowMobile=$allowMobile allowDesktop=$allowDesktop forbidden=$forbidden');
    return forbidden ? LicenseState.blockedDevice : null;
  }

  /// Network-free re-check of the LAST KNOWN device policy from cache. Used on
  /// app resume to enforce a policy change mid-session. If no policy was ever
  /// cached, treats the device as allowed (we can't lock out before we knew).
  Future<bool> isDeviceBlockedByCache() async {
    final m = await _secure.read(key: _keyAllowMobile);
    final d = await _secure.read(key: _keyAllowDesktop);
    return _deviceForbidden(allowMobile: m != '0', allowDesktop: d != '0');
  }

  /// Clear cached license (call on logout)
  Future<void> clear() async {
    await Future.wait([
      _secure.delete(key: _keyStatus),
      _secure.delete(key: _keyExpiresAt),
      _secure.delete(key: _keyMaxOfflineDays),
      _secure.delete(key: _keyGracePeriodDays),
      _secure.delete(key: _keyVerifiedAt),
      _secure.delete(key: _keyAllowMobile),
      _secure.delete(key: _keyAllowDesktop),
      _secure.delete(key: _keyAllowOnlineStore),
    ]);
  }
}
