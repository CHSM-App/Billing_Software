import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/floating_bar_physics.dart';
import '../widgets/shell_app_bar.dart';
import 'tables_screen.dart';
import 'open_drafts_screen.dart';
import 'credit_screen.dart';
import 'kitchen_screen.dart';
import 'online_orders_screen.dart';

/// The "Orders" bottom-nav tab: one screen hosting everything with work still
/// outstanding — **Tables** (the floor plan), **Open Orders** (table-less draft
/// bills), **Credit** (udhaari), and **Online** (orders from the store link).
///
/// The embedded child screens render only their bodies; this screen owns the
/// shared app bar, the TabBar, the refresh action, and the "add table" FAB
/// (shown only on the Tables sub-tab, for owners).
///
/// Order: Open Orders, Tables (table restaurants only), Online (only while the
/// online store is enabled), Credit.
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

  // Header search for Open Orders — same expanding field as the Billing page.
  bool _searchExpanded = false;
  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchAnim;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  // "Ready to serve" filter on Open Orders — same toggle as the Kitchen page.
  bool _readyOnly = false;

  @override
  void initState() {
    super.initState();
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _searchAnim =
        CurvedAnimation(parent: _searchAnimCtrl, curve: Curves.easeInOut);
    _searchController.addListener(() {
      setState(() {});
      // The search filters Open Orders, so typing brings that list forward.
      final i = _tabs.indexOf(_OrdersTab.openOrders);
      if (_searchController.text.isNotEmpty &&
          i >= 0 &&
          _tabController!.index != i) {
        _tabController!.animateTo(i);
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _header.dispose();
    _searchAnimCtrl.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Phone layout: the title row folds away with whichever sub-tab's list is
  /// scrolled, while the sub-tab row stays pinned — see [FoldingHeader].
  /// Pinned open while the search field (which lives in it) is in use.
  late final FoldingHeader _header = FoldingHeader(
    vsync: this,
    extent: () => 50, // ShellAppBar's toolbar row
    canFold: () => !_searchExpanded && MediaQuery.sizeOf(context).width < 720,
  );

  void _toggleSearch() {
    setState(() => _searchExpanded = !_searchExpanded);
    if (_searchExpanded) {
      _header.show();
      _searchAnimCtrl.forward();
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchAnimCtrl.reverse();
      _searchController.clear();
      _searchFocus.unfocus();
    }
  }

  /// The expanding search field + its search/close toggle, mirroring the
  /// Billing page's app bar. Sized against the bar's width (not the window's)
  /// so it never runs under the navigation rail on desktop; leaves room for
  /// the toggle and the refresh button that share the bar.
  Widget _buildSearch(AppLocalizations l10n, double barWidth) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _searchAnim,
          builder: (context, _) {
            final maxWidth = (barWidth - 128).clamp(0.0, barWidth);
            return SizedBox(
              width: _searchAnim.value * maxWidth,
              height: 40,
              child: Opacity(
                opacity: _searchAnim.value,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: l10n.openOrdersSearchHint,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _searchExpanded
                ? const Icon(Icons.close, key: ValueKey('close'), size: 20)
                : const Icon(Icons.search, key: ValueKey('search'), size: 20),
          ),
          color: AppColors.textSecondary,
          tooltip: l10n.openOrdersSearchHint,
          onPressed: _toggleSearch,
        ),
      ],
    );
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
      _header.show(); // the next sub-tab's list has its own scroll position
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

  /// Tab name followed by a red count badge (same look as the bottom bar),
  /// hidden at 0. Credit carries no count. Tables counts occupied tables;
  /// Online counts orders awaiting a decision.
  Widget _tabLabel(AppLocalizations l10n, _OrdersTab tab,
      {required int tables, required int open, required int online}) {
    Widget withCount(String label, int n) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (n > 0) ...[
              const SizedBox(width: 6),
              Badge(backgroundColor: Colors.red, label: Text('$n')),
            ],
          ],
        );
    switch (tab) {
      case _OrdersTab.tables:
        return withCount(l10n.ordersTabTables, tables);
      case _OrdersTab.openOrders:
        return withCount(l10n.ordersTabOpenOrders, open);
      case _OrdersTab.credit:
        return Text(l10n.ordersTabCredit);
      case _OrdersTab.online:
        return withCount(l10n.onlineOrdersTab, online);
    }
  }

  Widget _tabView(_OrdersTab tab) {
    switch (tab) {
      case _OrdersTab.tables:
        return TablesScreen(key: _tablesKey, embedded: true);
      case _OrdersTab.openOrders:
        return OpenDraftsScreen(
            embedded: true,
            query: _searchController.text,
            readyOnly: _readyOnly);
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
    // Watched here in build(), not inside the LayoutBuilder below, so a count
    // change always rebuilds the tab labels.
    // Tables only for table restaurants — watching it elsewhere would fetch the
    // floor plan (and every occupied table's bill) just for an unseen count.
    final int occupiedTables = widget.showTables
        ? (ref.watch(tablesProvider).valueOrNull ?? const [])
            .where((t) => t.activeBillId != null)
            .length
        : 0;
    final int openCount = ref.watch(openDraftsProvider).valueOrNull?.length ?? 0;
    final int onlineCount = ref.watch(pendingOnlineOrderCountProvider);

    final storeEnabled =
        ref.watch(sessionProvider).valueOrNull?.storeEnabled ?? false;
    final businessType = ref.watch(sessionProvider).valueOrNull?.businessType;
    final isRestaurant = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
    final readyCount = ref.watch(openOrdersReadyCountProvider);

    _syncTabs([
      // Always shown, even when empty, so staff always know where to look —
      // a Credit tab that came and went with the dues read as a missing
      // feature. An empty one says no one owes money.
      _OrdersTab.openOrders,
      if (widget.showTables) _OrdersTab.tables,
      // Online only while the shop runs its online store.
      if (storeEnabled) _OrdersTab.online,
      _OrdersTab.credit,
    ]);

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
    // Folded on a phone, then widened (where it never folds): open it back up.
    if (MediaQuery.sizeOf(context).width >= 720 && _header.bar.value < 1) {
      _header.bar.value = 1;
    }

    return Scaffold(
      body: Column(
        children: [
          // The status-bar band stays put; the title row folds away beneath
          // it while the sub-tab row (+ divider) always stays.
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
          LayoutBuilder(builder: (context, bar) => ShellAppBar(
            // Bottom-bar root tab: never show a back arrow.
            automaticallyImplyLeading: false,
            title: AnimatedOpacity(
              opacity: _searchExpanded ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Text(l10n.navOrders),
            ),
            actions: [
              _buildSearch(l10n, bar.maxWidth),
              if (isRestaurant && !_searchExpanded)
                // Back only once the search box has finished shrinking: shown
                // the moment ✕ is tapped, it shared the row with a still-wide
                // box and overflowed for the length of the animation.
                AnimatedBuilder(
                  animation: _searchAnimCtrl,
                  builder: (context, child) => _searchAnimCtrl.isDismissed
                      ? child!
                      : const SizedBox.shrink(),
                  child: ReadyToServeToggle(
                    count: readyCount,
                    selected: _readyOnly,
                    tooltip: l10n.kitchenReadyOnly,
                    onTap: () {
                      setState(() => _readyOnly = !_readyOnly);
                      // The filter lives on Open Orders — bring it forward.
                      final i = _tabs.indexOf(_OrdersTab.openOrders);
                      if (_readyOnly && _tabController!.index != i) {
                        _tabController!.animateTo(i);
                      }
                    },
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_outlined),
                onPressed: _refresh,
                tooltip: l10n.commonRefresh,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              // Always scrollable: with counts ("Open Orders (8)") the labels
              // don't fit fixed-width tabs on a phone and the count gets cut off.
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: [
                for (final t in _tabs)
                  Tab(
                      child: _tabLabel(l10n, t,
                          tables: occupiedTables,
                          open: openCount,
                          online: onlineCount))
              ],
            ),
          )),
            ),
          ),
          Expanded(
            // The sub-tab screens build their own lists; this hands them the
            // folding physics and listens to their scrolls.
            child: _header.wrap(
              context,
              TabBarView(
                controller: _tabController,
                // Switch tabs only by tapping the TabBar — no horizontal swipe.
                // A swipe would also fight the Tables canvas's pan gesture.
                physics: const NeverScrollableScrollPhysics(),
                children: [for (final t in _tabs) _tabView(t)],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: (onTablesTab && userRole == 'owner')
          // Lifted clear of the floating glass nav bar.
          ? Padding(
              padding:
                  EdgeInsets.only(bottom: AppBottomNavBar.fabLift(context)),
              child: FloatingActionButton.extended(
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
            ),
          )
          : null,
    );
  }
}
