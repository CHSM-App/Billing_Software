import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../services/sync_service.dart';
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
  const MainShell({super.key, this.initialIndex = 0});

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
    return [
      const NavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Billing',
          HomeScreen()),
      if (userRole == 'owner')
        const NavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Items',
            ItemsScreen()),
      if (businessType == 'restaurant_with_tables')
        const NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
            'Tables', TablesScreen()),
      const NavItem(
          Icons.history_outlined, Icons.history, 'History', HistoryScreen()),
      if (userRole == 'owner')
        const NavItem(Icons.bar_chart_outlined, Icons.bar_chart, 'Reports',
            ReportsScreen()),
      if (userRole == 'owner')
        const NavItem(Icons.account_balance_wallet_outlined,
            Icons.account_balance_wallet, 'Expenses', ExpensesScreen()),
      const NavItem(
          Icons.settings_outlined, Icons.settings, 'Settings', SettingsScreen()),
    ];
  }

  void _onNav(int i) {
    if (i == _index) return;
    // Tapping the Billing tab (index 0) always starts a fresh bill —
    // clear any leftover cart from a previous table session.
    if (i == 0) {
      ref.read(cartProvider.notifier).clear();
    }
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

        return Scaffold(
          body: Row(
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
          bottomNavigationBar: isWide
              ? null
              : _buildBottomNav(items, safeIndex),
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
