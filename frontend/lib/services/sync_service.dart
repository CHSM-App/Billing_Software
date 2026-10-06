import 'dart:convert';
import '../api.dart';
import 'offline_service.dart';

// ---------------------------------------------------------------------------
// SyncResult
// ---------------------------------------------------------------------------

class SyncResult {
  final int synced;
  final int failed;
  final int conflicted;

  const SyncResult({
    required this.synced,
    required this.failed,
    required this.conflicted,
  });

  bool get hasConflicts => conflicted > 0;
  bool get allOk => failed == 0 && conflicted == 0;
}

// ---------------------------------------------------------------------------
// SyncService
// ---------------------------------------------------------------------------

class SyncService {
  SyncService._();
  static final instance = SyncService._();

  bool _running = false;

  /// Push all pending offline bills to the server.
  ///
  /// Never throws — errors are absorbed and stored per-bill.
  ///
  /// Response classification:
  ///   HTTP 200   — server returned an *existing* bill (idempotent duplicate).
  ///                Treat as success and delete the local row.
  ///   HTTP 201   — new bill created successfully. Delete local row.
  ///   HTTP 409   — stock conflict: server has insufficient inventory.
  ///                Mark as [SyncStatus.conflict] — NO automatic retry.
  ///   HTTP 4xx   — other permanent rejection (bad payload etc.).
  ///                Mark as [SyncStatus.conflict] — NO automatic retry.
  ///   Network /
  ///   HTTP 5xx   — transient failure. Increment retry_count; retry next time.
  Future<SyncResult> syncAll() async {
    if (_running) return const SyncResult(synced: 0, failed: 0, conflicted: 0);
    _running = true;

    int synced     = 0;
    int failed     = 0;
    int conflicted = 0;

    try {
      final pending = await OfflineService.instance.getPendingBills();
      if (pending.isEmpty) {
        return const SyncResult(synced: 0, failed: 0, conflicted: 0);
      }

      for (final row in pending) {
        final localId = row['local_id'] as String;
        await OfflineService.instance.markBillSyncing(localId);

        try {
          final payload = _buildApiPayload(row);
          // createBill throws ApiException for non-2xx responses.
          await createBill(payload);

          // HTTP 200 (duplicate) or 201 (created) — both are success.
          await OfflineService.instance.markBillSynced(localId);
          synced++;
        } on ApiException catch (e) {
          if (_isPermanentRejection(e.statusCode)) {
            // 409 stock conflict or 4xx validation error — do not retry.
            // The user must resolve this manually via the conflict screen.
            final friendlyError = _friendlyError(e);
            await OfflineService.instance.markBillConflict(localId, friendlyError);
            conflicted++;
          } else {
            // 5xx or unexpected — transient, increment retry counter.
            await OfflineService.instance.markBillFailed(localId, e.toString());
            failed++;
          }
        } catch (e) {
          // SocketException, ClientException, etc. — transient.
          await OfflineService.instance.markBillFailed(localId, e.toString());
          failed++;
        }
      }

      // Then push queued drafts (open orders). Same idempotency contract via
      // client_bill_id; the server upserts on status:'draft'.
      final draftResult = await _syncDrafts();
      synced     += draftResult.synced;
      failed     += draftResult.failed;
      conflicted += draftResult.conflicted;
    } finally {
      _running = false;
    }

    return SyncResult(synced: synced, failed: failed, conflicted: conflicted);
  }

