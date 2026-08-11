import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'storage.dart';
import 'providers/connectivity_provider.dart';

// const String baseUrl = 'https://vittam.vengurlatech.com/api';
const String baseUrl = 'http://192.168.1.3:5000/api';
const String _genericApiErrorMessage = 'Something went wrong';

String sanitizeUiErrorMessage(Object? error, {String fallback = _genericApiErrorMessage}) {
  if (error is ApiException) {
    // Prefer the human-readable message the server sent (e.g. validation errors
    // like "This phone number is already registered."). Fall back to the
    // exception's own message, then the generic fallback.
    if (error.serverMessage != null && error.serverMessage!.trim().isNotEmpty) {
      return error.serverMessage!.trim();
    }
    if (error.message.trim().isNotEmpty &&
        error.message.trim() != _genericApiErrorMessage) {
      return error.message.trim();
    }
  }
  return fallback;
}


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

/// Runs [send] and, if it fails because the server was unreachable, flips the
/// connectivity state to offline and rethrows a typed [NetworkException] so the
/// UI can show a "No internet" message instead of "Something went wrong". Any
/// other error (a real HTTP response, an ApiException) passes through untouched.
Future<http.Response> _safeSend(Future<http.Response> Function() send) async {
  try {
    return await send();
  } catch (e) {
    if (isNetworkError(e)) {
      _connectivityNotifier?.markOffline();
      throw const NetworkException();
    }
    rethrow;
  }
}

Future<http.Response> _safeGet(Uri uri, {Map<String, String>? headers}) =>
    _safeSend(() => _get(uri, headers: headers));

Future<http.Response> _safePost(Uri uri, {Map<String, String>? headers, Object? body}) =>
    _safeSend(() => _post(uri, headers: headers, body: body));

Future<http.Response> _safePut(Uri uri, {Map<String, String>? headers, Object? body}) =>
    _safeSend(() => _put(uri, headers: headers, body: body));

Future<http.Response> _safeDelete(Uri uri, {Map<String, String>? headers}) =>
    _safeSend(() => _delete(uri, headers: headers));

// Auth-aware wrappers — automatically refresh the access token on 401 and retry.
// Use these for all authenticated endpoints. All go through the safe* wrappers
// so a network failure on ANY verb marks the app offline and surfaces a typed
// NetworkException.

Future<http.Response> _authGet(Uri uri) =>
    _withAutoRefresh((h) => _safeGet(uri, headers: h));

Future<http.Response> _authPost(Uri uri, {Object? body}) =>
    _withAutoRefresh((h) => _safePost(uri, headers: h, body: body));

Future<http.Response> _authPut(Uri uri, {Object? body}) =>
    _withAutoRefresh((h) => _safePut(uri, headers: h, body: body));

Future<http.Response> _authDelete(Uri uri) =>
    _withAutoRefresh((h) => _safeDelete(uri, headers: h));

void _logRequest(String method, Uri uri, Map<String, String>? headers, {Object? body}) {
  final buf = StringBuffer();
  buf.writeln('→ $method ${uri.path}${uri.query.isNotEmpty ? '?${uri.query}' : ''}');
  if (body != null) buf.writeln('  body: $body');
  dev.log(buf.toString().trimRight(), name: 'API');
}

void _logResponse(String method, Uri uri, http.Response response) {
  // We reached the server and got an HTTP response — we are online. This clears
  // a stale "offline" state after connectivity is restored, without waiting for
  // a manual pull-to-refresh.
  _connectivityNotifier?.markOnline();
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
  final body = _decodeResponseBody(response.body);
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return body;
  }
  final serverMessage = _extractServerMessage(body);
  List<Map<String, dynamic>>? items;
  if (response.statusCode == 409 && body is Map<String, dynamic>) {
    final raw = body['items'];
    if (raw is List) {
      items = raw.whereType<Map<String, dynamic>>().toList();
    }
  }
  throw ApiException(
    _genericApiErrorMessage,
    response.statusCode,
    serverMessage: serverMessage,
    items: items,
  );
}

