import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // used to hide printer tile on web
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'login_screen.dart';
// Printer screens use native-only packages — excluded on web.
import 'printer_setup_screen.dart'
    if (dart.library.html) 'printer_setup_screen_web.dart';
import 'printer_test_screen.dart'
    if (dart.library.html) 'printer_test_screen_web.dart';
import 'printer_test_windows_screen.dart'
    if (dart.library.html) 'printer_test_windows_screen_web.dart';
import 'staff_screen.dart';
import 'business_profile_screen.dart';
import 'conflict_resolution_screen.dart';
import '../services/offline_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider);

    return sessionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      data: (session) => _SettingsContent(session: session, ref: ref),
    );
  }
}

class _SettingsContent extends StatefulWidget {
  final dynamic session;
  final WidgetRef ref;

  const _SettingsContent({required this.session, required this.ref});

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnim =
        CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: const Icon(Icons.logout_outlined,
                  size: 18, color: AppColors.error),
            ),
            const SizedBox(width: AppSpacing.space12),
            const Text('Logout'),
          ],
        ),
        content: const Text(
            'Are you sure you want to logout from your account?'),
        actions: [
          SecondaryButton(
            text: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          const SizedBox(width: AppSpacing.space8),
          DestructiveButton(
            text: 'Logout',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.ref.read(sessionProvider.notifier).clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final isOwner = session.userRole == 'owner';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: RefreshIndicator(
          onRefresh: () =>
              widget.ref.read(sessionProvider.notifier).refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile header card
                    _buildProfileCard(context, session, isOwner),
                    const SizedBox(height: AppSpacing.space24),

                    if (isOwner) ...[
                      _sectionLabel(context, 'BUSINESS'),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.storefront_outlined,
                        iconColor: AppColors.primary,
                        title: 'Business Profile',
                        subtitle: 'Name, address, GST, billing settings',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BusinessProfileScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space24),

                      _sectionLabel(context, 'TEAM'),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.people_outline,
                        iconColor: const Color(0xFF0EA5E9),
                        title: 'Manage Staff',
                        subtitle: 'Add, edit or remove cashiers',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const StaffScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space24),

                      _sectionLabel(context, 'SYNC'),
                      const SizedBox(height: AppSpacing.space8),
                      const _SyncConflictTile(),
                      const SizedBox(height: AppSpacing.space24),
                    ],

                    if (!kIsWeb) ...[
                      _sectionLabel(context, 'HARDWARE'),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.print_outlined,
                        iconColor: const Color(0xFF7C3AED),
                        title: 'Printer Setup',
                        subtitle: 'Configure your thermal printer',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PrinterSetupScreen()),
                        ),
                      ),
                    ],
                    // const SizedBox(height: AppSpacing.space8),
                    // _buildNavCard(
                    //   context,
                    //   icon: Icons.bug_report_outlined,
                    //   iconColor: AppColors.warning,
                    //   title: 'Printer Test Android (Dev)',
                    //   subtitle: 'Test all print methods on Android',
                    //   onTap: () => Navigator.push(
                    //     context,
                    //     MaterialPageRoute(
                    //         builder: (_) => const PrinterTestScreen()),
                    //   ),
                    // ),
                    // const SizedBox(height: AppSpacing.space8),
                    // _buildNavCard(
                    //   context,
                    //   icon: Icons.bug_report_outlined,
                    //   iconColor: const Color(0xFF0078D4),
                    //   title: 'Printer Test Windows (Dev)',
                    //   subtitle: 'Test all print methods on Windows',
                    //   onTap: () => Navigator.push(
                    //     context,
                    //     MaterialPageRoute(
                    //         builder: (_) => const PrinterTestWindowsScreen()),
                    //   ),
                    // ),

                    const SizedBox(height: AppSpacing.space32),
                    _buildLogoutButton(),
                    const SizedBox(height: AppSpacing.space32),

                    // App version footer
                    Center(
                      child: Text(
                        'Vittam Billing v$_appVersion',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textDisabled,
                            ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(
      BuildContext context, dynamic session, bool isOwner) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadow.primary,
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2),
                ),
                child: Center(
                  child: Text(
                    session.userName.isNotEmpty
                        ? session.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.userName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        session.userRole.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space16),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: AppSpacing.space16),
          Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  size: 16, color: Colors.white70),
              const SizedBox(width: AppSpacing.space8),
              Expanded(
                child: Text(
                  session.businessName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Row(
            children: [
              const Icon(Icons.category_outlined,
                  size: 16, color: Colors.white70),
              const SizedBox(width: AppSpacing.space8),
              Text(
                _formatType(session.businessType),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: const Icon(Icons.chevron_right_outlined,
                size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_outlined,
                size: 18, color: AppColors.error),
            const SizedBox(width: AppSpacing.space8),
            const Text(
              'Logout',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
    );
  }

  String _formatType(String type) {
    return switch (type) {
      'retail' => 'Retail Shop',
      'restaurant_with_tables' => 'Restaurant (with tables)',
      'restaurant_no_tables' => 'Restaurant (takeaway)',
      _ => type,
    };
  }
}

// ---------------------------------------------------------------------------
// _SyncConflictTile — shows attention count badge and opens conflict screen
// ---------------------------------------------------------------------------

class _SyncConflictTile extends StatefulWidget {
  const _SyncConflictTile();

  @override
  State<_SyncConflictTile> createState() => _SyncConflictTileState();
}

class _SyncConflictTileState extends State<_SyncConflictTile> {
  int _attentionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await OfflineService.instance.getAttentionCount();
    if (mounted) setState(() => _attentionCount = count);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ConflictResolutionScreen()),
        );
        _loadCount(); // refresh badge after returning
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _attentionCount > 0
                  ? AppColors.warningLight
                  : AppColors.successLight,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(
              _attentionCount > 0
                  ? Icons.sync_problem_outlined
                  : Icons.sync_outlined,
              size: 20,
              color: _attentionCount > 0
                  ? AppColors.warning
                  : AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unsynced Bills',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  _attentionCount > 0
                      ? '$_attentionCount bill(s) need attention'
                      : 'All bills synced',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _attentionCount > 0
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          if (_attentionCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_attentionCount',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            )
          else
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: const Icon(Icons.chevron_right_outlined,
                  size: 18, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

