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

/// The "Orders" bottom-nav tab: a single screen hosting two sub-tabs —
/// **Tables** (the floor plan) and **Open Orders** (table-less draft bills).
///
/// Replaces what used to be two separate bottom-bar entries. The embedded
/// child screens render only their bodies; this screen owns the shared app
/// bar, the TabBar, the refresh action, and the "add table" FAB (shown only
/// on the Tables sub-tab, for owners).
class OrdersScreen extends ConsumerStatefulWidget {
  /// Whether to include the Tables (floor plan) sub-tab. True for table
  /// restaurants; false for retail / no-table businesses, which get the same
  /// Orders page with just Open Orders + Credit.
  final bool showTables;

  const OrdersScreen({super.key, this.showTables = true});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

/// Identifies a sub-tab regardless of how many are shown, so refresh and the
/// FAB stay correct as the tab set changes with [OrdersScreen.showTables].
enum _OrdersTab { tables, openOrders, credit }

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<_OrdersTab> _tabs;

  // Lets the shared FAB drive TablesScreen's "add table" flow.
  final GlobalKey<State<TablesScreen>> _tablesKey =
      GlobalKey<State<TablesScreen>>();

  @override
  void initState() {
    super.initState();
    _tabs = [
      if (widget.showTables) _OrdersTab.tables,
      _OrdersTab.openOrders,
      _OrdersTab.credit,
    ];
    _tabController = TabController(length: _tabs.length, vsync: this);
    // Rebuild on tab change so the FAB shows/hides with the active sub-tab.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    // Refresh whichever queue the active sub-tab shows.
    switch (_tabs[_tabController.index]) {
      case _OrdersTab.tables:
        ref.invalidate(tablesProvider);
        break;
      case _OrdersTab.openOrders:
        ref.invalidate(openDraftsProvider);
        break;
      case _OrdersTab.credit:
        ref.invalidate(creditCustomersProvider);
        break;
    }
  }

  String _tabLabel(AppLocalizations l10n, _OrdersTab tab) {
    switch (tab) {
      case _OrdersTab.tables:
        return l10n.ordersTabTables;
      case _OrdersTab.openOrders:
        return l10n.ordersTabOpenOrders;
      case _OrdersTab.credit:
        return l10n.ordersTabCredit;
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final userRole = ref.watch(userRoleProvider);
    final onTablesTab = _tabs[_tabController.index] == _OrdersTab.tables;

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
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: [for (final t in _tabs) Tab(text: _tabLabel(l10n, t))],
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