dynamic _decodeResponseBody(String responseBody) {
  if (responseBody.isEmpty) return null;
  try {
    return jsonDecode(responseBody);
  } catch (_) {
    return responseBody;
  }
}

String? _extractServerMessage(dynamic body) {
  if (body is Map<String, dynamic>) {
    final message = body['error'] ?? body['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
  }
  if (body is String && body.trim().isNotEmpty) {
    return body.trim();
  }
  return null;
}

Map<String, dynamic> _asJsonMap(
  dynamic body, {
  int statusCode = 500,
  String? serverMessage,
}) {
  if (body is Map<String, dynamic>) {
    return body;
  }
  if (body is Map) {
    return Map<String, dynamic>.from(body);
  }
  throw ApiException(
    _genericApiErrorMessage,
    statusCode,
    serverMessage: serverMessage ?? 'Unexpected response format',
  );
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
  final String? serverMessage;
  final List<Map<String, dynamic>>? items;

  ApiException(this.message, this.statusCode, {this.serverMessage, this.items});

  @override
  String toString() => message;
}

/// Thrown when a request could not reach the server at all — no DNS, no route,
/// connection refused, or a timeout. Distinct from [ApiException] (which means
/// the server WAS reached and returned an error). The UI uses this to show a
/// "No internet" message instead of a generic "Something went wrong".
class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'No internet connection']);

  @override
  String toString() => message;
}

/// True when [error] indicates the device could not reach the server — either an
/// explicit [NetworkException], or the raw socket/client errors that slip
/// through before classification. Used to pick the right UI message.
bool isNetworkError(Object? error) {
  if (error is NetworkException) return true;
  if (error is http.ClientException) return true;
  if (error is TimeoutException) return true;
  // dart:io SocketException — matched by name to avoid importing dart:io here
  // (this file is also compiled for web, where SocketException doesn't exist).
  final name = error.runtimeType.toString();
  return name == 'SocketException' || name == 'HttpException';
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
  String? refreshToken;
  try {
    refreshToken = await getRefreshToken();
  } on PlatformException catch (e) {
    // Secure storage failed to decrypt the stored value (e.g. on Windows,
    // the DPAPI key backing flutter_secure_storage was rotated/corrupted).
    // This is NOT recoverable by going online, so it must NOT be treated
    // as a transient/offline error — surface it as a real auth failure so
    // the caller prompts the user to log in again.
    throw ApiException('Local session data is unreadable. Please log in again.', 401,
        serverMessage: 'secure_storage_unreadable: ${e.message}');
  }
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

/// Returns { phone, message, receipt_url } for opening the user's own WhatsApp
/// (wa.me deep link) with a prefilled receipt message for [billId].
Future<Map<String, dynamic>> getBillWhatsAppText(String billId) async {
  final data = _parse(await _authGet(Uri.parse('$baseUrl/bills/$billId/whatsapp-text')));
  return Map<String, dynamic>.from(data as Map);
}

/// Single WhatsApp entry point. The backend decides by the business's
/// whatsapp_mode:
///   - 'api'      → it already sent the template; returns { mode:'api', sent:true }.
///   - 'deeplink' → returns { mode:'deeplink', phone, message } to open WhatsApp.
Future<Map<String, dynamic>> whatsAppBill(String billId) async {
  final data = _parse(await _authPost(Uri.parse('$baseUrl/bills/$billId/whatsapp')));
  return Map<String, dynamic>.from(data as Map);
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

// --- Item photos (owner-only; customer-facing on the QR menu) --------------

/// Owner-only list of items with their current [image_url]. Used by the Menu
/// Photos screen. The regular [getItems] omits image_url so photos never load
/// during billing.
Future<List<dynamic>> getItemsWithImages() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/items/with-images')));
}

/// Upload a compressed JPEG for [itemId]. [jpegBytes] must already be resized
/// and compressed on the device. Returns the new image_url (with a cache
/// buster). Sends the raw image bytes, not JSON.
Future<String> uploadItemImage(String itemId, List<int> jpegBytes) async {
  final uri = Uri.parse('$baseUrl/items/$itemId/image');
  final response = await _withAutoRefresh((h) {
    // Override the JSON content-type from _authHeaders with the raw image type;
    // keep the Authorization header.
    final headers = Map<String, String>.from(h)
      ..['Content-Type'] = 'image/jpeg';
    return _put(uri, headers: headers, body: jpegBytes);
  });
  final body = _parse(response) as Map<String, dynamic>;
  return body['image_url'] as String;
}

/// Remove [itemId]'s photo and clear its image_url.
Future<void> deleteItemImage(String itemId) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/items/$itemId/image')));
}