  /// Push queued offline drafts to POST /bills with status:'draft'. Because a
  /// draft carries a client_bill_id, a replay after a flaky first attempt is
  /// idempotent — the server returns the existing draft instead of duplicating.
  Future<SyncResult> _syncDrafts() async {
    int synced = 0, failed = 0, conflicted = 0;

    final pending = await OfflineService.instance.getPendingDrafts();
    for (final row in pending) {
      final localId = row['local_id'] as String;
      await OfflineService.instance.markDraftSyncing(localId);

      try {
        await createBill(_buildDraftPayload(row));
        await OfflineService.instance.markDraftSynced(localId);
        synced++;
      } on ApiException catch (e) {
        if (_isPermanentRejection(e.statusCode)) {
          await OfflineService.instance
              .markDraftConflict(localId, _friendlyError(e));
          conflicted++;
        } else {
          await OfflineService.instance.markDraftFailed(localId, e.toString());
          failed++;
        }
      } catch (e) {
        await OfflineService.instance.markDraftFailed(localId, e.toString());
        failed++;
      }
    }

    return SyncResult(synced: synced, failed: failed, conflicted: conflicted);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// A rejection is "permanent" when the server will never accept this exact
  /// payload regardless of how many times it is retried:
  ///   409 — stock conflict (items sold out while bill was queued)
  ///   400 — malformed request (bad item_id, missing fields, etc.)
  ///   422 — unprocessable entity
  ///   404 — referenced table/item no longer exists
  bool _isPermanentRejection(int statusCode) {
    return statusCode == 409 ||
        statusCode == 400 ||
        statusCode == 422 ||
        statusCode == 404;
  }

  /// Convert ApiException to a short, human-readable conflict reason that can
  /// be shown in the conflict resolution screen.
  String _friendlyError(ApiException e) {
    final serverMessage = e.serverMessage?.trim();
    if (e.statusCode == 409) {
      return (serverMessage != null && serverMessage.isNotEmpty)
          ? 'Insufficient stock: $serverMessage'
          : 'Insufficient stock';
    }
    if (e.statusCode == 404) return 'Item or table no longer exists';
    return serverMessage?.isNotEmpty == true ? serverMessage! : e.message;
  }

  /// Converts a stored offline_bills row into the POST /api/bills payload.
  /// Includes [client_bill_id] so the server can detect duplicate submissions.
  Map<String, dynamic> _buildApiPayload(Map<String, dynamic> row) {
    final lineItems = List<Map<String, dynamic>>.from(
      jsonDecode(row['items_json'] as String),
    );

    return {
      'client_bill_id': row['client_bill_id'] as String,
      // Preserve the offline bill number (INV-<tag>-####) the customer was
      // handed at print time — the server stores it verbatim instead of
      // assigning a new one.
      if (row['bill_number'] != null) 'bill_number': row['bill_number'],
      'items': lineItems
          .map((li) => {
                'item_id':  li['item_id'],
                if (li['variant_id'] != null) 'variant_id': li['variant_id'],
                'quantity': li['quantity'],
              })
          .toList(),
      if (row['table_id']       != null) 'table_id':       row['table_id'],
      if (row['customer_name']  != null) 'customer_name':  row['customer_name'],
      if (row['customer_phone'] != null) 'customer_phone': row['customer_phone'],
      // Preserve the discount and the invoice round-off exactly as printed on
      // the customer's receipt; the server stores round_off verbatim (like
      // bill_number) rather than recomputing it.
      if (((row['discount_amount'] as num?)?.toDouble() ?? 0.0) > 0)
        'discount_amount': (row['discount_amount'] as num).toDouble(),
      if (((row['round_off'] as num?)?.toDouble() ?? 0.0) != 0.0)
        'round_off': (row['round_off'] as num).toDouble(),
      // Additional charges exactly as printed; the server re-sums them.
      ..._chargesPayload(row),
      'payment_mode': row['payment_mode'],
      'status': 'finalized',
    };
  }

  /// `additional_charges` entry for a sync payload, decoded from the JSON the
  /// offline row stores. Omitted entirely when the bill carries none.
  Map<String, dynamic> _chargesPayload(Map<String, dynamic> row) {
    final raw = row['additional_charges'];
    if (raw is! String || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.isNotEmpty) {
        return {'additional_charges': decoded};
      }
    } catch (_) {}
    return const {};
  }

  /// Converts a stored offline_drafts row into a POST /api/bills draft payload.
  /// The server re-prices from item_id + quantity, so only the thin line form is
  /// sent; the stored priced items_json is for local display only.
  Map<String, dynamic> _buildDraftPayload(Map<String, dynamic> row) {
    final lineItems = List<Map<String, dynamic>>.from(
      jsonDecode(row['items_json'] as String),
    );
    final discount = (row['discount_amount'] as num?)?.toDouble() ?? 0.0;

    return {
      'client_bill_id': row['client_bill_id'] as String,
      'items': lineItems
          .map((li) => {
                'item_id':  li['item_id'],
                if (li['variant_id'] != null) 'variant_id': li['variant_id'],
                'quantity': li['quantity'],
              })
          .toList(),
      if (row['table_id']       != null) 'table_id':       row['table_id'],
      if (row['customer_name']  != null) 'customer_name':  row['customer_name'],
      if (row['customer_phone'] != null) 'customer_phone': row['customer_phone'],
      if (discount > 0)                  'discount_amount': discount,
      ..._chargesPayload(row),
      'payment_mode': row['payment_mode'],
      'status': 'draft',
    };
  }
}
