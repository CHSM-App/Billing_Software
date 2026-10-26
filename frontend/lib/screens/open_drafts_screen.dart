import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../models/cart_entry.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/skeletons.dart';
import 'home_screen.dart';
import 'kitchen_screen.dart';

/// One card on the Open Orders board: the draft, its queue number, and the
/// dishes to list (all of them, or only the ready ones under the filter).
typedef OpenOrderTicket = ({Bill bill, int seq, List<BillItem> items});

/// The "Open Orders" queue: every draft bill — saved from the billing page or
/// at a table — laid out like the Kitchen page: oldest first, each card listing
/// its dishes with their kitchen status. A card's "Open bill" button (or a
/// swipe right) opens it in the billing screen where a cashier/owner finalizes
/// it (or a server edits and re-saves it); tapping a ready dish marks it served.
class OpenDraftsScreen extends ConsumerStatefulWidget {
  /// When true, embedded inside the Orders tab's TabBarView — the parent
  /// [OrdersScreen] supplies the shared app bar, so render only the list body.
  final bool embedded;

  /// Search text from the Orders page header; empty shows every order.
  final String query;

  /// "Ready to serve" filter from the Orders header: only dishes the kitchen
  /// has finished that nobody has served yet.
  final bool readyOnly;

  const OpenDraftsScreen(
      {super.key,
      this.embedded = false,
      this.query = '',
      this.readyOnly = false});

  /// What the header search matches on: table, customer name, phone, bill no.
  static String _haystack(Bill b) => [
        b.tableNumber,
        b.customerName,
        b.customerPhone,
        b.billNumber,
      ].whereType<String>().join(' ').toLowerCase();

  /// Oldest order first (#1 is the one waiting longest), then the search and
  /// the ready filter. Queue numbers come from the full list so a card keeps
  /// its number while filtered.
  @visibleForTesting
  static List<OpenOrderTicket> tickets(
      List<Bill> drafts, String query, bool readyOnly) {
    final sorted = [...drafts]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final q = query.trim().toLowerCase();
    return [
      for (var i = 0; i < sorted.length; i++)
        if (q.isEmpty || _haystack(sorted[i]).contains(q))
          (
            bill: sorted[i],
            seq: i + 1,
            items: readyOnly
                ? sorted[i]
                    .items
                    .where((it) => it.kitchenStatus == 'ready')
                    .toList()
                : sorted[i].items,
          ),
    ].where((t) => !readyOnly || t.items.isNotEmpty).toList();
  }

  @override
  ConsumerState<OpenDraftsScreen> createState() => _OpenDraftsScreenState();
}

class _OpenDraftsScreenState extends ConsumerState<OpenDraftsScreen> {
  // Dish ids mid-update (tile disabled) and their optimistic status until the
  // refreshed list lands.
  final Set<String> _busy = {};
  final Map<String, String> _override = {};

  // Phone: one bill unfolded at a time — opening one folds the other.
  String? _openBillId;

  void _openDraft(Bill draft) {
    // Start from a clean cart; HomeScreen loads the draft's items itself.
    ref.read(cartProvider.notifier).clear();
    Navigator.push(
      context,
      MaterialPageRoute(
        // A table order opens as that table, so settling it frees the table.
        builder: (_) => HomeScreen(
          tableId: draft.tableId,
          tableNumber: draft.tableNumber,
          activeBillId: draft.id,
          activeBillFuture: Future.value(draft),
          openCart: true,
        ),
      ),
    ).then((_) {
      // Back from the billing screen — reconcile the queue and drop the
      // borrowed cart so a draft's items never leak into a fresh order.
      ref.read(cartProvider.notifier).clear();
      ref.read(openDraftsProvider.notifier).refreshSilently();
    });
  }

  bool get _retail =>
      ref.read(sessionProvider).valueOrNull?.businessType == 'retail';

