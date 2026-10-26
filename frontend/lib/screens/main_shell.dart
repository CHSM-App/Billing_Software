import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
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
import 'warranty_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'license_screen.dart';
import 'login_screen.dart';
import '../providers/open_drafts_provider.dart';
import '../widgets/stock_target_picker.dart' show isRetailWarrantyShop;

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

  /// Narrow layout: the bottom bar slides away while the user scrolls a page
  /// down and comes back on the way up (YouTube-style). See [_onPageScroll].
  final _navShown = AppBottomNavBar.shown;
  double _navDrift = 0; // px the user has scrolled in the current direction
  bool _userScrolling = false;
  int _navShownFor = -1; // tab the bar was last reset for
  bool _wasCurrent = true; // shell's route was on top at the last build

  /// Scroll this far in one direction before the bar hides/shows, so a
  /// wobbling thumb doesn't flicker it.
  static const double _navToggleAfter = 24;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    HardwareKeyboard.instance.addHandler(_onEscBack);
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
    NotificationService.instance.lowStockTap.addListener(_onLowStockTapped);
    NotificationService.instance.tableOrderPing.addListener(_onTableOrderPing);

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
          if (NotificationService.instance.consumeTap('online_order')) {
            _openOnlineOrders();
          }
        }
      }
      // Same cold-launch case for the owner's low-stock alert.
      if (NotificationService.instance.consumeTap('low_stock')) _openItems();
    });
  }

  void _onRealtimeEvent(String type) {
    if (!mounted) return;
    switch (type) {
      case 'kitchen':
        // The Kitchen screen listens to this ping and reloads its queue.
        NotificationService.instance.pingKitchen();
        // Open Orders shows each dish's kitchen status too (the chef has no
        // Orders page, so skip the fetch there).
        if (ref.read(sessionProvider).valueOrNull?.userRole != 'kitchen') {
          ref.read(openDraftsProvider.notifier).refreshSilently();
        }
        break;
      case 'tables':
        ref.read(tablesProvider.notifier).refreshSilently();
        // Table orders are listed in Open Orders too, and their saves only
        // broadcast 'tables'.
        ref.read(openDraftsProvider.notifier).refreshSilently();
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
      case 'staff':
        // An owner changed someone's role. Every device of this business hears
        // it; only the one whose own role moved is signed out.
        _recheckDeviceAccess();
        break;
      case 'store':
        // A customer placed an order, or another device accepted/rejected one.
        ref.read(onlineOrdersProvider.notifier).refreshSilently();
        break;
      case 'stock':
        // A sale, order edit or void moved stock — on this device or another —
        // so the billing list's out-of-stock rows stay current.
        ref.read(itemsProvider.notifier).refreshInBackground();
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
      // Same check also refreshes the cached store_enabled flag — pick it up so
      // the online-order tab appears/disappears on resume rather than at the
      // next login.
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;

      // The role this device is running as, versus the role the server says it
      // has right now. They differ when an owner changed it mid-session — and
      // until this check existed, nothing noticed: the role lives in an 8-hour
      // access token that is never re-read, so a kitchen user demoted to
      // captain kept the Kitchen screen and kept taking orders. Sign them out;
      // the next login issues a token with the right role. A null server role
      // (their user row is gone) counts as changed for the same reason.
      //
      // Three ways this session is no longer valid, all ending the same way:
      //   * the role moved           — currentRole differs from the cached one
      //   * the account was disabled — accountActive is false
      //   * the user was deleted     — currentRole comes back null
      // The null case was previously skipped, so a deleted staff member kept
      // working until their token expired.
      final sessionRole = ref.read(sessionProvider).valueOrNull?.userRole;
      final hadSession = sessionRole != null && sessionRole.isNotEmpty;
      // A null currentRole means "we did not hear from the server" — an offline
      // check returns exactly that — so it must never count as a change, or
      // losing signal would sign everyone out. Deletion is covered by
      // accountActive instead, which the server answers definitively.
      final roleChanged = hadSession &&
          status.currentRole != null &&
          status.currentRole != sessionRole;
      if (hadSession && (!status.accountActive || roleChanged)) {
        await ref.read(sessionProvider.notifier).clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }

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
    NotificationService.instance.tableOrderPing
        .removeListener(_onTableOrderPing);
    NotificationService.instance.onlineOrderTap
        .removeListener(_onOnlineOrderTapped);
    NotificationService.instance.lowStockTap.removeListener(_onLowStockTapped);
    _railAnimController.dispose();
    HardwareKeyboard.instance.removeHandler(_onEscBack);
    super.dispose();
  }

  /// Windows: Esc works like the back arrow. Pops the page on top (respecting
  /// its PopScope, e.g. an unsaved-bill prompt); at the shell's own level it
  /// returns to Billing, and on Billing it does nothing — Esc never exits.
  ///
  /// Dialogs, sheets and menus (PopupRoutes) are left to Flutter's own Esc
  /// handling, which honours barrierDismissible. Returns true only when it
  /// acted, so Esc still reaches text fields and overlays otherwise.
  bool _onEscBack(KeyEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted) {
      return false;
    }
    final nav = Navigator.of(context);
    Route<dynamic>? top;
    nav.popUntil((r) {
      top = r; // peek at the top route without popping anything
      return true;
    });
    if (top is PopupRoute) return false;
    // A page pushed over the shell (compared to the shell's own route rather
    // than canPop, so Esc can never pop the shell itself).
    if (top != null && top != ModalRoute.of(context)) {
      nav.maybePop();
      return true;
    }
    if (_index != 0) {
      // Drop keyboard focus too: the key press flips Flutter into keyboard
      // highlight mode, and a still-focused rail item would stay greyed out.
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _index = 0);
      return true;
    }
    return false;
  }

  /// A QR table order arrived by push. Refreshes exactly what the WebSocket
  /// `tables`/`drafts` events would have, for the case the socket was asleep
  /// because the app was backgrounded.
  void _onTableOrderPing() {
    if (!mounted) return;
    ref.read(tablesProvider.notifier).refreshSilently();
    ref.read(openDraftsProvider.notifier).refreshSilently();
  }

  void _onOnlineOrderPing() {
    if (!mounted) return;
    ref.read(onlineOrdersProvider.notifier).refreshSilently();
  }

  void _onOnlineOrderTapped() {
    if (!mounted) return;
    NotificationService.instance.consumeTap('online_order');
    _openOnlineOrders();
  }

  void _onLowStockTapped() {
    if (!mounted) return;
    NotificationService.instance.consumeTap('low_stock');
    _openItems();
  }

  /// Jump to Items, where low-stock items sort to the top. Owner-only tab, and
  /// only owners get the alert — anyone else simply stays where they are.
  void _openItems() {
    final i = _navItems.indexWhere((n) => n.screen is ItemsScreen);
    if (i >= 0) _onNav(i);
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
      {bool wide = false}) {
    final l10n = context.l10n;
    final isRestaurant = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
    // Kitchen chef only sees the Kitchen Display and Settings (for logout /
    // language). No billing, items, reports or history.
    if (userRole == 'kitchen') {
      return [
        // No ready-count badge here: the chef marks dishes ready, it is the
        // floor staff who need telling.
        NavItem(Icons.restaurant_menu_outlined, Icons.restaurant_menu,
            l10n.navKitchen, const KitchenScreen()),
        NavItem(Icons.person_outline, Icons.person, l10n.navProfile,
            const SettingsScreen()),
      ];
    }

    final int ordersBadge =
        (ref.watch(openDraftsProvider).valueOrNull?.length ?? 0) +
            ref.watch(pendingOnlineOrderCountProvider);

    return [
      NavItem(Icons.receipt_long_outlined, Icons.receipt_long, l10n.navBilling,
          const HomeScreen()),
      if (userRole == 'owner')
        NavItem(Icons.inventory_2_outlined, Icons.inventory_2, l10n.navItems,
            const ItemsScreen()),
      // Orders: one page hosting Tables (table restaurants only), Open Orders,
      // Online and Credit as sub-tabs. Always shown, even when every queue is
      // empty. Badge = open drafts (table orders included) + online orders
      // still waiting on a decision; credit is not counted. Accepted online
      // orders are already drafts, so counting only pending avoids doubles.
      if (businessType == 'restaurant_with_tables')
        NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
            l10n.navOrders, const OrdersScreen(showTables: true),
            badge: ordersBadge)
      else
        NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
            l10n.navOrders, const OrdersScreen(showTables: false),
            badge: ordersBadge),
      // Waiters and owners at a restaurant can watch the kitchen queue.
      if (isRestaurant)
        // Red count: dishes ready and waiting to be served.
        NavItem(Icons.restaurant_menu_outlined, Icons.restaurant_menu,
            l10n.navKitchen, const KitchenScreen(),
            badge: ref.watch(kitchenReadyCountProvider)),
      // Tyre/battery/electronics shops track warranty records per customer.
      if (isRetailWarrantyShop(businessType))
        NavItem(Icons.verified_user_outlined, Icons.verified_user,
            l10n.navWarranty, const WarrantyScreen()),
      // History, Reports and Expenses moved into the Profile screen. The side
      // rail (wide screens, Windows) has room, so History is a tab there too —
      // same roles as its Profile card (not waiters).
      if (wide && userRole != 'server')
        NavItem(Icons.history_outlined, Icons.history, l10n.navHistory,
            const HistoryScreen()),
      NavItem(Icons.person_outline, Icons.person, l10n.navProfile,
          const SettingsScreen()),
    ];
  }

  void _onNav(int i) {
    if (i == _index) return;
    // Opening the Kitchen tab reloads its queue (and so the badge count).
    if (i < _navItems.length && _navItems[i].screen is KitchenScreen) {
      NotificationService.instance.pingKitchen();
    }
    setState(() => _index = i);
  }

  /// Hide the bottom bar after the user scrolls a page down, show it again
  /// after scrolling back up or on reaching the top. Only finger-driven scrolls
  /// (drags and the flings they release) move it — a jump-to-category or other
  /// programmatic scroll never hides it. Sideways strips are ignored.
  bool _onPageScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (MediaQuery.sizeOf(context).width >= 720) return false; // rail, no bar
    if (n is UserScrollNotification) {
      _userScrolling = n.direction != ScrollDirection.idle;
      _navDrift = 0;
    } else if (n is ScrollUpdateNotification) {
      if (n.metrics.extentBefore <= 0) {
        _navShown.value = true;
      } else if (_userScrolling && !n.metrics.outOfRange) {
        // outOfRange: an iOS bounce at either end isn't a change of mind.
        final d = n.scrollDelta ?? 0;
        _navDrift = _navDrift.sign == d.sign ? _navDrift + d : d;
        if (_navDrift > _navToggleAfter) _navShown.value = false;
        if (_navDrift < -_navToggleAfter) _navShown.value = true;
      }
    }
    return false;
  }

  /// Push the offline queue, then reload everything that went stale offline.
  ///
  /// The refresh runs whether or not the sync succeeded. It used to hang off
  /// `syncAll().then(...)`, and syncAll — despite its doc — is only
  /// try/finally, so ONE throwing database call left every page frozen on the
  /// offline error state it was showing when the network died, with no way back
  /// short of restarting the app. Reconnecting must always reload; pushing the
  /// queue is the part allowed to fail.
  Future<void> _refreshAfterReconnect() async {
    try {
      await SyncService.instance.syncAll();
    } catch (e) {
      debugPrint('[SYNC] reconnect sync failed, refreshing anyway: $e');
    }
    if (!mounted) return;
    ref.invalidate(itemsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(categoryTreeProvider);
    ref.invalidate(tablesProvider);
    // Queued offline drafts were just pushed; refresh Open Orders so their
    // local copies are replaced by the authoritative server ones.
    ref.invalidate(openDraftsProvider);
    // Online orders may have arrived while offline; the Orders badge counts
    // them. Silent refresh so a failed fetch keeps the last list.
    unawaited(ref.read(onlineOrdersProvider.notifier).refreshSilently());
    // History: the just-synced offline bills are now on the server and their
    // local INV-<tag>-#### rows are gone, so re-fetch the authoritative copies.
    ref.invalidate(billsProvider);
    ref.invalidate(reportProvider);
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
            unawaited(_refreshAfterReconnect());
          }
        });

        final isWide = MediaQuery.of(context).size.width >= 720;
        final items = _buildNavItems(session.userRole, session.businessType,
            wide: isWide);
        // Kept so a notification tap can find the Orders tab's index without
        // rebuilding the list outside build().
        _navItems = items;
        final safeIndex = _index.clamp(0, items.length - 1);
        // Coming back from a page pushed over the shell (which has no bottom
        // bar) also brings the bar back, however it was left on the way in.
        // isCurrentOf rebuilds the shell when that page pops — at the START of
        // the pop, so the bar is already there as the page slides away.
        final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
        final returned = isCurrent && !_wasCurrent;
        _wasCurrent = isCurrent;
        // Every way of landing on a tab (tap, back press, notification) starts
        // with the bottom bar showing, wherever the last tab left it.
        if (safeIndex != _navShownFor || isWide || returned) {
          _navShownFor = safeIndex;
          _navShown.value = true;
          _navDrift = 0;
        }

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
          // Content runs under the floating glass bar (narrow layout). The
          // Scaffold raises the body's bottom padding by the bar's height, and
          // tab screens add that padding so nothing ends up hidden behind it.
          extendBody: true,
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
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onPageScroll,
                        child: IndexedStack(
                          index: safeIndex,
                          children: items.map((e) => e.screen).toList(),
                        ),
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
            icon: item.badged(Icon(item.iconOutlined)),
            selectedIcon: item.badged(Icon(item.iconFilled)),
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
    // The Scaffold has extendBody, so page content scrolls under this whole
    // area: a soft dark fade at the screen bottom, with the floating glass
    // capsule above it. Only the capsule takes taps; the fade and the margins
    // around the capsule let touches through to the content behind.
    //
    // Scrolling down slides this whole area (fade, glass, highlight, strip)
    // below the screen edge as one piece; while hidden it ignores taps, so
    // nothing invisible sits over the content. Its layout height is unchanged,
    // so lists keep their bottom padding and nothing jumps.
    return HidesWithNavBar(
      child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Eased fade: stays clear near the top of the area, then
                  // deepens towards the screen edge.
                  colors: [
                    AppColors.textPrimary.withValues(alpha: 0),
                    AppColors.textPrimary.withValues(alpha: 0.10),
                    AppColors.textPrimary.withValues(alpha: 0.28),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeArea(
              top: false,
              // While the bar is visible it hugs the bottom edge and takes the
              // inset, so the capsule must not also pad the bottom (double gap).
              bottom: !barVisible,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: AppBottomNavBar(
                  items: items,
                  selectedIndex: safeIndex,
                  onDestinationSelected: _onNav,
                ),
              ),
            ),
            const ConnectivityBar(),
          ],
        ),
      ],
      ),
    );
  }
}
