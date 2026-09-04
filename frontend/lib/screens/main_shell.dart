import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../api.dart' show setConnectivityNotifier;
import '../providers.dart';
import '../theme/app_theme.dart';
import '../services/sync_service.dart';
import '../services/license_service.dart';
import '../services/realtime_service.dart';
import '../services/notification_service.dart';
import '../widgets/nav_item.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/connectivity_bar.dart';
import '../features/splash/splash_loading_view.dart';
import 'home_screen.dart';
import 'items_screen.dart';
import 'orders_screen.dart';
import 'kitchen_screen.dart';
import 'settings_screen.dart';
import 'license_screen.dart';
import 'login_screen.dart';
import '../providers/open_drafts_provider.dart';

class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;
  final LicenseStatus? licenseStatus;
  const MainShell({super.key, this.initialIndex = 0, this.licenseStatus});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _index = 0;

  /// The nav items from the last build — see _openOnlineOrders.
  List<NavItem> _navItems = const [];
  late final AnimationController _railAnimController;
  late final Animation<double> _railFadeAnim;
  StreamSubscription<String>? _realtimeSub;
  bool _deviceCheckInFlight = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    // Observe lifecycle so we can re-check the device-access policy when the app
    // returns to the foreground — enforcing a restriction the admin applied
    // while the app was backgrounded, without needing a full restart.
    WidgetsBinding.instance.addObserver(this);
    _railAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _railFadeAnim = CurvedAnimation(
        parent: _railAnimController, curve: Curves.easeOut);
    _railAnimController.forward();

    // Route real-time WebSocket events to the relevant providers so every
    // screen updates live across devices, without any notifications.
    _realtimeSub = RealtimeService.instance.events.listen(_onRealtimeEvent);

    // A second path to the same refresh for online orders: the push arrives even
    // when the WebSocket is down (backgrounded app, dropped socket), which is
    // exactly when a shop is most likely to miss an order.
    NotificationService.instance.onlineOrderPing.addListener(_onOnlineOrderPing);
    NotificationService.instance.onlineOrderTap.addListener(_onOnlineOrderTapped);

    // Ensure the socket is live for this session. The app bootstrap starts it on
    // cold launch, but a re-login (login screen → new shell) mounts here without
    // re-running bootstrap; start() is idempotent and clears the disposed latch
    // set by a prior logout, so realtime works on every session.
    RealtimeService.instance.start();

    // Wire the connectivity notifier into api.dart for THIS session. The cold-
    // start bootstrap wires it, but a fresh login (login screen → new shell) does
    // not — without this, api.dart's markOffline/markOnline are no-ops, so the
    // "No connection" badge never shows, the app can't tell it's offline (so
    // billing tries online and fails), and it never detects reconnect. Re-wiring
    // here guarantees it's connected on every session.
    setConnectivityNotifier(ref.read(connectivityProvider.notifier));

    // Fresh login mounts a new shell. The open-drafts provider may still hold
    // stale/empty state from a previous session (it isn't autoDispose), so the
    // "Open Orders" tab would stay hidden until the next drafts event. Force a
    // fresh fetch after the first frame so the tab appears right away when
    // table-less drafts already exist on the server.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final role = ref.read(sessionProvider).valueOrNull?.userRole;
      if (role != null && role != 'kitchen') {
        ref.read(openDraftsProvider.notifier).refreshSilently();
        // Same reasoning for the Credit tab: fetch once so it appears right
        // away when credit is already outstanding on the server.
        ref.read(creditCustomersProvider.notifier).refreshSilently();
        // And the online-order queue — but only for a shop that runs a store
        // and a role that can decide one, so nobody else pays for the request.
        final session = ref.read(sessionProvider).valueOrNull;
        if (session != null &&
            session.storeEnabled &&
            _canDecideOnlineOrders(role)) {
          ref.read(onlineOrdersProvider.notifier).refreshSilently();
          // A COLD launch from tapping the notification: the tap was handled
          // during startup, before this shell existed to hear it.
          if (NotificationService.instance.consumeOnlineOrderTap()) {
            _openOnlineOrders();
          }
        }
      }
    });
  }

  void _onRealtimeEvent(String type) {
    if (!mounted) return;
    switch (type) {
      case 'kitchen':
        // The Kitchen screen listens to this ping and reloads its queue.
        NotificationService.instance.pingKitchen();
        break;
      case 'tables':
        ref.read(tablesProvider.notifier).refreshSilently();
        break;
      case 'drafts':
        ref.read(openDraftsProvider.notifier).refreshSilently();
        // Settling the draft an online order became is what finishes that
        // order, so the Online tab has to re-evaluate on the same signal —
        // otherwise it lingers after the bill it was waiting on is paid.
        ref.read(onlineOrdersProvider.notifier).refreshSilently();
        break;
      case 'credit':
        ref.read(creditCustomersProvider.notifier).refreshSilently();
        break;
      case 'store':
        // A customer placed an order, or another device accepted/rejected one.
        ref.read(onlineOrdersProvider.notifier).refreshSilently();
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckDeviceAccess();
    }
  }

  /// Re-evaluate the device-access policy when the app resumes. Fetches the
  /// latest license (which refreshes the cached device policy) and, if this
  /// device is now forbidden, routes to the block screen. Network-free fallback:
  /// if the fetch can't reach the server, the offline evaluation still enforces
  /// the LAST KNOWN policy from cache. Guarded so overlapping resumes don't
  /// stack navigations.
  Future<void> _recheckDeviceAccess() async {
    if (_deviceCheckInFlight) return;
    _deviceCheckInFlight = true;
    try {
      final status = await LicenseService.instance.check(isOnline: true);
      if (!mounted) return;
      if (status.state == LicenseState.blockedDevice) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => LicenseBlockedScreen(
              reason: LicenseState.blockedDevice,
              onUnblocked: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
            ),
          ),
          (_) => false,
        );
      }
    } catch (_) {
      // Never let a resume-time check crash the app; the next launch re-checks.
    } finally {
      _deviceCheckInFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSub?.cancel();
    NotificationService.instance.onlineOrderPing
        .removeListener(_onOnlineOrderPing);
    NotificationService.instance.onlineOrderTap
        .removeListener(_onOnlineOrderTapped);
    _railAnimController.dispose();
    super.dispose();
  }

  void _onOnlineOrderPing() {
    if (!mounted) return;
    ref.read(onlineOrdersProvider.notifier).refreshSilently();
  }

  void _onOnlineOrderTapped() {
    if (!mounted) return;
    NotificationService.instance.consumeOnlineOrderTap();
    _openOnlineOrders();
  }

  /// Bring the Online orders queue to the front.
  ///
  /// The queue is loaded FIRST: the Orders nav item and its Online sub-tab both
  /// exist only while an order is open, so jumping before the fetch lands would
  /// aim at a tab that is not there yet. The post-frame hop is what lets the
  /// rebuilt nav list be read back.
  Future<void> _openOnlineOrders() async {
    await ref.read(onlineOrdersProvider.notifier).refreshSilently();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = _navItems.indexWhere((n) => n.screen is OrdersScreen);
      // No Orders tab means the order was already handled on another device.
      // Drop the request rather than leave it primed to fire later.
      if (i < 0) return;
      ref.read(openOnlineOrdersRequestProvider.notifier).state = true;
      if (i != _index) setState(() => _index = i);
    });
  }

  /// Mirrors the server's guard in routes/online_orders.js: only an owner or a
  /// cashier may accept or reject. Showing the tab to anyone else would offer
  /// buttons that always 403.
  static bool _canDecideOnlineOrders(String role) =>
      role == 'owner' || role == 'cashier';

  List<NavItem> _buildNavItems(String userRole, String businessType,
      bool hasOpenDrafts, bool hasCredit, bool hasOnlineOrders) {
    final l10n = context.l10n;
    final isRestaurant = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';

    // Kitchen chef only sees the Kitchen Display and Settings (for logout /
    // language). No billing, items, reports or history.
    if (userRole == 'kitchen') {
      return [
        NavItem(Icons.restaurant_menu_outlined, Icons.restaurant_menu,
            l10n.navKitchen, const KitchenScreen()),
        NavItem(Icons.person_outline, Icons.person, l10n.navProfile,
            const SettingsScreen()),
      ];
    }

    return [
      NavItem(Icons.receipt_long_outlined, Icons.receipt_long, l10n.navBilling,
          const HomeScreen()),
      if (userRole == 'owner')
        NavItem(Icons.inventory_2_outlined, Icons.inventory_2, l10n.navItems,
            const ItemsScreen()),
      // Orders: one page hosting Tables (table restaurants only), Open Orders,
      // Credit and Online as sub-tabs — each shown only while it has something
      // in it (OrdersScreen decides that). Table restaurants always show the
      // page (Tables is always relevant). Retail / no-table businesses get the
      // SAME page, minus the Tables sub-tab, and only while at least one queue
      // has work in it, so it never sits empty.
      if (businessType == 'restaurant_with_tables')
        NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
            l10n.navOrders, const OrdersScreen(showTables: true))
      else if (hasOpenDrafts || hasCredit || hasOnlineOrders)
        NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
            l10n.navOrders, const OrdersScreen(showTables: false)),
      // Waiters and owners at a restaurant can watch the kitchen queue.
      if (isRestaurant)
        NavItem(Icons.restaurant_menu_outlined, Icons.restaurant_menu,
            l10n.navKitchen, const KitchenScreen()),
      // History, Reports and Expenses moved into the Profile screen.
      NavItem(Icons.person_outline, Icons.person, l10n.navProfile,
          const SettingsScreen()),
    ];
  }

  void _onNav(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider);

    return sessionAsync.when(
      // Continue the branded splash visual instead of a bare spinner. In
      // practice sessionProvider is already resolved by the _AppEntry bootstrap
      // before MainShell mounts, so this rarely shows — but when it does it
      // stays visually continuous with the splash.
      loading: () => const SplashLoadingView(),
      error: (_, __) => const SplashLoadingView(),
      data: (session) {
        ref.listen<bool>(connectivityProvider, (prev, next) {
          if (prev == false && next == true) {
            SyncService.instance.syncAll().then((_) {
              ref.invalidate(itemsProvider);
              ref.invalidate(categoriesProvider);
              ref.invalidate(categoryTreeProvider);
              ref.invalidate(tablesProvider);
              // Queued offline drafts were just pushed; refresh Open Orders so
              // their local copies are replaced by the authoritative server ones.
              ref.invalidate(openDraftsProvider);
              // History: the just-synced offline bills are now on the server and
              // their local INV-<tag>-#### rows are gone, so re-fetch to show the
              // authoritative copies.
              ref.invalidate(billsProvider);
              ref.invalidate(reportProvider);
            });
          }
        });

        // Kitchen staff never see billing/orders, so don't even query drafts.
        final hasOpenDrafts = session.userRole != 'kitchen' &&
            ref.watch(hasOpenDraftsProvider);
        final hasCredit =
            session.userRole != 'kitchen' && ref.watch(hasCreditProvider);
        // Only a role that can decide an order needs the queue — and only when
        // the shop actually runs a store. Deliberately NOT gated on there being
        // open orders: with the store on, the Online tab is always available,
        // so the Orders page must be reachable to host it.
        final hasOnlineOrders =
            session.storeEnabled && _canDecideOnlineOrders(session.userRole);
        final items = _buildNavItems(session.userRole, session.businessType,
            hasOpenDrafts, hasCredit, hasOnlineOrders);
        // Kept so a notification tap can find the Orders tab's index without
        // rebuilding the list outside build().
        _navItems = items;
        final safeIndex = _index.clamp(0, items.length - 1);
        final isWide = MediaQuery.of(context).size.width >= 720;

        final inGrace = widget.licenseStatus?.state == LicenseState.grace;
        final graceDays = widget.licenseStatus?.graceDaysRemaining ?? 0;

        // Back behaviour: from any bottom-bar tab, the first back press returns
        // to Billing (the home tab, index 0). Only a back press while already
        // on Billing is allowed to pop the shell and exit the app.
        final onHomeTab = safeIndex == 0;
        return PopScope(
          canPop: onHomeTab,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            setState(() => _index = 0);
          },
          child: Scaffold(
          bottomNavigationBar: isWide ? null : _buildBottomNav(items, safeIndex),
          body: Column(
            children: [
              if (inGrace)
                Container(
                  width: double.infinity,
                  color: AppColors.warningLight,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          graceDays <= 1
                              ? context.l10n.licenseGraceLastDay
                              : context.l10n.licenseGraceDaysLeft(graceDays),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (isWide)
                      FadeTransition(
                        opacity: _railFadeAnim,
                        child: _buildRail(items, safeIndex),
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: safeIndex,
                        children: items.map((e) => e.screen).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              // Wide (rail) layout has no bottom nav to anchor the strip to, so
              // pin it to the bottom of the body instead. Narrow layouts get it
              // above the bottom nav in _buildBottomNav.
              if (isWide) const ConnectivityBar(),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildRail(List<NavItem> items, int selectedIndex) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(right: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: _onNav,
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.primaryLight,
        selectedIconTheme:
            const IconThemeData(color: AppColors.primary, size: 22),
        unselectedIconTheme:
            const IconThemeData(color: AppColors.textSecondary, size: 22),
        selectedLabelTextStyle: const TextStyle(
            color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500),
        labelType: NavigationRailLabelType.all,
        minWidth: 72,
        leading: const SizedBox(height: AppSpacing.space8),
        destinations: items.map((item) {
          return NavigationRailDestination(
            icon: Icon(item.iconOutlined),
            selectedIcon: Icon(item.iconFilled),
            label: Text(item.label),
            padding: const EdgeInsets.symmetric(vertical: 4),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomNav(List<NavItem> items, int safeIndex) {
    // The connectivity strip sits BELOW the nav bar (YouTube-style), pinned to
    // the very bottom edge of the screen. When it is showing it also owns the
    // bottom safe-area inset; otherwise the nav bar keeps it.
    final banner = ref.watch(connectivityBannerProvider);
    final barVisible = banner != ConnectivityBanner.online;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(top: BorderSide(color: AppColors.border)),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            // While the bar is visible it hugs the bottom edge and takes the
            // inset, so the nav bar must not also pad the bottom (double gap).
            bottom: !barVisible,
            child: AppBottomNavBar(
              items: items,
              selectedIndex: safeIndex,
              onDestinationSelected: _onNav,
            ),
          ),
        ),
        const ConnectivityBar(),
      ],
    );
  }
}
