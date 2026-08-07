import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../providers/connectivity_provider.dart';
import '../theme/app_theme.dart';

/// A YouTube-style connectivity strip that sits directly above the bottom nav.
///
///   • Offline    → a dark "No connection" bar that stays until reconnected.
///   • Back online → a green "Back online" bar that auto-dismisses after ~2s.
///   • Online      → nothing (zero height).
///
/// Drives itself entirely from [connectivityBannerProvider]; drop it above the
/// bottom navigation bar and it manages its own visibility and animation.
class ConnectivityBar extends ConsumerWidget {
  const ConnectivityBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final banner = ref.watch(connectivityBannerProvider);

    final bool visible = banner != ConnectivityBanner.online;
    final bool online = banner == ConnectivityBanner.backOnline;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axisAlignment: 1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: !visible
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              key: ValueKey(online),
              width: double.infinity,
              color: online
                  ? AppColors.success
                  : const Color(0xFF202124), // YouTube-style near-black
              // Absorb the bottom safe-area inset so the label clears the
              // gesture bar / rounded corners when pinned to the screen edge.
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      online
                          ? l10n.connectivityBackOnline
                          : l10n.connectivityNoConnection,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
