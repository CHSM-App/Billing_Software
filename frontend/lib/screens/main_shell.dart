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
import 'settings_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
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
      const NavItem(
          Icons.settings_outlined, Icons.settings, 'Settings', SettingsScreen()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider);

    return sessionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      data: (session) {
        // Auto-sync when connectivity is restored
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
              if (isWide) _buildRail(items, safeIndex),
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
              : AppBottomNavBar(
                  items: items,
                  selectedIndex: safeIndex,
                  onDestinationSelected: (i) => setState(() => _index = i),
                ),
        );
      },
    );
  }

  Widget _buildRail(List<NavItem> items, int selectedIndex) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => setState(() => _index = i),
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryLight,
      selectedIconTheme: const IconThemeData(color: AppColors.primary),
      unselectedIconTheme:
          const IconThemeData(color: AppColors.textSecondary),
      selectedLabelTextStyle: const TextStyle(
          color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle:
          const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      labelType: NavigationRailLabelType.all,
      destinations: items
          .map((item) => NavigationRailDestination(
                icon: Icon(item.iconOutlined),
                selectedIcon: Icon(item.iconFilled),
                label: Text(item.label),
              ))
          .toList(),
    );
  }
}
