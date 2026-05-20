import 'package:flutter/material.dart';

class NavItem {
  final IconData iconOutlined;
  final IconData iconFilled;
  final String label;
  final Widget screen;

  const NavItem(this.iconOutlined, this.iconFilled, this.label, this.screen);
}