  /// Serve a ready dish (or undo). Same rules and flow as the Kitchen page.
  /// Retail has no kitchen: a tap just ticks the item off, or unticks it.
  Future<void> _toggle(Map<String, dynamic> item) async {
    final next = _retail
        ? (item['kitchen_status'] == 'delivered' ? 'pending' : 'delivered')
        : KitchenScreen.nextStatus(ref.read(userRoleProvider), item);
    final id = item['id'] as String;
    if (next == null || _busy.contains(id)) return;
    setState(() {
      _busy.add(id);
      _override[id] = next;
    });
    try {
      await markKitchenItem(id, next);
      await ref.read(openDraftsProvider.notifier).refreshSilently();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(sanitizeUiErrorMessage(e)),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(id);
          _override.remove(id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final body = _buildBody(context);

    // Embedded in the Orders tab: parent supplies the app bar.
    if (widget.embedded) return body;

    return Scaffold(
      body: Column(children: [
        ShellAppBar(
          // Bottom-bar root tab: never show a back arrow.
          automaticallyImplyLeading: false,
          title: Text(l10n.openOrdersTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () => ref.invalidate(openDraftsProvider),
              tooltip: l10n.commonRefresh,
            ),
          ],
        ),
        Expanded(child: body),
      ]),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final draftsAsync = ref.watch(openDraftsProvider);

    return draftsAsync.when(
      loading: () => const OrdersListSkeleton(),
      error: (e, _) => AppErrorWidget(
        error: e,
        onRetry: () => ref.invalidate(openDraftsProvider),
      ),
      data: (drafts) {
        if (drafts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 48, color: AppColors.textDisabled),
                const SizedBox(height: AppSpacing.space16),
                Text(
                  l10n.openOrdersEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }
        final shown =
            OpenDraftsScreen.tickets(drafts, widget.query, widget.readyOnly);
        final role = ref.watch(userRoleProvider);
        // Wide screens keep every card open side by side (kitchen-display
        // style), each folding on its own.
        final phone = MediaQuery.sizeOf(context).width < 720;
        return RefreshIndicator(
          onRefresh: () => ref.read(openDraftsProvider.notifier).reload(),
          child: shown.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Text(
                      widget.readyOnly
                          ? l10n.kitchenNoReadyItems
                          : l10n.openOrdersNoMatches,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ])
              : kitchenMasonry(
                  itemCounts: [
                    for (final t in shown)
                      t.items.length.clamp(0, _DraftTicket._maxRows)
                  ],
                  cards: [
                    for (final t in shown)
                      _DraftTicket(
                        key: ValueKey(t.bill.id),
                        ticket: t,
                        role: role,
                        busy: _busy,
                        statusOverride: _override,
                        forceExpanded: widget.readyOnly,
                        catalog: ref.watch(itemsProvider).valueOrNull ?? const [],
                        retail: ref.watch(sessionProvider).valueOrNull
                                ?.businessType ==
                            'retail',
                        open: phone ? _openBillId == t.bill.id : null,
                        onOpenChanged: phone
                            ? (open) => setState(
                                () => _openBillId = open ? t.bill.id : null)
                            : null,
                        onOpen: () => _openDraft(t.bill),
                        onToggle: _toggle,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// An Open Orders card styled like the Kitchen page's: queue number, name,
/// age, total and ready count on top (tap = fold/unfold), the dishes
/// below (tap a ready one = served), then an "Open bill" button. Swipe right
/// to open the bill too. Folds to just the header — folded by default on a
/// phone, open on wider screens.
class _DraftTicket extends StatefulWidget {
  static const int _maxRows = 10; // dishes shown before the list scrolls

  final OpenOrderTicket ticket;
  final String role;
  final Set<String> busy;
  final Map<String, String> statusOverride;
  final bool forceExpanded;

  /// The item catalog, to show a line's packs ("1 Box + 2 Bottle").
  final List<Item> catalog;

  /// Retail shop: items get a plain tick box instead of kitchen statuses.
  final bool retail;

  /// When the list decides which card is unfolded (phone: one at a time),
  /// whether this one is, and how to ask for a change. Null = the card
  /// folds on its own.
  final bool? open;
  final ValueChanged<bool>? onOpenChanged;
  final VoidCallback onOpen;
  final Future<void> Function(Map<String, dynamic>) onToggle;

  const _DraftTicket({
    super.key,
    required this.ticket,
    required this.role,
    required this.busy,
    required this.statusOverride,
    required this.forceExpanded,
    this.catalog = const [],
    this.retail = false,
    this.open,
    this.onOpenChanged,
    required this.onOpen,
    required this.onToggle,
  });

  @override
  State<_DraftTicket> createState() => _DraftTicketState();
}

class _DraftTicketState extends State<_DraftTicket> {
  // Null until the user folds/unfolds it; until then it follows screen width.
  bool? _expanded;


  String _status(BillItem it) =>
      widget.statusOverride[it.id] ?? it.kitchenStatus ?? 'pending';

  /// "1 Box + 2 Bottle" for a line holding at least one full pack, else null.
  /// Read from the live catalog — bill lines carry no pack of their own.
  String? _packLabel(BillItem it) {
    final item = widget.catalog.where((i) => i.id == it.itemId).firstOrNull;
    if (item == null) return null;
    final variant = it.variantId == null
        ? null
        : item.variants.where((v) => v.id == it.variantId).firstOrNull;
    return cartPackLabel(
        context, CartEntry(item: item, variant: variant, quantity: it.quantity));
  }

  /// The line's short unit ("kg", "pcs"), from the live catalog like
  /// [_packLabel].
  String? _unit(BillItem it) {
    final unit = widget.catalog.where((i) => i.id == it.itemId).firstOrNull?.unit;
    return unit == null ? null : unitShort(unit);
  }

  /// The dish list hit its top/bottom under a finger: keep the drag going on
  /// the page instead of stopping dead. (A mouse wheel already passes to the
  /// page by itself once the list can't move.)
  /// ponytail: the page follows the finger but gets no fling on release.
  bool _chainToPage(OverscrollNotification n) {
    if (n.depth != 0 || n.dragDetails == null) return false;
    // This card's context sits above the dish list, so this is the page.
    final page = Scrollable.maybeOf(context)?.position;
    if (page == null) return false;
    page.jumpTo((page.pixels + n.overscroll)
        .clamp(page.minScrollExtent, page.maxScrollExtent));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = widget.ticket.bill;
    final items = widget.ticket.items;
    final expanded = widget.forceExpanded ||
        (widget.open ?? _expanded ?? MediaQuery.sizeOf(context).width >= 720);
    final readyCount = draft.items.where((it) => _status(it) == 'ready').length;
    final allReady = draft.items.isNotEmpty &&
        draft.items
            .every((it) => const ['ready', 'delivered'].contains(_status(it)));

    final hasName =
        draft.customerName != null && draft.customerName!.trim().isNotEmpty;
    final title = draft.tableNumber != null
        ? l10n.tablesTableLabel(draft.tableNumber!) +
            (hasName ? ' · ${draft.customerName!.trim()}' : '')
        : hasName
            ? draft.customerName!.trim()
            : l10n.openOrdersBillNumber(draft.billNumber);
    final timeLabel =
        orderTimeLabel(context, draft.createdAt.toUtc().toIso8601String());

    final card = AppCard(
      padding: EdgeInsets.zero,
      // Never tinted green when everything is done — the ticks say it.
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: a tap anywhere folds/unfolds the dishes. Opening the bill
          // is the button under the dishes, or a swipe right on the card.
          // Under the ready filter cards stay open, so the tap does nothing.
          InkWell(
            onTap: widget.forceExpanded
                ? null
                : widget.onOpenChanged != null
                    ? () => widget.onOpenChanged!(!expanded)
                    : () => setState(() => _expanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space8, 6, AppSpacing.space8, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: allReady
                                    ? AppColors.success
                                    : AppColors.primary,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.small),
                              ),
                              child: Text(
                                '${widget.ticket.seq}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          // Indented past the queue chip (22 + 6) so the total
                          // lines up under the title.
                          padding: const EdgeInsets.only(left: 28),
                          child: Row(
                            children: [
                              Text(
                                '₹${(draft.total - draft.discountAmount).toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.openOrdersItemCount(draft.items
                                      .fold<double>(
                                          0, (s, it) => s + it.quantity)
                                      .toInt()),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Money already taken online, and the reference to
                        // check it against. Shown here rather than only in the
                        // online queue because THIS is the screen someone opens
                        // to settle the bill or hand a delivery over — and a
                        // prepaid order that looks unpaid gets charged in full
                        // a second time.
                        if (draft.hasOnlinePrepayment) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const SizedBox(width: 28),
                              const Icon(Icons.verified_outlined,
                                  size: 13, color: AppColors.success),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Paid online ₹${draft.onlinePaidAmount.toStringAsFixed(2)}'
                                  '${draft.onlinePaymentTxnId != null && draft.onlinePaymentTxnId!.isNotEmpty ? ' · ${draft.onlinePaymentTxnId}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  // Time + chevron on top, the ready badge right-aligned under
                  // them at the card's edge.
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (timeLabel.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Icon(Icons.schedule,
                                    size: 11, color: AppColors.textSecondary),
                              ),
                              const SizedBox(width: 2),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  timeLabel,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                            if (!widget.forceExpanded) ...[
                              const SizedBox(width: 4),
                              // Turns over in step with the dishes sliding.
                              AnimatedRotation(
                                turns: expanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeInOutCubic,
                                child: const Icon(Icons.expand_more, size: 20),
                              ),
                            ],
                          ],
                        ),
                        if (readyCount > 0) ...[
                          const SizedBox(height: 2),
                          _ReadyBadge(count: readyCount),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Slides the dishes (and the Open bill button) open/closed instead
          // of snapping; clips while it animates.
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A long order stops growing at ~10 dishes and scrolls
                      // inside the card; the Open bill button stays in view.
                      // ponytail: ~35px per KitchenItemTile row, so wrapped
                      // names show slightly fewer than 10.
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxHeight: _DraftTicket._maxRows * 35.0),
                        child: NotificationListener<OverscrollNotification>(
                          onNotification: _chainToPage,
                          child: Scrollbar(
                          child: SingleChildScrollView(
                            // Clamping, so a finger drag at either end reports
                            // overscroll (handed to the page) instead of
                            // bouncing.
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (int i = 0; i < items.length; i++) ...[
                                  const Divider(height: 1),
                                  if (widget.retail)
                                    _TickTile(
                                      key: ValueKey(items[i].id),
                                      item: items[i],
                                      packLabel: _packLabel(items[i]),
                                      unit: _unit(items[i]),
                                      ticked:
                                          _status(items[i]) == 'delivered',
                                      busy: widget.busy.contains(items[i].id),
                                      onTap: () => widget.onToggle({
                                        'id': items[i].id,
                                        'kitchen_status': _status(items[i]),
                                      }),
                                    )
                                  else
                                  KitchenItemTile(
                                    key: ValueKey(items[i].id),
                                    item: {
                                      'id': items[i].id,
                                      'item_name': [
                                        items[i].itemName,
                                        _packLabel(items[i]),
                                      ].nonNulls.join('  ·  '),
                                      'quantity': items[i].quantity,
                                      'kitchen_status': _status(items[i]),
                                    },
                                    role: widget.role,
                                    busy: widget.busy,
                                    onToggle: widget.onToggle,
                                    tintRow: false,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.space8),
                        child: OutlinedButton.icon(
                          onPressed: widget.onOpen,
                          icon:
                              const Icon(Icons.receipt_long_outlined, size: 18),
                          label: Text(l10n.openOrdersOpenBill),
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );

    // Short swipe right (folded or open) = open the bill — same feel as the
    // billing page's swipe-to-add: the card travels at most [_maxDrag], fires
    // past [_threshold], and springs back.
    final armed = _dragDx > _threshold;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Stack(
        children: [
          // Revealed hint behind the card, growing with the drag.
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: _dragDx.clamp(0.0, _maxDrag),
                color: AppColors.primary.withValues(alpha: armed ? 0.22 : 0.10),
                alignment: Alignment.center,
                child: _dragDx > 8
                    ? Icon(Icons.receipt_long_outlined,
                        size: 20,
                        color: AppColors.primary.withValues(
                            alpha: ((_dragDx - 8) / (_threshold - 8))
                                .clamp(0.0, 1.0)))
                    : null,
              ),
            ),
          ),
          GestureDetector(
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: (d) {
              final next = (_dragDx + d.delta.dx).clamp(0.0, _maxDrag);
              // A tick as it crosses the trigger point, so the hand knows
              // letting go now opens the bill.
              if ((next > _threshold) != (_dragDx > _threshold)) {
                HapticFeedback.selectionClick();
              }
              setState(() => _dragDx = next);
            },
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _endDrag,
            child: AnimatedContainer(
              // Follows the finger 1:1; eases back on release.
              duration:
                  _dragging ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_dragDx, 0, 0),
              child: card,
            ),
          ),
        ],
      ),
    );
  }

  static const double _threshold = 56.0; // px to trigger, as swipe-to-add
  static const double _maxDrag = 72.0;
  double _dragDx = 0;
  bool _dragging = false;

  void _endDrag() {
    final fire = _dragDx > _threshold;
    setState(() {
      _dragging = false;
      _dragDx = 0;
    });
    if (fire) {
      HapticFeedback.lightImpact();
      widget.onOpen();
    }
  }
}

/// Green "🛎 N" pill — dishes on this order ready to be taken out.
class _ReadyBadge extends StatelessWidget {
  final int count;
  const _ReadyBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.room_service, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// A retail order line with a plain tick box — what the tick means is up to
/// the shop (packed, handed over, checked…), so it carries no label.
class _TickTile extends StatelessWidget {
  final BillItem item;
  final String? packLabel;
  final String? unit;
  final bool ticked;
  final bool busy;
  final VoidCallback onTap;

  const _TickTile({
    super.key,
    required this.item,
    this.packLabel,
    this.unit,
    required this.ticked,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space8, vertical: 6),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: ticked
                  ? Container(
                      key: const ValueKey('on'),
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                          color: AppColors.success, shape: BoxShape.circle),
                      child: const Icon(Icons.check,
                          size: 14, color: Colors.white),
                    )
                  : const Icon(Icons.radio_button_unchecked,
                      key: ValueKey('off'),
                      size: 20,
                      color: AppColors.textSecondary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.itemName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      ticked ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (packLabel != null) ...[
              Text(
                packLabel!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              ['× ${formatQty(item.quantity)}', unit].nonNulls.join(' '),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
