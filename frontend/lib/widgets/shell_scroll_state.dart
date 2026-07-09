import 'package:flutter/material.dart';

/// Inherited widget that broadcasts whether the app bars should be visible.
/// MainShell writes it; individual screens read it to animate their AppBar.
class ShellScrollState extends InheritedWidget {
  final bool barsVisible;

  const ShellScrollState({
    super.key,
    required this.barsVisible,
    required super.child,
  });

  static ShellScrollState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScrollState>();

  @override
  bool updateShouldNotify(ShellScrollState old) =>
      old.barsVisible != barsVisible;
}
