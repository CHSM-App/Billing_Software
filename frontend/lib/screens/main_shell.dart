import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
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

  List<_NavItem> _buildNavItems(String userRole, String businessType) {
    return [
      _NavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Billing',
          const HomeScreen()),
      if (userRole == 'owner')
        _NavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Items',
            const ItemsScreen()),
      if (businessType == 'restaurant_with_tables')
        _NavItem(Icons.table_restaurant_outlined, Icons.table_restaurant,
            'Tables', const TablesScreen()),
      _NavItem(Icons.history_outlined, Icons.history, 'History',
          const HistoryScreen()),
      if (userRole == 'owner')
        _NavItem(Icons.bar_chart_outlined, Icons.bar_chart, 'Reports',
            const ReportsScreen()),
      _NavItem(Icons.settings_outlined, Icons.settings, 'Settings',
          const SettingsScreen()),
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
        final items =
            _buildNavItems(session.userRole, session.businessType);
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
          bottomNavigationBar:
              isWide ? null : _buildBottomNav(items, safeIndex),
        );
      },
    );
  }

  Widget _buildBottomNav(List<_NavItem> items, int selectedIndex) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => setState(() => _index = i),
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryLight,
      destinations: items
          .map((item) => NavigationDestination(
                icon: Icon(item.iconOutlined, color: AppColors.textSecondary),
                selectedIcon: Icon(item.iconFilled, color: AppColors.primary),
                label: item.label,
              ))
          .toList(),
    );
  }

  Widget _buildRail(List<_NavItem> items, int selectedIndex) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => setState(() => _index = i),
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryLight,
      selectedIconTheme: const IconThemeData(color: AppColors.primary),
      unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
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

class _NavItem {
  final IconData iconOutlined;
  final IconData iconFilled;
  final String label;
  final Widget screen;
  const _NavItem(this.iconOutlined, this.iconFilled, this.label, this.screen);
}
