import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../services/sync_service.dart';
import '../services/license_service.dart';
import '../services/realtime_service.dart';
import '../services/notification_service.dart';
import '../widgets/nav_item.dart';
import '../widgets/bottom_nav_bar.dart';
import 'home_screen.dart';
import 'items_screen.dart';
import 'tables_screen.dart';
import 'kitchen_screen.dart';
import 'open_drafts_screen.dart';
import 'settings_screen.dart';
import '../providers/open_drafts_provider.dart';

class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;
  final LicenseStatus? licenseStatus;
  const MainShell({super.key, this.initialIndex = 0, this.licenseStatus});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _railAnimController;
  late final Animation<double> _railFadeAnim;
  StreamSubscription<String>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
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
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _railAnimController.dispose();
    super.dispose();
  }

  List<NavItem> _buildNavItems(
      String userRole, String businessType, bool hasOpenDrafts) {
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
      if (businessType == 'restaurant_with_tables')
        NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
            l10n.navTables, const TablesScreen()),
      // Waiters and owners at a restaurant can watch the kitchen queue.
      if (isRestaurant)
        NavItem(Icons.restaurant_menu_outlined, Icons.restaurant_menu,
            l10n.navKitchen, const KitchenScreen()),
      // Open Orders: table-less drafts awaiting finalization. Only shown while
      // such drafts exist, so it appears/disappears with the queue.
      if (hasOpenDrafts)
        NavItem(Icons.receipt_long_outlined, Icons.receipt_long,
            l10n.navOpenOrders, const OpenDraftsScreen()),
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
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      data: (session) {
        ref.listen<bool>(connectivityProvider, (prev, next) {
          if (prev == false && next == true) {
            SyncService.instance.syncAll().then((_) {
              ref.invalidate(itemsProvider);
              ref.invalidate(categoriesProvider);
              ref.invalidate(tablesProvider);
            });
          }
        });

        // Kitchen staff never see billing/orders, so don't even query drafts.
        final hasOpenDrafts = session.userRole != 'kitchen' &&
            ref.watch(hasOpenDraftsProvider);
        final items = _buildNavItems(
            session.userRole, session.businessType, hasOpenDrafts);
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
    return Container(
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
        child: AppBottomNavBar(
          items: items,
          selectedIndex: safeIndex,
          onDestinationSelected: _onNav,
        ),
      ),
    );
  }
}
