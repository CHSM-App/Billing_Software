import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'nav_item.dart';

class AppBottomNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
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
}
