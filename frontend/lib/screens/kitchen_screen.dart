import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/skeletons.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/floating_bar_physics.dart';
import '../services/notification_service.dart';
import '../services/printer_service.dart';
import '../storage.dart';
import 'kitchen_print_settings_screen.dart';

/// Dishes the kitchen has marked ready that nobody has delivered yet — the red
/// count on the Kitchen nav icon. Written by [KitchenScreen] on every reload;
/// the screen lives in the shell's IndexedStack and reloads on each realtime
/// 'kitchen' event, so the count stays live without a manual refresh.
final kitchenReadyCountProvider = StateProvider<int>((_) => 0);

/// Kitchen Display for restaurants. Shows active orders (draft bills) with each
/// dish, letting the kitchen chef tick dishes as ready and the floor staff mark
/// ready dishes delivered. Refreshes immediately when a kitchen push
/// notification (FCM) arrives.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  /// The status a tap moves [item] to for this user, or null when they cannot
  /// touch it. Mirrors the server's rules in routes/kitchen.js: the chef ticks
  /// pending <-> ready; everyone else marks a ready dish delivered (or undoes).
  static String? nextStatus(String role, Map<String, dynamic> item) {
    final current = item['kitchen_status'] as String? ?? 'pending';
    if (role == 'kitchen') {
      return switch (current) {
        'pending' => 'ready',
        'ready' => 'pending',
        _ => null,
      };
    }
    return switch (current) {
      'ready' => 'delivered',
      'delivered' => 'ready',
      _ => null,
    };
  }

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  // Item ids currently being toggled — disables the tile to avoid double taps.
  final Set<String> _busy = {};
  late final TabController _tabController;
  // Pending tab filter: only dishes that are ready and still to be served.
  bool _readyOnly = false;

  // Order ids seen on the last load. When a reload reveals an id not in this
  // set, a genuinely new order has arrived and we chime — but only while this
  // screen is alive (i.e. the app is open on the kitchen display).
  Set<String> _seenOrderIds = {};
  // First load never chimes; there's no "before" state to compare against.
  bool _primed = false;
  final AudioPlayer _chimePlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Switching Pending/Completed shows the title row again: the other tab's
    // list has its own scroll position.
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_header.show);
    _load();
    NotificationService.instance.kitchenPing.addListener(_onPing);
  }

  @override
  void dispose() {
    NotificationService.instance.kitchenPing.removeListener(_onPing);
    _chimePlayer.dispose();
    _tabController.dispose();
    _header.dispose();
    super.dispose();
  }

  /// Phone layout: the title row folds away with the order list while the
  /// Pending/Completed row stays pinned — see [FoldingHeader].
  late final FoldingHeader _header = FoldingHeader(
    vsync: this,
    extent: () => 50, // ShellAppBar's toolbar row
    canFold: () => MediaQuery.sizeOf(context).width < 720,
  );

  void _onPing() => _load(silent: true);

  /// Print a kitchen ticket for each newly-arrived order, when the setting is
  /// on. Best-effort by design: the queue is what the kitchen actually works
  /// from, so a printer that is switched off or out of range must never stop
  /// orders appearing on screen.
  ///
  /// Sequential, not concurrent — two jobs sent at once collide on a Bluetooth
  /// link, the same reason [PrinterService.printBills] pauses between receipts.
  /// The first failure stops the run: if the printer is unreachable the rest
  /// will fail too, and one warning is enough.
  Future<void> _autoPrintNewOrders(List<Map<String, dynamic>> orders) async {
    if (orders.isEmpty) return;
    if (!await getKitchenAutoPrint()) return;

    final dots = PaperSizes.thermalDots(await getKitchenPaperSize());
    for (final order in orders) {
      try {
        await PrinterService.instance
            .printKitchenTicket(order, paperDots: dots);
      } catch (e) {
        debugPrint('Kitchen auto-print failed: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Kitchen ticket did not print: '
              '${sanitizeUiErrorMessage(e)}'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
    }
  }

  Future<void> _playNewOrderChime() async {
    try {
      await _chimePlayer.stop();
      await _chimePlayer.play(AssetSource('sounds/new_order.mp3'));
    } catch (e) {
      // Sound is a non-critical nicety — never let it break the queue refresh.
      debugPrint('Kitchen chime failed: $e');
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await getKitchenOrders();
      if (!mounted) return;
      final orders = data.cast<Map<String, dynamic>>();
      final ids =
          orders.map((o) => '${o['id']}').where((id) => id.isNotEmpty).toSet();
      // Chime if any order id is new since the last load. Skip the very first
      // load so opening the screen with a backlog stays silent.
      // The ids themselves, not just "was there one" — auto-print needs to know
      // WHICH orders are new so it prints those and nothing else.
      final newIds = _primed ? ids.difference(_seenOrderIds) : const <String>{};
      // Recorded before printing starts, so a reload that lands mid-print
      // cannot queue the same ticket twice.
      _seenOrderIds = ids;
      _primed = true;
      if (newIds.isNotEmpty) {
        _playNewOrderChime();
        unawaited(_autoPrintNewOrders(
            orders.where((o) => newIds.contains('${o['id']}')).toList()));
      }
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
      _publishReadyCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _publishReadyCount() {
    var n = 0;
    for (final o in _orders) {
      for (final i in (o['items'] as List)) {
        if (i['kitchen_status'] == 'ready') n++;
      }
    }
    ref.read(kitchenReadyCountProvider.notifier).state = n;
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    final next = KitchenScreen.nextStatus(ref.read(userRoleProvider), item);
    if (next == null) return;
    final id = item['id'] as String;
    if (_busy.contains(id)) return;
    final current = item['kitchen_status'] as String? ?? 'pending';

    setState(() {
      _busy.add(id);
      item['kitchen_status'] = next; // optimistic
    });
    _publishReadyCount();
    try {
      await markKitchenItem(id, next);
    } catch (e) {
      if (mounted) {
        setState(() => item['kitchen_status'] = current); // revert
        _publishReadyCount();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(sanitizeUiErrorMessage(e)),
              backgroundColor: AppColors.error),
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

  // "Mark as Completed" ticks every not-yet-ready dish in the order at once,
  // so the whole card turns green (cooked). The order only moves to the
  // Completed tab once floor staff have delivered every dish (server-computed
  // all_delivered). If a new dish is later added to this same order (e.g. the
  // table orders more), that dish starts pending again, all_delivered flips back to
  // false, and the order reappears in Pending — no separate "completed" flag to
  // get out of sync with the dishes themselves.
  Future<void> _markOrderCompleted(Map<String, dynamic> order) async {
    if (ref.read(userRoleProvider) != 'kitchen') return;
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final pendingItems =
        items.where((i) => i['kitchen_status'] == 'pending').toList();
    if (pendingItems.isEmpty) return;

    final ids = pendingItems.map((i) => i['id'] as String).toList();
    setState(() {
      _busy.addAll(ids);
      for (final i in pendingItems) {
        i['kitchen_status'] = 'ready'; // optimistic
      }
    });
    try {
      await Future.wait(ids.map((id) => markKitchenItem(id, 'ready')));
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final i in pendingItems) {
            i['kitchen_status'] = 'pending'; // revert
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(sanitizeUiErrorMessage(e)),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.removeAll(ids));
    }
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final readyCount = ref.watch(kitchenReadyCountProvider);
    // ShellAppBar, not Scaffold.appBar: this screen is a tab inside the shell's
    // IndexedStack, where AppBar's Scaffold-dependent layout does not render —
    // which is why the bar (and everything in it) was invisible here.
    // Folded on a phone, then widened (where it never folds): open it back up.
    if (MediaQuery.sizeOf(context).width >= 720 && _header.bar.value < 1) {
      _header.bar.value = 1;
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        // The status-bar band stays put; the title row folds away beneath it
        // while the Pending/Completed row (+ divider) always stays.
        ColoredBox(
          color: AppColors.surface,
          child: SizedBox(
              width: double.infinity,
              height: MediaQuery.paddingOf(context).top),
        ),
        FoldAway(
          bar: _header.bar.drive(Tween(
              begin: (kTextTabBarHeight + 1) / (50 + kTextTabBarHeight + 1),
              end: 1.0)),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child:
        ShellAppBar(
          title: Text(l10n.kitchenTitle),
          automaticallyImplyLeading: false,
          actions: [
            // The pass printer belongs to the kitchen station, so this is the
            // ONLY way into its settings and only the kitchen sees it. Owners,
            // cashiers and servers can all watch this queue, but none of them
            // is standing at the printer being configured — and the Settings
            // entry that used to duplicate this is gone.
            if (ref.watch(userRoleProvider) == 'kitchen')
              IconButton(
                icon: const Icon(Icons.print_outlined),
                tooltip: 'Kitchen printing',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const KitchenPrintSettingsScreen(),
                )),
              ),
            ReadyToServeToggle(
              count: readyCount,
              selected: _readyOnly,
              tooltip: l10n.kitchenReadyOnly,
              onTap: () {
                setState(() => _readyOnly = !_readyOnly);
                // The filter lives on Pending — jump there if switched on
                // from Completed so the result is actually visible.
                if (_readyOnly) _tabController.animateTo(0);
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.commonRefresh,
              onPressed: () => _load(),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              // Renamed while filtered so it is obvious the list is cut down.
              Tab(
                  text: _readyOnly
                      ? l10n.kitchenReadyOnly
                      : l10n.kitchenTabPending),
              Tab(text: l10n.kitchenTabCompleted),
            ],
          ),
        ),
          ),
        ),
        Expanded(
          // Hands the order lists the folding physics and listens to them.
          child: _header.wrap(context, _loading
              ? const KitchenSkeleton()
              : _error != null && _orders.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                            child: Text(_error!, textAlign: TextAlign.center)),
                      ],
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        RefreshIndicator(
                          onRefresh: () => _load(),
                          child: _readyOnly
                              ? _buildOrderGrid(
                                  _readyToServe(), l10n.kitchenNoReadyItems)
                              : _buildOrderGrid(
                                  _orders
                                      .where((o) => o['all_delivered'] != true)
                                      .toList(),
                                  l10n.kitchenNoPendingOrders,
                                ),
                        ),
                        RefreshIndicator(
                          onRefresh: () => _load(),
                          child: _buildOrderGrid(
                            _orders
                                .where((o) => o['all_delivered'] == true)
                                .toList(),
                            l10n.kitchenNoCompletedOrders,
                          ),
                        ),
                      ],
                    )),
        ),
      ]),
    );
  }

  /// The "Ready to serve" filter: every order (fully-cooked ones included —
  /// those still hold dishes to take out) cut down to its ready,
  /// not-yet-delivered dishes; orders left with none are dropped. Item maps are shared with [_orders], so taps on the
  /// filtered view update the real data.
  List<Map<String, dynamic>> _readyToServe() => [
        for (final o in _orders)
          if ((o['items'] as List).any((i) => i['kitchen_status'] == 'ready'))
            {
              ...o,
              'items': (o['items'] as List)
                  .where((i) => i['kitchen_status'] == 'ready')
                  .toList(),
            },
      ];

  Widget _buildOrderGrid(
      List<Map<String, dynamic>> orders, String emptyMessage) {
    if (orders.isEmpty) {
      return Stack(
        children: [
          ListView(), // keeps pull-to-refresh working when empty
          EmptyState(
            icon: Icons.restaurant_menu,
            message: emptyMessage,
          ),
        ],
      );
    }

    final role = ref.read(userRoleProvider);
    return kitchenMasonry(
      itemCounts: [for (final o in orders) (o['items'] as List).length],
      cards: [
        for (int i = 0; i < orders.length; i++)
          _OrderCard(
            order: orders[i],
            // Queue position — orders are oldest-first, so #1 is prepared first.
            sequence: i + 1,
            label: _orderLabel(orders[i]),
            busy: _busy,
            role: role,
            onToggle: _toggle,
            onMarkCompleted: _markOrderCompleted,
          ),
      ],
    );
  }
}

