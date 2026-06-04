import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'storage.dart';
import 'providers/connectivity_provider.dart';

const String baseUrl = 'https://billing.vengurlatech.com/api';

// ---------------------------------------------------------------------------
// Connectivity notifier reference — set once from main.dart after ProviderScope
// ---------------------------------------------------------------------------

ConnectivityNotifier? _connectivityNotifier;

void setConnectivityNotifier(ConnectivityNotifier n) {
  _connectivityNotifier = n;
}

// ---------------------------------------------------------------------------
// Logging HTTP client
// ---------------------------------------------------------------------------

Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) async {
  _logRequest('GET', uri, headers);
  final response = await http.get(uri, headers: headers);
  _logResponse('GET', uri, response);
  return response;
}

Future<http.Response> _post(Uri uri, {Map<String, String>? headers, Object? body}) async {
  _logRequest('POST', uri, headers, body: body);
  final response = await http.post(uri, headers: headers, body: body);
  _logResponse('POST', uri, response);
  return response;
}

Future<http.Response> _put(Uri uri, {Map<String, String>? headers, Object? body}) async {
  _logRequest('PUT', uri, headers, body: body);
  final response = await http.put(uri, headers: headers, body: body);
  _logResponse('PUT', uri, response);
  return response;
}

Future<http.Response> _delete(Uri uri, {Map<String, String>? headers}) async {
  _logRequest('DELETE', uri, headers);
  final response = await http.delete(uri, headers: headers);
  _logResponse('DELETE', uri, response);
  return response;
}

// ---------------------------------------------------------------------------
// Safe wrappers — mark offline on network failure
// ---------------------------------------------------------------------------

Future<http.Response> _safeGet(Uri uri, {Map<String, String>? headers}) async {
  try {
    return await _get(uri, headers: headers);
  } on http.ClientException {
    _connectivityNotifier?.markOffline();
    rethrow;
  } catch (e) {
    // Catches dart:io SocketException on native platforms
    _connectivityNotifier?.markOffline();
    rethrow;
  }
}

Future<http.Response> _safePost(Uri uri, {Map<String, String>? headers, Object? body}) async {
  try {
    return await _post(uri, headers: headers, body: body);
  } on http.ClientException {
    _connectivityNotifier?.markOffline();
    rethrow;
  } catch (e) {
    // Catches dart:io SocketException on native platforms
    _connectivityNotifier?.markOffline();
    rethrow;
  }
}

// Auth-aware wrappers — automatically refresh the access token on 401 and retry.
// Use these for all authenticated endpoints.

Future<http.Response> _authGet(Uri uri) =>
    _withAutoRefresh((h) => _safeGet(uri, headers: h));

Future<http.Response> _authPost(Uri uri, {Object? body}) =>
    _withAutoRefresh((h) => _safePost(uri, headers: h, body: body));

Future<http.Response> _authPut(Uri uri, {Object? body}) =>
    _withAutoRefresh((h) => _put(uri, headers: h, body: body));

Future<http.Response> _authDelete(Uri uri) =>
    _withAutoRefresh((h) => _delete(uri, headers: h));

void _logRequest(String method, Uri uri, Map<String, String>? headers, {Object? body}) {
  final buf = StringBuffer();
  buf.writeln('→ $method ${uri.path}${uri.query.isNotEmpty ? '?${uri.query}' : ''}');
  if (body != null) buf.writeln('  body: $body');
  dev.log(buf.toString().trimRight(), name: 'API');
}

void _logResponse(String method, Uri uri, http.Response response) {
  final ok = response.statusCode >= 200 && response.statusCode < 300;
  final tag = ok ? '✓' : '✗';
  dev.log(
    '$tag ${response.statusCode} $method ${uri.path} — ${response.body.length > 300 ? '${response.body.substring(0, 300)}…' : response.body}',
    name: 'API',
  );
}

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------

Future<Map<String, String>> _authHeaders() async {
  final token = await getToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

dynamic _parse(http.Response response) {
  final body = jsonDecode(response.body);
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return body;
  }
  final message = body['error'] ?? body['message'] ?? 'Unknown error';
  throw ApiException(message, response.statusCode);
}