// Variants (sizes) — nested under an item.
Future<Map<String, dynamic>> createVariant(
    String itemId, Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/items/$itemId/variants'),
      body: jsonEncode(data)));
}

Future<Map<String, dynamic>> updateVariant(
    String itemId, String variantId, Map<String, dynamic> data) async {
  return _parse(await _authPut(
      Uri.parse('$baseUrl/items/$itemId/variants/$variantId'),
      body: jsonEncode(data)));
}

Future<void> deleteVariant(String itemId, String variantId) async {
  _parse(await _authDelete(
      Uri.parse('$baseUrl/items/$itemId/variants/$variantId')));
}

// ---------------------------------------------------------------------------
// Raw materials (restaurant ingredient inventory) + item recipes (BOM)
// ---------------------------------------------------------------------------

Future<List<dynamic>> getRawMaterials() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/raw-materials')));
}

Future<Map<String, dynamic>> createRawMaterial(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/raw-materials'), body: jsonEncode(data)));
}

Future<Map<String, dynamic>> updateRawMaterial(String id, Map<String, dynamic> data) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/raw-materials/$id'), body: jsonEncode(data)));
}

Future<void> deleteRawMaterial(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/raw-materials/$id')));
}

/// The recipe (raw-material consumption) for a sellable item.
Future<List<dynamic>> getItemRecipe(String itemId) async {
  return _parse(await _authGet(Uri.parse('$baseUrl/items/$itemId/recipe')));
}

/// Replaces an item's whole recipe. [rows] is a list of
/// `{ raw_material_id, quantity }`.
Future<void> setItemRecipe(String itemId, List<Map<String, dynamic>> rows) async {
  _parse(await _authPut(Uri.parse('$baseUrl/items/$itemId/recipe'),
      body: jsonEncode({'rows': rows})));
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

/// Regenerate a table's QR token, invalidating the old sticker. Owner-only.
Future<Map<String, dynamic>> rotateTableQr(String id) async {
  return _parse(
      await _authPost(Uri.parse('$baseUrl/tables/$id/qr/rotate')));
}

/// Public customer-ordering base URL (the same host as the API, minus `/api`).
/// A table's QR encodes `$orderBaseUrl/<qr_token>`.
final String orderBaseUrl =
    '${baseUrl.endsWith('/api') ? baseUrl.substring(0, baseUrl.length - 4) : baseUrl}/order';

/// Full customer-menu URL encoded into a table's QR sticker.
String tableOrderUrl(String qrToken) => '$orderBaseUrl/$qrToken';

// ---------------------------------------------------------------------------
// Kitchen (restaurant Kitchen Display)
// ---------------------------------------------------------------------------

/// Active orders (draft bills) with per-item kitchen status.
Future<List<dynamic>> getKitchenOrders() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/kitchen/orders')));
}

/// Mark a single dish 'ready' or back to 'pending'.
Future<Map<String, dynamic>> markKitchenItem(
    String itemId, String kitchenStatus) async {
  return _parse(await _authPut(
    Uri.parse('$baseUrl/kitchen/items/$itemId'),
    body: jsonEncode({'kitchen_status': kitchenStatus}),
  ));
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

/// Open orders (draft bills) that are NOT attached to a table — the queue shown
/// on the Open Orders page.
Future<List<dynamic>> getDraftBills() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/bills/drafts')));
}