/// Scrollable masonry of order cards — shared by the Kitchen page and the
/// Orders page's Open Orders. [itemCounts] (dish rows per card) is only used to
/// estimate card heights for packing.
Widget kitchenMasonry(
    {required List<Widget> cards, required List<int> itemCounts}) {
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
    for (int i = 0; i < cards.length; i++) {
      int target = 0;
      for (int c = 1; c < cols; c++) {
        if (columnHeights[c] < columnHeights[target]) target = c;
      }
      // ~40px header + ~30px per dish row; exact value is irrelevant, it only
      // needs to order columns by relative fullness.
      columnHeights[target] += 40 + itemCounts[i] * 30 + spacing;
      columns[target].add(Padding(
        padding: const EdgeInsets.only(bottom: spacing),
        child: cards[i],
      ));
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      // + the floating nav bar's inset, so the last cards scroll above it.
      padding: const EdgeInsets.all(padding).copyWith(
          bottom: padding + MediaQuery.paddingOf(context).bottom),
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

/// Header pill that filters Pending down to dishes waiting to be served: a
/// bell plus the live ready count. Outlined when off, solid green when on.
class ReadyToServeToggle extends StatelessWidget {
  final int count;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const ReadyToServeToggle({
    super.key,
    required this.count,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.success;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected ? AppColors.success : Colors.transparent,
          shape: StadiumBorder(
              side: BorderSide(color: AppColors.success, width: 1.5)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      selected
                          ? Icons.room_service
                          : Icons.room_service_outlined,
                      size: 18,
                      color: fg),
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Order-age label for a kitchen card: "Just now" (<1 min), "N min ago"
/// (<1 hr), and the local clock time (e.g. "02:45 PM") once an hour or more has
/// passed. [createdAtIso] is the UTC ISO timestamp from the API.
String orderTimeLabel(BuildContext context, String? createdAtIso) {
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
  final String role;
  final Future<void> Function(Map<String, dynamic>) onToggle;
  final Future<void> Function(Map<String, dynamic>) onMarkCompleted;

  const _OrderCard({
    required this.order,
    required this.sequence,
    required this.label,
    required this.busy,
    required this.role,
    required this.onToggle,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    // Every dish cooked (ready or already delivered) — the card goes green with
    // a READY tag, even while it waits in Pending for delivery.
    final allReady = items.isNotEmpty &&
        items.every((i) =>
            const ['ready', 'delivered'].contains(i['kitchen_status']));
    final canEdit = role == 'kitchen';

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
                      orderTimeLabel(context, order['created_at'] as String?);
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
          // The customer's instruction for this order ("no onions", "less
          // spicy"). Deliberately loud — it is the one thing on the card the
          // kitchen has to read rather than tick, and it used to never arrive
          // here at all.
          Builder(builder: (_) {
            final note = (order['notes'] as String?)?.trim() ?? '';
            if (note.isEmpty) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              color: AppColors.warning.withValues(alpha: 0.12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Shrink-wrapped list so the card's height follows its dish count.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                KitchenItemTile(
                  item: items[i],
                  role: role,
                  busy: busy,
                  onToggle: onToggle,
                ),
              ],
            ],
          ),
          // Lets the chef complete the whole order in one tap instead of
          // ticking every dish individually. Ticking the last dish by hand
          // has the same effect — this just moves the order to Completed
          // immediately without needing every dish tapped one by one.
          if (canEdit &&
              !allReady &&
              items.any((i) => i['kitchen_status'] == 'pending'))
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy
                          .intersection(
                              items.map((i) => i['id'] as String).toSet())
                          .isEmpty
                      ? () => onMarkCompleted(order)
                      : null,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(l10n.kitchenMarkCompleted),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single dish row in an order card. Stateful so it can play a smooth
/// scale-in animation on the green "ready" circle the moment a dish is marked
/// complete — visible to every role (chef, owner, waiter), not just a
/// strikethrough. The chef taps to toggle pending/ready; floor staff tap a
/// ready dish to mark it delivered (and again to undo).
class KitchenItemTile extends StatefulWidget {
  final Map<String, dynamic> item;
  final String role;
  final Set<String> busy;
  final Future<void> Function(Map<String, dynamic>) onToggle;

  const KitchenItemTile({
    super.key,
    required this.item,
    required this.role,
    required this.busy,
    required this.onToggle,
  });

  @override
  State<KitchenItemTile> createState() => _KitchenItemTileState();
}

class _KitchenItemTileState extends State<KitchenItemTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late bool _ready;

  // Delivered is still "done" in the kitchen's eyes: greyed, no pop.
  bool get _isReady =>
      const ['ready', 'delivered'].contains(widget.item['kitchen_status']);

  @override
  void initState() {
    super.initState();
    _ready = _isReady;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
      // Already-ready dishes start fully shown (no pop on first paint).
      value: _ready ? 1.0 : 0.0,
    );
    // A gentle over-shoot so the circle "pops" in when a dish becomes ready.
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
  }

  @override
  void didUpdateWidget(KitchenItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to readiness changing (e.g. a realtime refresh flips the status):
    // animate the circle in when it becomes ready, out when it's un-ticked.
    if (_isReady != _ready) {
      _ready = _isReady;
      if (_ready) {
        _controller.forward(from: 0.0);
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ready = _ready;
    final id = item['id'] as String;
    final qty = (item['quantity'] as num?) ?? 1;
    final qtyLabel =
        qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();

    final delivered = item['kitchen_status'] == 'delivered';

    // Compact custom row instead of ListTile, which forces a ~48px min height
    // even when dense. This packs more dishes into each card.
    final enabled =
        KitchenScreen.nextStatus(widget.role, item) != null &&
            !widget.busy.contains(id);
    return InkWell(
      onTap: enabled ? () => widget.onToggle(item) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: delivered
            ? AppColors.background
            : ready
                ? AppColors.successLight
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space8, vertical: 6),
        child: Row(
          children: [
            // A green check circle marks a completed dish for EVERY role. It
            // scales in with a little pop the moment the chef ticks it, so
            // owners and waiters watching the queue see completion clearly —
            // not just a thin strikethrough. When not ready: the chef sees an
            // empty tick target; read-only roles see nothing.
            _buildLeading(ready, delivered),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      '${item['item_name']}'
                      '${item['diner_name'] != null && (item['diner_name'] as String).isNotEmpty ? ' · ${item['diner_name']}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: ready ? FontWeight.w500 : FontWeight.normal,
                        color: ready
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (delivered) ...[
              const SizedBox(width: 6),
              Text(
                context.l10n.kitchenDelivered,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(width: 6),
            Text(
              '× $qtyLabel',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  /// The leading indicator: a grey double-tick once delivered, a green filled
  /// circle with a white check when ready (animated), otherwise an empty tick
  /// outline for the chef and a blank spacer for everyone else.
  Widget _buildLeading(bool ready, bool delivered) {
    if (delivered) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.textSecondary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.done_all, size: 13, color: Colors.white),
        ),
      );
    }
    if (ready) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 14, color: Colors.white),
          ),
        ),
      );
    }
    // Not ready: the chef gets a tappable empty circle; other roles get a
    // matching-width spacer so text stays aligned across rows.
    if (widget.role == 'kitchen') {
      return const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.radio_button_unchecked,
            size: 20, color: AppColors.textSecondary),
      );
    }
    return const SizedBox(width: 26);
  }
}