// ---------------------------------------------------------------------------
// Token refresh serialisation — prevents the race condition where concurrent
// 401 responses each try to rotate the refresh token simultaneously.
// Only one refresh call runs at a time; others wait for it to complete and
// then reuse the result.
// ---------------------------------------------------------------------------

Future<bool>? _pendingRefresh;

/// Runs [call] with fresh auth headers. If the server returns 401 (access
/// token expired), silently refreshes and retries once before throwing.
/// Only forces logout when the server explicitly rejects the refresh token
/// (401/403). All other failures (network, 5xx, storage) are treated as
/// transient and the original request error is surfaced instead.
///
/// Concurrent 401s share a single refresh call to avoid token reuse detection.
Future<http.Response> _withAutoRefresh(
    Future<http.Response> Function(Map<String, String> headers) call) async {
  final response = await call(await _authHeaders());
  if (response.statusCode != 401) return response;

  // Serialise: if a refresh is already in flight, wait for it instead of
  // starting a second one (which would send a revoked token and trigger
  // reuse detection on the server).
  _pendingRefresh ??= refreshAccessToken().whenComplete(() {
    _pendingRefresh = null;
  });

  final bool refreshed;
  try {
    refreshed = await _pendingRefresh!;
  } on _TransientError {
    // Storage read failure, network error, 5xx, rate-limit — do NOT logout.
    // Surface as a generic request failure so the UI shows a normal error.
    rethrow;
  } catch (_) {
    // SocketException, ClientException, etc. — also transient.
    rethrow;
  }

  if (!refreshed) {
    // Refresh token is genuinely expired (after 30 days of no use).
    // Throw so the request fails with a clear message — do NOT auto-logout.
    // The user will see an error and can manually log in again if needed.
    throw ApiException('Session expired. Please log in again.', 401);
  }
  return call(await _authHeaders());
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> login(String phone, String pin) async {
  final response = await _post(
    Uri.parse('$baseUrl/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'phone': phone, 'pin': pin}),
  );
  return _parse(response);
}

/// Exchanges the stored refresh token for a new access+refresh token pair.
/// Saves both tokens on success (token rotation).
///
/// Returns true on success.
/// Returns false only when the server explicitly rejects the token (401/403) —
/// meaning the token is expired or revoked and the user must log in again.
/// Throws on network errors so the caller does NOT treat a WiFi blip as a
/// logged-out session.
Future<bool> refreshAccessToken() async {
  final refreshToken = await getRefreshToken();
  // No refresh token in storage — transient storage issue, do NOT log out.
  if (refreshToken == null) {
    throw const _TransientError('No refresh token in storage');
  }
  // Network errors propagate as exceptions — callers must not treat them as
  // auth failures.
  final response = await _post(
    Uri.parse('$baseUrl/refresh'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'refresh_token': refreshToken}),
  );
  if (response.statusCode == 200) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    // Server only returns a new access token — refresh token is unchanged.
    await saveAccessToken(body['access_token'] as String);
    return true;
  }
  // Only 401/403 mean the refresh token is genuinely expired/revoked.
  if (response.statusCode == 401 || response.statusCode == 403) {
    return false;
  }
  // 429, 500, 502, 503 etc. are transient — throw, do NOT log out.
  throw _TransientError('Refresh failed with status ${response.statusCode}');
}

/// Thrown when a refresh failure is transient (network, server error, rate
/// limit) and must NOT cause a forced logout.
class _TransientError implements Exception {
  final String message;
  const _TransientError(this.message);
}

