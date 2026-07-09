import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A custom app bar that works safely inside a Column (not Scaffold.appBar).
/// Avoids AppBar's Scaffold-dependent layout which crashes inside IndexedStack.
class ShellAppBar extends StatelessWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  const ShellAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = automaticallyImplyLeading && Navigator.of(context).canPop();
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: topPadding),
          SizedBox(
            height: kToolbarHeight,
            child: Row(
              children: [
                if (leading != null)
                  leading!
                else if (canPop)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: AppColors.textPrimary,
                    onPressed: () => Navigator.of(context).pop(),
                  )
                else
                  const SizedBox(width: 16),
                Expanded(
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.titleLarge!,
                    child: title ?? const SizedBox.shrink(),
                  ),
                ),
                if (actions != null) ...actions!,
                if (actions == null) const SizedBox(width: 16),
              ],
            ),
          ),
          if (bottom != null)
            SizedBox(
              height: bottom!.preferredSize.height,
              child: bottom!,
            ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
        ],
      ),
    );
  }
}
