import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'storage.dart';
import 'providers/connectivity_provider.dart';

const String baseUrl = 'http://192.168.1.10:3000/api';

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
  } on SocketException {
    _connectivityNotifier?.markOffline();
    rethrow;
  } on http.ClientException {
    _connectivityNotifier?.markOffline();
    rethrow;
  }
}

Future<http.Response> _safePost(Uri uri, {Map<String, String>? headers, Object? body}) async {
  try {
    return await _post(uri, headers: headers, body: body);
  } on SocketException {
    _connectivityNotifier?.markOffline();
    rethrow;
  } on http.ClientException {
    _connectivityNotifier?.markOffline();
    rethrow;
  }
}

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
// Items
// ---------------------------------------------------------------------------

Future<List<dynamic>> getItems({String? search, String? category}) async {
  final params = <String, String>{};
  if (search != null) params['search'] = search;
  if (category != null) params['category'] = category;

  final uri = Uri.parse('$baseUrl/items').replace(queryParameters: params.isEmpty ? null : params);
  final response = await _safeGet(uri, headers: await _authHeaders());
  return _parse(response);
}

Future<Map<String, dynamic>> getItemByBarcode(String barcode) async {
  final uri = Uri.parse('$baseUrl/items').replace(queryParameters: {'barcode': barcode});
  final response = await _safeGet(uri, headers: await _authHeaders());
  return _parse(response);
}

Future<List<String>> getTopSoldItemIds() async {
  final response = await _safeGet(
    Uri.parse('$baseUrl/items/top-sold'),
    headers: await _authHeaders(),
  );
  return List<String>.from(_parse(response));
}

Future<List<String>> getCategories() async {
  final response = await _safeGet(
    Uri.parse('$baseUrl/items/categories'),
    headers: await _authHeaders(),
  );
  return List<String>.from(_parse(response));
}

Future<Map<String, dynamic>> createItem(Map<String, dynamic> data) async {
  final response = await _post(
    Uri.parse('$baseUrl/items'),
    headers: await _authHeaders(),
    body: jsonEncode(data),
  );
  return _parse(response);
}

Future<Map<String, dynamic>> updateItem(String id, Map<String, dynamic> data) async {
  final response = await _put(
    Uri.parse('$baseUrl/items/$id'),
    headers: await _authHeaders(),
    body: jsonEncode(data),
  );
  return _parse(response);
}

Future<void> deleteItem(String id) async {
  final response = await _delete(
    Uri.parse('$baseUrl/items/$id'),
    headers: await _authHeaders(),
  );
  _parse(response);
}

// ---------------------------------------------------------------------------
// Staff
// ---------------------------------------------------------------------------

Future<List<dynamic>> getStaff() async {
  final response = await _get(Uri.parse('$baseUrl/staff'), headers: await _authHeaders());
  return _parse(response);
}

Future<Map<String, dynamic>> createStaff(Map<String, dynamic> data) async {
  final response = await _post(
    Uri.parse('$baseUrl/staff'),
    headers: await _authHeaders(),
    body: jsonEncode(data),
  );
  return _parse(response);
}

Future<Map<String, dynamic>> updateStaff(String id, Map<String, dynamic> data) async {
  final response = await _put(
    Uri.parse('$baseUrl/staff/$id'),
    headers: await _authHeaders(),
    body: jsonEncode(data),
  );
  return _parse(response);
}

Future<void> deleteStaff(String id) async {
  final response = await _delete(
    Uri.parse('$baseUrl/staff/$id'),
    headers: await _authHeaders(),
  );
  _parse(response);
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

Future<List<dynamic>> getTables() async {
  final response = await _get(Uri.parse('$baseUrl/tables'), headers: await _authHeaders());
  return _parse(response);
}

Future<Map<String, dynamic>> createTable(Map<String, dynamic> data) async {
  final response = await _post(
    Uri.parse('$baseUrl/tables'),
    headers: await _authHeaders(),
    body: jsonEncode(data),
  );
  return _parse(response);
}

Future<Map<String, dynamic>> updateTable(String id, Map<String, dynamic> data) async {
  final response = await _put(
    Uri.parse('$baseUrl/tables/$id'),
    headers: await _authHeaders(),
    body: jsonEncode(data),
  );
  return _parse(response);
}

Future<void> deleteTable(String id) async {
  final response = await _delete(
    Uri.parse('$baseUrl/tables/$id'),
    headers: await _authHeaders(),
  );
  _parse(response);
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
  final response = await _get(uri, headers: await _authHeaders());
  return _parse(response);
}

Future<Map<String, dynamic>> getBill(String id) async {
  final response = await _get(Uri.parse('$baseUrl/bills/$id'), headers: await _authHeaders());
  return _parse(response);
}

Future<Map<String, dynamic>> createBill(Map<String, dynamic> data) async {
  final response = await _safePost(
    Uri.parse('$baseUrl/bills'),
    headers: await _authHeaders(),
    body: jsonEncode(data),
  );
  return _parse(response);
}

Future<Map<String, dynamic>> finalizeBill(String id) async {
  final response = await _put(
    Uri.parse('$baseUrl/bills/$id/finalize'),
    headers: await _authHeaders(),
  );
  return _parse(response);
}

Future<Map<String, dynamic>> addItemsToBill(String id, List<Map<String, dynamic>> items) async {
  final response = await _put(
    Uri.parse('$baseUrl/bills/$id/add-items'),
    headers: await _authHeaders(),
    body: jsonEncode({'items': items}),
  );
  return _parse(response);
}

Future<Map<String, dynamic>> updateBillItems(String id, List<Map<String, dynamic>> items) async {
  final response = await _put(
    Uri.parse('$baseUrl/bills/$id/update-items'),
    headers: await _authHeaders(),
    body: jsonEncode({'items': items}),
  );
  return _parse(response);
}

Future<void> voidBill(String id) async {
  final response = await _delete(
    Uri.parse('$baseUrl/bills/$id'),
    headers: await _authHeaders(),
  );
  _parse(response);
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> getTodayReport() async {
  final response = await _get(Uri.parse('$baseUrl/reports/today'), headers: await _authHeaders());
  return _parse(response);
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