Future<void> logoutApi() async {
  final refreshToken = await getRefreshToken();
  if (refreshToken == null) return;
  try {
    await _post(
      Uri.parse('$baseUrl/logout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );
  } catch (_) {
    // Best-effort — local session will be cleared regardless
  }
}

/// Revokes all refresh tokens for the current user on the server
/// (signs out every device), then clears the local session.
Future<void> logoutAllDevices() async {
  try {
    await _authPost(Uri.parse('$baseUrl/logout-all'));
  } catch (_) {
    // Best-effort — local session will be cleared regardless
  }
}

Future<Map<String, dynamic>> register({
  required String businessName,
  required String businessType,
  String? address,
  required String phone,
  required bool inventoryEnabled,
  required bool hasBarcodeScanner,
  required String ownerName,
  required String ownerPhone,
  required String pin,
}) async {
  final response = await _post(
    Uri.parse('$baseUrl/register'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'business_name': businessName,
      'business_type': businessType,
      'address': address,
      'phone': phone,
      'inventory_enabled': inventoryEnabled,
      'has_barcode_scanner': hasBarcodeScanner,
      'owner_name': ownerName,
      'owner_phone': ownerPhone,
      'pin': pin,
    }),
  );
  return _parse(response);
}

// ---------------------------------------------------------------------------
// OTP — WhatsApp verification
// ---------------------------------------------------------------------------

/// Sends an OTP to [phone] for [purpose] ('register' or 'forgot_pin').
/// Returns the response map. In dev mode the server returns `dev_otp`.
Future<Map<String, dynamic>> sendOtp(String phone, String purpose) async {
  final response = await _post(
    Uri.parse('$baseUrl/send-otp'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'phone': phone, 'purpose': purpose}),
  );
  return _parse(response);
}

/// Verifies [otp] for [phone]+[purpose].
/// Returns `{ verified_token: '...' }` on success, throws [ApiException] on failure.
Future<Map<String, dynamic>> verifyOtp(String phone, String otp, String purpose) async {
  final response = await _post(
    Uri.parse('$baseUrl/verify-otp'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'phone': phone, 'otp': otp, 'purpose': purpose}),
  );
  return _parse(response);
}

/// Sends a receipt link to the customer's WhatsApp for the given [billId].
Future<Map<String, dynamic>> sendBillWhatsApp(String billId) async {
  final response = await _authPost(
    Uri.parse('$baseUrl/bills/send-whatsapp'),
    body: jsonEncode({'bill_id': billId}),
  );
  return _parse(response);
}

/// Resets the PIN for the user associated with [verifiedToken].
Future<void> resetPin(String verifiedToken, String newPin) async {
  final response = await _post(
    Uri.parse('$baseUrl/reset-pin'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'verified_token': verifiedToken, 'new_pin': newPin}),
  );
  _parse(response);
}

// ---------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------

Future<List<dynamic>> getItems({String? search, String? category}) async {
  final params = <String, String>{};
  if (search != null) params['search'] = search;
  if (category != null) params['category'] = category;

  final uri = Uri.parse('$baseUrl/items').replace(queryParameters: params.isEmpty ? null : params);
  return _parse(await _authGet(uri));
}

Future<Map<String, dynamic>> getItemByBarcode(String barcode) async {
  final uri = Uri.parse('$baseUrl/items').replace(queryParameters: {'barcode': barcode});
  return _parse(await _authGet(uri));
}

Future<List<String>> getTopSoldItemIds() async {
  return List<String>.from(_parse(await _authGet(Uri.parse('$baseUrl/items/top-sold'))));
}

Future<List<String>> getCategories() async {
  return List<String>.from(_parse(await _authGet(Uri.parse('$baseUrl/items/categories'))));
}

Future<Map<String, dynamic>> createItem(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/items'), body: jsonEncode(data)));
}

Future<Map<String, dynamic>> updateItem(String id, Map<String, dynamic> data) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/items/$id'), body: jsonEncode(data)));
}

Future<void> deleteItem(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/items/$id')));
}

// ---------------------------------------------------------------------------
// Staff
// ---------------------------------------------------------------------------

Future<List<dynamic>> getStaff() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/staff')));
}

Future<Map<String, dynamic>> createStaff(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/staff'), body: jsonEncode(data)));
}

Future<Map<String, dynamic>> updateStaff(String id, Map<String, dynamic> data) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/staff/$id'), body: jsonEncode(data)));
}

