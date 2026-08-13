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
import '../providers/credit_provider.dart';

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
        break;
      case 'credit':
        ref.read(creditCustomersProvider.notifier).refreshSilently();
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
    _railAnimController.dispose();
    super.dispose();
  }

  List<NavItem> _buildNavItems(String userRole, String businessType,
      bool hasOpenDrafts, bool hasCredit) {
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
      // Orders: one page hosting Tables (table restaurants only), Open Orders
      // and Credit as sub-tabs. Table restaurants always show it (Tables is
      // always relevant). Retail / no-table businesses get the SAME page — just
      // without the Tables sub-tab — and only while there's something in it
      // (open drafts or outstanding credit), so it doesn't sit empty.
      if (businessType == 'restaurant_with_tables')
        NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
            l10n.navOrders, const OrdersScreen(showTables: true))
      else if (hasOpenDrafts || hasCredit)
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
        final items = _buildNavItems(
            session.userRole, session.businessType, hasOpenDrafts, hasCredit);
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
