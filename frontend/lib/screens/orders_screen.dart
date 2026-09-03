import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shell_app_bar.dart';
import 'tables_screen.dart';
import 'open_drafts_screen.dart';
import 'credit_screen.dart';
import 'online_orders_screen.dart';

/// The "Orders" bottom-nav tab: one screen hosting everything with work still
/// outstanding — **Tables** (the floor plan), **Open Orders** (table-less draft
/// bills), **Credit** (udhaari), and **Online** (orders from the store link).
///
/// The embedded child screens render only their bodies; this screen owns the
/// shared app bar, the TabBar, the refresh action, and the "add table" FAB
/// (shown only on the Tables sub-tab, for owners).
///
/// Tab set is CONTENT-DRIVEN, not fixed: a queue with nothing in it has no tab.
/// Tables is the exception — a table restaurant's floor plan is always relevant
/// even when every table is empty.
class OrdersScreen extends ConsumerStatefulWidget {
  /// Whether to include the Tables (floor plan) sub-tab. True for table
  /// restaurants; false for retail / no-table businesses.
  final bool showTables;

  const OrdersScreen({super.key, this.showTables = true});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

/// Identifies a sub-tab regardless of how many are shown, so refresh and the
/// FAB stay correct as the tab set changes with content.
enum _OrdersTab { tables, openOrders, credit, online }

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  List<_OrdersTab> _tabs = const [];

  // Lets the shared FAB drive TablesScreen's "add table" flow.
  final GlobalKey<State<TablesScreen>> _tablesKey =
      GlobalKey<State<TablesScreen>>();

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  /// Rebuild the controller only when the tab SET actually changes, keeping the
  /// user on the same sub-tab where it survives.
  ///
  /// A TabController's length is fixed at construction, so a queue emptying (or
  /// a new online order arriving) means a new controller. Recreating it on every
  /// build would reset the selection on each rebuild, which is why this is
  /// guarded on the list contents rather than called unconditionally.
  void _syncTabs(List<_OrdersTab> next) {
    if (_tabController != null && _listEquals(_tabs, next)) return;

    final previous =
        _tabController == null ? null : _tabs.elementAtOrNull(_tabController!.index);
    _tabController?.dispose();
    _tabs = next;
    final restored = previous == null ? -1 : next.indexOf(previous);
    _tabController = TabController(
      length: next.length,
      // The tab they were on may have just disappeared (they settled the last
      // draft); fall back to the first rather than to a stale index.
      initialIndex: restored >= 0 ? restored : 0,
      vsync: this,
    );
    // Rebuild on tab change so the FAB shows/hides with the active sub-tab.
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) return;
      setState(() {});
    });
  }

  static bool _listEquals(List<_OrdersTab> a, List<_OrdersTab> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _refresh() {
    // Refresh whichever queue the active sub-tab shows.
    switch (_tabs[_tabController!.index]) {
      case _OrdersTab.tables:
        ref.invalidate(tablesProvider);
        break;
      case _OrdersTab.openOrders:
        ref.invalidate(openDraftsProvider);
        break;
      case _OrdersTab.credit:
        ref.invalidate(creditCustomersProvider);
        break;
      case _OrdersTab.online:
        ref.invalidate(onlineOrdersProvider);
        break;
    }
  }

  String _tabLabel(AppLocalizations l10n, _OrdersTab tab, int pendingOnline) {
    switch (tab) {
      case _OrdersTab.tables:
        return l10n.ordersTabTables;
      case _OrdersTab.openOrders:
        return l10n.ordersTabOpenOrders;
      case _OrdersTab.credit:
        return l10n.ordersTabCredit;
      case _OrdersTab.online:
        // The count is what makes "something needs deciding" visible without
        // opening the tab. Dropped once everything left is merely in progress.
        return pendingOnline > 0
            ? '${l10n.onlineOrdersTab} ($pendingOnline)'
            : l10n.onlineOrdersTab;
    }
  }

  Widget _tabView(_OrdersTab tab) {
    switch (tab) {
      case _OrdersTab.tables:
        return TablesScreen(key: _tablesKey, embedded: true);
      case _OrdersTab.openOrders:
        return const OpenDraftsScreen(embedded: true);
      case _OrdersTab.credit:
        return const CreditScreen(embedded: true);
      case _OrdersTab.online:
        return const OnlineOrdersScreen(embedded: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final userRole = ref.watch(userRoleProvider);
    final storeEnabled =
        ref.watch(sessionProvider).valueOrNull?.storeEnabled ?? false;
    final pendingOnline = ref.watch(pendingOnlineOrderCountProvider);

    _syncTabs([
      if (widget.showTables) _OrdersTab.tables,
      if (ref.watch(hasOpenDraftsProvider)) _OrdersTab.openOrders,
      if (ref.watch(hasCreditProvider)) _OrdersTab.credit,
      if (storeEnabled && ref.watch(hasOpenOnlineOrdersProvider))
        _OrdersTab.online,
    ]);

    // Every queue drained at once. The shell normally hides this whole nav item
    // in that case, but the two decisions are made a frame apart — so render
    // something calm instead of asserting inside TabController(length: 0).
    if (_tabs.isEmpty) {
      return Scaffold(
        body: Column(children: [
          ShellAppBar(
            automaticallyImplyLeading: false,
            title: Text(l10n.navOrders),
          ),
          const Expanded(child: SizedBox.shrink()),
        ]),
      );
    }

    // A notification tap asked for the Online queue. Handled after this frame
    // so the tab set above is already built, and cleared either way so a
    // request that cannot be honoured does not linger.
    if (ref.watch(openOnlineOrdersRequestProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(openOnlineOrdersRequestProvider.notifier).state = false;
        final i = _tabs.indexOf(_OrdersTab.online);
        if (i >= 0 && _tabController!.index != i) _tabController!.animateTo(i);
      });
    }

    final onTablesTab = _tabs[_tabController!.index] == _OrdersTab.tables;

    return Scaffold(
      body: Column(
        children: [
          ShellAppBar(
            // Bottom-bar root tab: never show a back arrow.
            automaticallyImplyLeading: false,
            title: Text(l10n.navOrders),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_outlined),
                onPressed: _refresh,
                tooltip: l10n.commonRefresh,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              // With four possible tabs the labels no longer fit a phone width
              // evenly; scrolling keeps them readable instead of squeezing.
              isScrollable: _tabs.length > 3,
              tabAlignment: _tabs.length > 3 ? TabAlignment.start : null,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: [
                for (final t in _tabs)
                  Tab(text: _tabLabel(l10n, t, pendingOnline))
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              // Switch tabs only by tapping the TabBar — no horizontal swipe.
              // A swipe would also fight the Tables canvas's pan gesture.
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final t in _tabs) _tabView(t)],
            ),
          ),
        ],
      ),
      floatingActionButton: (onTablesTab && userRole == 'owner')
          ? FloatingActionButton.extended(
              heroTag: 'addTableFab',
              onPressed: () {
                final state = _tablesKey.currentState;
                if (state is TablesScreenApi) {
                  (state as TablesScreenApi).addTable();
                }
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.tablesAddTable),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}