Future<void> deleteStaff(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/staff/$id')));
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

Future<List<dynamic>> getTables() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/tables')));
}

Future<Map<String, dynamic>> createTable(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/tables'), body: jsonEncode(data)));
}

Future<Map<String, dynamic>> updateTable(String id, Map<String, dynamic> data) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/tables/$id'), body: jsonEncode(data)));
}

Future<void> deleteTable(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/tables/$id')));
}

// ---------------------------------------------------------------------------
// Bills
// ---------------------------------------------------------------------------

Future<List<dynamic>> getBills({String? from, String? to, String? search}) async {
  final params = <String, String>{};
  if (from != null) params['from'] = from;
  if (to != null) params['to'] = to;
  if (search != null) params['search'] = search;

  final uri = Uri.parse('$baseUrl/bills').replace(queryParameters: params.isEmpty ? null : params);
  return _parse(await _authGet(uri));
}

Future<Map<String, dynamic>> getBill(String id) async {
  return _parse(await _authGet(Uri.parse('$baseUrl/bills/$id')));
}

Future<Map<String, dynamic>> createBill(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/bills'), body: jsonEncode(data)));
}

Future<Map<String, dynamic>> finalizeBill(String id) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/bills/$id/finalize')));
}

Future<Map<String, dynamic>> addItemsToBill(String id, List<Map<String, dynamic>> items) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/bills/$id/add-items'), body: jsonEncode({'items': items})));
}

Future<Map<String, dynamic>> updateBillItems(String id, List<Map<String, dynamic>> items) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/bills/$id/update-items'), body: jsonEncode({'items': items})));
}

Future<void> voidBill(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/bills/$id')));
}

// ---------------------------------------------------------------------------
// License
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getLicense() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/license')));
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getTodayReport() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/reports/today')));
}

Future<Map<String, dynamic>> getReportSummary({required String from, required String to}) async {
  final uri = Uri.parse('$baseUrl/reports/summary')
      .replace(queryParameters: {'from': from, 'to': to});
  return _parse(await _authGet(uri));
}

// ---------------------------------------------------------------------------
// Expenses
// ---------------------------------------------------------------------------

Future<List<dynamic>> getExpenses({String? from, String? to, String? category}) async {
  final params = <String, String>{};
  if (from != null) params['from'] = from;
  if (to != null) params['to'] = to;
  if (category != null) params['category'] = category;
  final uri = Uri.parse('$baseUrl/expenses')
      .replace(queryParameters: params.isEmpty ? null : params);
  return _parse(await _authGet(uri));
}

Future<Map<String, dynamic>> createExpense(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/expenses'), body: jsonEncode(data)));
}

Future<Map<String, dynamic>> updateExpense(String id, Map<String, dynamic> data) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/expenses/$id'), body: jsonEncode(data)));
}

Future<void> deleteExpense(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/expenses/$id')));
}

// ---------------------------------------------------------------------------
// Recurring Expenses
// ---------------------------------------------------------------------------

Future<List<dynamic>> getRecurringExpenses() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/expenses/recurring')));
}

Future<Map<String, dynamic>> createRecurringExpense(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/expenses/recurring'), body: jsonEncode(data)));
}

Future<Map<String, dynamic>> updateRecurringExpense(String id, Map<String, dynamic> data) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/expenses/recurring/$id'), body: jsonEncode(data)));
}

Future<void> deleteRecurringExpense(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/expenses/recurring/$id')));
}

Future<List<String>> getExpenseCategories() async {
  return List<String>.from(_parse(await _authGet(Uri.parse('$baseUrl/expenses/categories'))));
}

// ---------------------------------------------------------------------------
// Business profile
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getBusinessProfile() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/businesses/profile')));
}

Future<Map<String, dynamic>> updateBusinessProfile(Map<String, dynamic> data) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/businesses/profile'), body: jsonEncode(data)));
}

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

/// Returns true if the backend is reachable and DB is connected.
Future<bool> checkHealth() async {
  try {
    final response = await _get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 5));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}
