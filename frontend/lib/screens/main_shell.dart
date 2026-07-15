import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../services/sync_service.dart';
import '../services/license_service.dart';
import '../widgets/nav_item.dart';
import '../widgets/bottom_nav_bar.dart';
import 'home_screen.dart';
import 'items_screen.dart';
import 'tables_screen.dart';
import 'history_screen.dart';
import 'reports_screen.dart';
import 'expenses_screen.dart';
import 'settings_screen.dart';

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
  }

  @override
  void dispose() {
    _railAnimController.dispose();
    super.dispose();
  }

  List<NavItem> _buildNavItems(String userRole, String businessType) {
    final l10n = context.l10n;
    return [
      NavItem(Icons.receipt_long_outlined, Icons.receipt_long, l10n.navBilling,
          const HomeScreen()),
      if (userRole == 'owner')
        NavItem(Icons.inventory_2_outlined, Icons.inventory_2, l10n.navItems,
            const ItemsScreen()),
      if (businessType == 'restaurant_with_tables')
        NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
            l10n.navTables, const TablesScreen()),
      NavItem(Icons.history_outlined, Icons.history, l10n.navHistory,
          const HistoryScreen()),
      if (userRole == 'owner')
        NavItem(Icons.bar_chart_outlined, Icons.bar_chart, l10n.navReports,
            const ReportsScreen()),
      if (userRole == 'owner')
        NavItem(Icons.account_balance_wallet_outlined,
            Icons.account_balance_wallet, l10n.navExpenses, const ExpensesScreen()),
      NavItem(Icons.settings_outlined, Icons.settings, l10n.navSettings,
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

        final items = _buildNavItems(session.userRole, session.businessType);
        final safeIndex = _index.clamp(0, items.length - 1);
        final isWide = MediaQuery.of(context).size.width >= 720;

        final inGrace = widget.licenseStatus?.state == LicenseState.grace;
        final graceDays = widget.licenseStatus?.graceDaysRemaining ?? 0;

        return Scaffold(
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
