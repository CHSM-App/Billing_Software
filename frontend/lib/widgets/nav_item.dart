import 'package:flutter/material.dart';

class NavItem {
  final IconData iconOutlined;
  final IconData iconFilled;
  final String label;
  final Widget screen;

  /// Count shown in a red badge on the icon; hidden when 0.
  final int badge;

  const NavItem(this.iconOutlined, this.iconFilled, this.label, this.screen,
      {this.badge = 0});

  /// [icon] wrapped in the red count badge (no-op when [badge] is 0).
  Widget badged(Widget icon) => Badge(
        isLabelVisible: badge > 0,
        backgroundColor: Colors.red,
        label: Text('$badge'),
        child: icon,
      );
}