Future<Map<String, dynamic>> createBill(Map<String, dynamic> data) async {
  return _parse(await _authPost(Uri.parse('$baseUrl/bills'), body: jsonEncode(data)));
}

// ---------------------------------------------------------------------------
// Credit (udhaari)
// ---------------------------------------------------------------------------

/// Debtor list for the Credit tab — one entry per customer who owes money.
Future<List<dynamic>> getCreditCustomers() async {
  return _parse(await _authGet(Uri.parse('$baseUrl/credit/customers')));
}

/// All unpaid credit bills for one customer (by phone), each with line items.
Future<List<dynamic>> getCreditCustomerBills(String phone) async {
  return _parse(await _authGet(
      Uri.parse('$baseUrl/credit/customers/${Uri.encodeComponent(phone)}/bills')));
}

/// Lightweight outstanding-credit summary for one phone. Returns
/// { outstanding, unpaid_count, bill_ids }. Used on the billing screen.
Future<Map<String, dynamic>> getCreditSummary(String phone) async {
  final data = _parse(await _authGet(Uri.parse(
      '$baseUrl/credit/customers/${Uri.encodeComponent(phone)}/summary')));
  return Map<String, dynamic>.from(data as Map);
}

/// Marks the given credit bills paid in one settlement with [paymentMode].
/// Returns the settled bills (with items) for building a merged receipt.
Future<Map<String, dynamic>> settleCreditBills(
    List<String> billIds, String paymentMode) async {
  return _parse(await _authPost(
    Uri.parse('$baseUrl/credit/settle'),
    body: jsonEncode({'bill_ids': billIds, 'payment_mode': paymentMode}),
  ));
}

Future<Map<String, dynamic>> finalizeBill(String id) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/bills/$id/finalize')));
}

Future<Map<String, dynamic>> addItemsToBill(String id, List<Map<String, dynamic>> items) async {
  return _parse(await _authPut(Uri.parse('$baseUrl/bills/$id/add-items'), body: jsonEncode({'items': items})));
}

Future<Map<String, dynamic>> updateBillItems(
  String id,
  List<Map<String, dynamic>> items, {
  String? customerName,
  String? customerPhone,
  double? discountAmount,
}) async {
  return _parse(await _authPut(
    Uri.parse('$baseUrl/bills/$id/update-items'),
    body: jsonEncode({
      'items': items,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (discountAmount != null) 'discount_amount': discountAmount,
    }),
  ));
}

Future<void> voidBill(String id) async {
  _parse(await _authDelete(Uri.parse('$baseUrl/bills/$id')));
}

// ---------------------------------------------------------------------------
// License
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getLicense() async {
  final body = _parse(await _authGet(Uri.parse('$baseUrl/license')));
  return _asJsonMap(body, statusCode: 200);
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

/// Last-7-days net sales per day, independent of the report period filter.
/// [date] is the device's local today (YYYY-MM-DD) so the window is correct
/// for non-UTC timezones. Returns { days: [{day, revenue}, …] } (7 entries).
Future<Map<String, dynamic>> getWeeklySales({String? date}) async {
  final uri = Uri.parse('$baseUrl/reports/weekly-sales').replace(
      queryParameters: date != null ? {'date': date} : null);
  final data = _parse(await _authGet(uri));
  return Map<String, dynamic>.from(data as Map);
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

// ---------------------------------------------------------------------------
// FCM tokens
// ---------------------------------------------------------------------------

Future<void> registerFcmToken(String token) async {
  _parse(await _authPost(
    Uri.parse('$baseUrl/fcm/token'),
    body: jsonEncode({'token': token}),
  ));
}

Future<void> deleteFcmToken(String token) async {
  _parse(await _authPost(
    Uri.parse('$baseUrl/fcm/token/remove'),
    body: jsonEncode({'token': token}),
  ));
}
