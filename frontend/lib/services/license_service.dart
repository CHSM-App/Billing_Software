import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api.dart';

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
}

class LicenseStatus {
  final LicenseState state;
  final int? daysUntilExpiry;      // for warning banner
  final int? graceDaysRemaining;   // how many grace days left
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

  // -------------------------------------------------------------------------
  // check() — call on every app startup after login
  //
  // If online:  fetch from server, update local cache, evaluate state
  // If offline: use cached data, evaluate against last_verified_at
  // -------------------------------------------------------------------------
  Future<LicenseStatus> check({required bool isOnline}) async {
    if (isOnline) {
      return await _checkOnline();
    } else {
      return await _checkOffline();
    }
  }

  // Last error message — shown on the blocked screen when online check fails
  String? lastOnlineError;

  Future<LicenseStatus> _checkOnline() async {
    lastOnlineError = null;
    try {
      final data = await getLicense();
      // ignore: avoid_print
      print('[LICENSE] server response: $data');

      // Save to secure storage
      await Future.wait([
        _secure.write(key: _keyStatus,          value: data['status'] as String),
        _secure.write(key: _keyExpiresAt,        value: data['expires_at'] as String),
        _secure.write(key: _keyMaxOfflineDays,   value: '${data['max_offline_days']}'),
        _secure.write(key: _keyGracePeriodDays,  value: '${data['grace_period_days']}'),
        _secure.write(key: _keyVerifiedAt,       value: data['verified_at'] as String),
      ]);

      final result = _evaluate(
        status:          data['status'] as String,
        expiresAt:       DateTime.parse(data['expires_at'] as String),
        maxOfflineDays:  data['max_offline_days'] as int,
        gracePeriodDays: data['grace_period_days'] as int,
        verifiedAt:      DateTime.parse(data['verified_at'] as String),
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
      // Network error — store error and fall back to cached
      lastOnlineError = e.toString();
      return await _checkOffline();
    }
  }

  Future<LicenseStatus> _checkOffline() async {
    final values = await Future.wait([
      _secure.read(key: _keyStatus),
      _secure.read(key: _keyExpiresAt),
      _secure.read(key: _keyMaxOfflineDays),
      _secure.read(key: _keyGracePeriodDays),
      _secure.read(key: _keyVerifiedAt),
    ]);

    final status          = values[0];
    final expiresAtStr    = values[1];
    final maxOfflineDays  = int.tryParse(values[2] ?? '') ?? 30;
    final gracePeriodDays = int.tryParse(values[3] ?? '') ?? 5;
    final verifiedAtStr   = values[4];

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
    );
  }

  LicenseStatus _evaluate({
    required String status,
    required DateTime expiresAt,
    required int maxOfflineDays,
    required int gracePeriodDays,
    required DateTime verifiedAt,
  }) {
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
      return LicenseStatus(LicenseState.allowed, daysUntilExpiry: daysUntilExpiry);
    }

    final totalAllowed = maxOfflineDays + gracePeriodDays;
    if (offlineDays <= totalAllowed) {
      // In grace period — show warning
      final graceDaysRemaining = totalAllowed - offlineDays;
      return LicenseStatus(LicenseState.grace, graceDaysRemaining: graceDaysRemaining);
    }

    // Exceeded offline limit + grace — hard block
    return const LicenseStatus(LicenseState.blockedOffline);
  }

  /// Clear cached license (call on logout)
  Future<void> clear() async {
    await Future.wait([
      _secure.delete(key: _keyStatus),
      _secure.delete(key: _keyExpiresAt),
      _secure.delete(key: _keyMaxOfflineDays),
      _secure.delete(key: _keyGracePeriodDays),
      _secure.delete(key: _keyVerifiedAt),
    ]);
  }
}
