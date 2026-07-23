import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../services/notification_service.dart';

/// Kitchen Display for restaurants. Shows active orders (draft bills) with each
/// dish, letting the kitchen chef tick dishes as ready. Refreshes immediately
/// when a kitchen push notification (FCM) arrives.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  // Item ids currently being toggled — disables the tile to avoid double taps.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.instance.kitchenPing.addListener(_onPing);
  }

  @override
  void dispose() {
    NotificationService.instance.kitchenPing.removeListener(_onPing);
    super.dispose();
  }

  void _onPing() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await getKitchenOrders();
      if (!mounted) return;
      setState(() {
        _orders = data.cast<Map<String, dynamic>>();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    // Only the kitchen chef may mark dishes ready; others have a read-only view.
    if (ref.read(userRoleProvider) != 'kitchen') return;
    final id = item['id'] as String;
    if (_busy.contains(id)) return;
    final current = item['kitchen_status'] as String? ?? 'pending';
    final next = current == 'ready' ? 'pending' : 'ready';

    setState(() {
      _busy.add(id);
      item['kitchen_status'] = next; // optimistic
    });
    try {
      await markKitchenItem(id, next);
    } catch (e) {
      if (mounted) {
        setState(() => item['kitchen_status'] = current); // revert
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
    // Refresh so an order that just became fully ready reflects immediately.
    _load(silent: true);
  }

  String _orderLabel(Map<String, dynamic> o) {
    final l10n = context.l10n;
    final tableNumber = o['table_number'];
    if (tableNumber != null) return l10n.kitchenTable('$tableNumber');
    final name = o['customer_name'];
    if (name != null && '$name'.isNotEmpty) return '$name';
    return '${o['bill_number'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.kitchenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.commonRefresh,
            onPressed: () => _load(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: _buildBody(l10n),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _orders.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(_error!, textAlign: TextAlign.center)),
        ],
      );
    }
    if (_orders.isEmpty) {
      return Stack(
        children: [
          ListView(), // keeps pull-to-refresh working when empty
          EmptyState(
            icon: Icons.restaurant_menu,
            message: l10n.kitchenNoOrders,
          ),
        ],
      );
    }

    final canEdit = ref.read(userRoleProvider) == 'kitchen';
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = AppSpacing.space8;
      const padding = AppSpacing.space12;
      // How many columns fit, aiming for ~240px per card so small devices show
      // an extra column. Each card takes an equal share of the width and keeps
      // its natural height (grows with its dish count), never a fixed grid box.
      final cols =
          ((constraints.maxWidth - padding * 2) / 240).floor().clamp(1, 5);
      final cardWidth =
          (constraints.maxWidth - padding * 2 - spacing * (cols - 1)) / cols;

      // Masonry layout: place each order into the currently shortest column so
      // cards pack tightly top-to-bottom with no gaps between them. Height is
      // estimated from the header + one row per dish.
      final columns = List.generate(cols, (_) => <Widget>[]);
      final columnHeights = List.filled(cols, 0.0);
      for (int i = 0; i < _orders.length; i++) {
        final order = _orders[i];
        int target = 0;
        for (int c = 1; c < cols; c++) {
          if (columnHeights[c] < columnHeights[target]) target = c;
        }
        final itemCount = (order['items'] as List).length;
        // ~40px header + ~30px per dish row; exact value is irrelevant, it only
        // needs to order columns by relative fullness.
        columnHeights[target] += 40 + itemCount * 30 + spacing;
        columns[target].add(Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: _OrderCard(
            order: order,
            // Queue position — orders are oldest-first, so #1 is prepared first.
            sequence: i + 1,
            label: _orderLabel(order),
            busy: _busy,
            canEdit: canEdit,
            onToggle: _toggle,
          ),
        ));
      }

      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(padding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int c = 0; c < cols; c++) ...[
              if (c > 0) const SizedBox(width: spacing),
              SizedBox(
                width: cardWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: columns[c],
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Order-age label for a kitchen card: "Just now" (<1 min), "N min ago"
/// (<1 hr), and the local clock time (e.g. "02:45 PM") once an hour or more has
/// passed. [createdAtIso] is the UTC ISO timestamp from the API.
String _orderTimeLabel(BuildContext context, String? createdAtIso) {
  if (createdAtIso == null) return '';
  final created = DateTime.tryParse(createdAtIso);
  if (created == null) return '';
  final diff = DateTime.now().difference(created.toLocal());
  final l10n = context.l10n;
  if (diff.inMinutes < 1) return l10n.kitchenJustNow;
  if (diff.inMinutes < 60) return l10n.kitchenMinAgo(diff.inMinutes);
  return DateFormat('hh:mm a').format(created.toLocal());
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final int sequence;
  final String label;
  final Set<String> busy;
  final bool canEdit;
  final Future<void> Function(Map<String, dynamic>) onToggle;

  const _OrderCard({
    required this.order,
    required this.sequence,
    required this.label,
    required this.busy,
    required this.canEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final allReady = order['all_ready'] == true;

    return AppCard(
      padding: EdgeInsets.zero,
      color: allReady ? AppColors.successLight : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space8, vertical: 6),
            child: Row(
              children: [
                // Queue number — the chef prepares lower numbers first.
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: allReady ? AppColors.success : AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(
                    '$sequence',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                Builder(builder: (context) {
                  final timeLabel =
                      _orderTimeLabel(context, order['created_at'] as String?);
                  if (timeLabel.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 2),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }),
                if (allReady)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      l10n.kitchenReady,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Shrink-wrapped list so the card's height follows its dish count.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _buildItemTile(context, items[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, Map<String, dynamic> item) {
    final ready = item['kitchen_status'] == 'ready';
    final id = item['id'] as String;
    final qty = (item['quantity'] as num?) ?? 1;
    final qtyLabel =
        qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();

    // Compact custom row instead of ListTile, which forces a ~48px min height
    // even when dense. This packs more dishes into each card.
    final enabled = canEdit && !busy.contains(id);
    return InkWell(
      onTap: enabled ? () => onToggle(item) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space8, vertical: 6),
        child: Row(
          children: [
            // Checkbox only for the kitchen chef, who can tick dishes off.
            // Read-only viewers see readiness via the strikethrough + badge.
            if (canEdit) ...[
              Icon(
                ready ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: ready ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                '${item['item_name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  decoration: ready ? TextDecoration.lineThrough : null,
                  color:
                      ready ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '× $qtyLabel',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
