import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage.dart';

class SessionData {
  final String userId;
  final String userName;
  final String userRole;
  final String businessId;
  final String businessName;
  final String businessType;
  final bool inventoryEnabled;
  final bool hasBarcodeScanner;
  final bool gstEnabled;
  final bool roundOffEnabled;

  const SessionData({
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.businessId,
    required this.businessName,
    required this.businessType,
    required this.inventoryEnabled,
    required this.hasBarcodeScanner,
    required this.gstEnabled,
    required this.roundOffEnabled,
  });

  static SessionData empty() => const SessionData(
        userId: '',
        userName: '',
        userRole: '',
        businessId: '',
        businessName: '',
        businessType: '',
        inventoryEnabled: false,
        hasBarcodeScanner: false,
        gstEnabled: false,
        roundOffEnabled: false,
      );

  static SessionData fromMap(Map<String, dynamic> m) => SessionData(
        userId: m['user_id'] ?? '',
        userName: m['user_name'] ?? '',
        userRole: m['user_role'] ?? '',
        businessId: m['business_id'] ?? '',
        businessName: m['business_name'] ?? '',
        businessType: m['business_type'] ?? '',
        inventoryEnabled: m['inventory_enabled'] == true,
        hasBarcodeScanner: m['has_barcode_scanner'] == true,
        gstEnabled: m['gst_enabled'] == true,
        roundOffEnabled: m['round_off_enabled'] == true,
      );
}

class SessionNotifier extends AsyncNotifier<SessionData> {
  @override
  Future<SessionData> build() async {
    final m = await getSession();
    if ((m['user_id'] ?? '').isEmpty) {
      throw Exception('no_session');
    }
    return SessionData.fromMap(m);
  }

  Future<void> refresh() async {
    // Re-read the (local) session WITHOUT flipping to AsyncLoading first —
    // otherwise every listener, including MainShell, briefly sees `loading` and
    // the whole app flashes the splash screen (e.g. on Profile pull-to-refresh).
    // getSession() reads SharedPreferences, so it's fast and effectively never
    // fails; keep showing the current data throughout.
    final next = await AsyncValue.guard(() async {
      final m = await getSession();
      return SessionData.fromMap(m);
    });
    state = next;
  }

  Future<void> clear() async {
    await clearSession();
    state = AsyncError(Exception('no_session'), StackTrace.current);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, SessionData>(SessionNotifier.new);

// Fine-grained derived providers — only the watching widget rebuilds
final userRoleProvider = Provider<String>((ref) =>
    ref.watch(sessionProvider).valueOrNull?.userRole ?? '');

final businessTypeProvider = Provider<String>((ref) =>
    ref.watch(sessionProvider).valueOrNull?.businessType ?? '');

final businessNameProvider = Provider<String>((ref) =>
    ref.watch(sessionProvider).valueOrNull?.businessName ?? '');

final userNameProvider = Provider<String>((ref) =>
    ref.watch(sessionProvider).valueOrNull?.userName ?? '');

// Barcode scanning is always on now (the per-business toggle was removed), so
// this is unconditionally true regardless of the (possibly stale) session flag.
final hasBarcodeProvider = Provider<bool>((ref) => true);

final inventoryEnabledProvider = Provider<bool>((ref) =>
    ref.watch(sessionProvider).valueOrNull?.inventoryEnabled ?? false);

// Master GST toggle. When false (the default), all GST UI and receipt sections
// are hidden and the app behaves exactly as before.
final gstEnabledProvider = Provider<bool>((ref) =>
    ref.watch(sessionProvider).valueOrNull?.gstEnabled ?? false);

// Invoice round-off toggle. When false (the default), no round-off is applied
// and the bill totals behave exactly as before.
final roundOffEnabledProvider = Provider<bool>((ref) =>
    ref.watch(sessionProvider).valueOrNull?.roundOffEnabled ?? false);
