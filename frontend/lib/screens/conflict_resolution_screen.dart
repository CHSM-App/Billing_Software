import 'package:flutter/material.dart';
import '../services/offline_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// ConflictResolutionScreen
//
// Shows bills that could not be synced permanently (stock conflicts, deleted
// items, etc.) and lets the owner either retry or dismiss each one.
//
// Navigation:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => const ConflictResolutionScreen(),
//   ));
// ---------------------------------------------------------------------------

class ConflictResolutionScreen extends StatefulWidget {
  const ConflictResolutionScreen({super.key});

  @override
  State<ConflictResolutionScreen> createState() =>
      _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<Map<String, dynamic>> _conflicts  = [];
  List<Map<String, dynamic>> _exhausted  = [];
  bool _loading  = true;
  bool _syncing  = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final conflicts = await OfflineService.instance.getConflictedBills();
    final exhausted = await OfflineService.instance.getExhaustedBills();
    if (mounted) {
      setState(() {
        _conflicts = conflicts;
        _exhausted = exhausted;
        _loading   = false;
      });
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _requeue(String localId) async {
    await OfflineService.instance.requeueConflictedBill(localId);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill queued for retry')),
    );
  }

  Future<void> _dismiss(String localId) async {
    final confirmed = await _confirmDismiss();
    if (!confirmed) return;
    await OfflineService.instance.dismissBill(localId);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill dismissed')),
    );
  }

  Future<void> _retryAll() async {
    setState(() => _syncing = true);
    // Requeue all conflicted bills then sync immediately.
    for (final row in _conflicts) {
      await OfflineService.instance.requeueConflictedBill(
          row['local_id'] as String);
    }
    final result = await SyncService.instance.syncAll();
    await _load();
    if (!mounted) return;
    setState(() => _syncing = false);

    final msg = result.synced > 0
        ? '${result.synced} bill(s) synced'
        : result.conflicted > 0
            ? '${result.conflicted} conflict(s) remain'
            : 'Nothing synced';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirmDismiss() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Dismiss bill?'),
            content: const Text(
              'This bill will be permanently removed from the queue. '
              'It will not be recorded in the system.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Unsynced Bills'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(
              text: 'Conflicts${_conflicts.isEmpty ? '' : ' (${_conflicts.length})'}',
            ),
            Tab(
              text: 'Failed${_exhausted.isEmpty ? '' : ' (${_exhausted.length})'}',
            ),
          ],
        ),
        actions: [
          if (_conflicts.isNotEmpty)
            _syncing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _retryAll,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry All'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary),
                  ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _BillList(
                  rows: _conflicts,
                  emptyMessage: 'No stock conflicts — all clear.',
                  emptyIcon: Icons.check_circle_outline,
                  onRequeue: _requeue,
                  onDismiss: _dismiss,
                  showRequeue: true,
                ),
                _BillList(
                  rows: _exhausted,
                  emptyMessage: 'No permanently failed bills.',
                  emptyIcon: Icons.check_circle_outline,
                  onRequeue: _requeue,
                  onDismiss: _dismiss,
                  showRequeue: true,
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BillList — shared list widget for both tabs
// ---------------------------------------------------------------------------

class _BillList extends StatelessWidget {
  const _BillList({
    required this.rows,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onRequeue,
    required this.onDismiss,
    required this.showRequeue,
  });

  final List<Map<String, dynamic>> rows;
  final String emptyMessage;
  final IconData emptyIcon;
  final Future<void> Function(String localId) onRequeue;
  final Future<void> Function(String localId) onDismiss;
  final bool showRequeue;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 56, color: AppColors.accent),
            const SizedBox(height: 12),
            Text(emptyMessage,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _BillCard(
        row: rows[i],
        onRequeue: showRequeue ? onRequeue : null,
        onDismiss: onDismiss,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BillCard — one conflicted/failed bill
// ---------------------------------------------------------------------------

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.row,
    required this.onRequeue,
    required this.onDismiss,
  });

  final Map<String, dynamic> row;
  final Future<void> Function(String)? onRequeue;
  final Future<void> Function(String) onDismiss;

  @override
  Widget build(BuildContext context) {
    final localId    = row['local_id']    as String;
    final total      = (row['total']      as num).toDouble();
    final payMode    = row['payment_mode'] as String;
    final error      = row['sync_error']  as String? ?? 'Unknown error';
    final retryCount = (row['retry_count'] as int?) ?? 0;
    final createdMs  = row['created_at']  as int;
    final createdAt  = DateTime.fromMillisecondsSinceEpoch(createdMs);

    final items = OfflineService.decodeItems(row['items_json'] as String);
    final isConflict = (row['sync_status'] as String) == SyncStatus.conflict;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConflict ? AppColors.warningLight : AppColors.errorLight,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isConflict ? AppColors.warningLight : AppColors.errorLight,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(
                  isConflict ? Icons.warning_amber_rounded : Icons.error_outline,
                  size: 16,
                  color: isConflict ? AppColors.warning : AppColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isConflict ? 'Stock conflict' : 'Failed after $retryCount retries',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isConflict ? AppColors.warning : AppColors.error,
                    ),
                  ),
                ),
                Text(
                  _formatDate(createdAt),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // ── Bill summary ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _payModeLabel(payMode),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                _ItemCountBadge(count: items.length),
              ],
            ),
          ),

          // ── Item list (collapsed to 3 lines) ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        const Text('• ',
                            style:
                                TextStyle(color: AppColors.textSecondary)),
                        Expanded(
                          child: Text(
                            '${item['item_name']} × ${item['quantity']}',
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (items.length > 3)
                  Text(
                    '+${items.length - 3} more item(s)',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),

          // ── Error reason ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Action buttons ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                // Dismiss — always available
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onDismiss(localId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Dismiss'),
                  ),
                ),
                if (onRequeue != null) ...[
                  const SizedBox(width: 8),
                  // Retry — visible for both conflicts and exhausted
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => onRequeue!(localId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 0,
                      ),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _payModeLabel(String mode) {
    const labels = {
      'cash': 'Cash',
      'upi': 'UPI',
      'card': 'Card',
      'credit': 'Credit',
      'other': 'Other',
    };
    return labels[mode] ?? mode;
  }
}

// ---------------------------------------------------------------------------
// _ItemCountBadge
// ---------------------------------------------------------------------------

class _ItemCountBadge extends StatelessWidget {
  const _ItemCountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count item${count == 1 ? '' : 's'}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
