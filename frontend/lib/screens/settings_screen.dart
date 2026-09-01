import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // used to hide printer tile on web
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../storage.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/language_selector.dart';
import '../widgets/shell_app_bar.dart';
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
import 'marathi_print_test_screen.dart';
import 'raster_lab_screen.dart';
import 'conflict_resolution_screen.dart';
import 'history_screen.dart';
import 'reports_screen.dart';
import 'vendor_bills_screen.dart';
import 'expenses_screen.dart';
import '../services/offline_service.dart';
import '../services/realtime_service.dart';

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
    final l10n = context.l10n;
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
            Text(l10n.logout),
          ],
        ),
        content: Text(l10n.logoutConfirmBody),
        actions: [
          SecondaryButton(
            text: l10n.commonCancel,
            onPressed: () => Navigator.pop(context, false),
          ),
          const SizedBox(height: AppSpacing.space8),
          DestructiveButton(
            text: l10n.logout,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Close the real-time socket so it doesn't keep reconnecting after logout.
    await RealtimeService.instance.stop();
    // Drop cached open-drafts so the next user doesn't inherit stale state (this
    // is why the Open Orders tab stayed hidden until a new draft was added).
    widget.ref.invalidate(openDraftsProvider);
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
    final l10n = context.l10n;
    final language = widget.ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
            title: Text(l10n.settingsTitle),
            automaticallyImplyLeading: false),
        Expanded(child: FadeTransition(
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

                    // Activity — History (all roles except kitchen chef).
                    if (session.userRole != 'kitchen') ...[
                      _sectionLabel(context, l10n.settingsSectionActivity),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.history_outlined,
                        iconColor: const Color(0xFF64748B),
                        title: l10n.settingsHistory,
                        subtitle: l10n.settingsHistorySubtitle,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HistoryScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space24),
                    ],

                    // Reports & Expenses — owner only.
                    if (isOwner) ...[
                      _sectionLabel(context, l10n.settingsSectionReports),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.bar_chart_outlined,
                        iconColor: const Color(0xFF16A34A),
                        title: l10n.settingsReports,
                        subtitle: l10n.settingsReportsSubtitle,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ReportsScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.shopping_bag_outlined,
                        iconColor: const Color(0xFF0891B2),
                        title: 'Purchases',
                        subtitle: 'Vendor bills, stock receipts and input tax credit',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const VendorBillsScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: const Color(0xFFEA580C),
                        title: l10n.settingsExpenses,
                        subtitle: l10n.settingsExpensesSubtitle,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ExpensesScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space24),
                    ],

                    if (isOwner) ...[
                      _sectionLabel(context, l10n.settingsSectionBusiness),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.storefront_outlined,
                        iconColor: AppColors.primary,
                        title: l10n.settingsBusinessProfile,
                        subtitle: l10n.settingsBusinessProfileSubtitle,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BusinessProfileScreen()),
                        ),
                      ),
                      // Customer QR self-ordering — restaurants only.
                      if (session.businessType == 'restaurant_with_tables') ...[
                        const SizedBox(height: AppSpacing.space8),
                        _BusinessFlagToggle(
                          field: 'self_order_enabled',
                          icon: Icons.qr_code_2,
                          title: l10n.settingsSelfOrder,
                          subtitle: l10n.settingsSelfOrderSubtitle,
                        ),
                      ],
                      // Inventory tracking — any business type. (Barcode
                      // scanning is always on now, so it has no toggle.)
                      const SizedBox(height: AppSpacing.space8),
                      _BusinessFlagToggle(
                        field: 'inventory_enabled',
                        icon: Icons.inventory_2_outlined,
                        title: l10n.settingsInventory,
                        subtitle: l10n.settingsInventorySubtitle,
                      ),
                      // GST tax invoices — off by default. When on, items gain a
                      // tax rate + HSN/SAC field and receipts show CGST/SGST.
                      const SizedBox(height: AppSpacing.space8),
                      _BusinessFlagToggle(
                        field: 'gst_enabled',
                        icon: Icons.receipt_long_outlined,
                        title: l10n.settingsGst,
                        subtitle: l10n.settingsGstSubtitle,
                      ),
                      // Invoice round-off — off by default. When on, the final
                      // payable is rounded to the nearest rupee and the
                      // adjustment shows as a separate "Round Off" line.
                      const SizedBox(height: AppSpacing.space8),
                      _BusinessFlagToggle(
                        field: 'round_off_enabled',
                        icon: Icons.calculate_outlined,
                        title: l10n.settingsRoundOff,
                        subtitle: l10n.settingsRoundOffSubtitle,
                      ),
                      const SizedBox(height: AppSpacing.space24),

                      _sectionLabel(context, l10n.settingsSectionTeam),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.people_outline,
                        iconColor: const Color(0xFF0EA5E9),
                        title: l10n.settingsManageStaff,
                        subtitle: l10n.settingsManageStaffSubtitle,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const StaffScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space24),

                      _sectionLabel(context, l10n.settingsSectionSync),
                      const SizedBox(height: AppSpacing.space8),
                      const _SyncConflictTile(),
                      const SizedBox(height: AppSpacing.space24),
                    ],

                    _sectionLabel(context, l10n.settingsSectionPreferences),
                    const SizedBox(height: AppSpacing.space8),
                    _buildNavCard(
                      context,
                      icon: Icons.language_outlined,
                      iconColor: const Color(0xFF0891B2),
                      title: l10n.settingsLanguage,
                      subtitle: language.nativeLabel,
                      onTap: () => showLanguagePicker(context),
                    ),

                    if (!kIsWeb) ...[
                      const SizedBox(height: AppSpacing.space24),
                      _sectionLabel(context, l10n.settingsSectionHardware),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.print_outlined,
                        iconColor: const Color(0xFF7C3AED),
                        title: l10n.settingsPrinterSetup,
                        subtitle: l10n.settingsPrinterSetupSubtitle,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PrinterSetupScreen()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space8),
                      _buildNavCard(
                        context,
                        icon: Icons.translate_outlined,
                        iconColor: Colors.deepPurple,
                        title: 'Marathi Print Test',
                        subtitle: 'Diagnose Devanagari printing strategies',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MarathiPrintTestScreen()),
                        ),
                      ),
                      // const SizedBox(height: AppSpacing.space8),
                      // _buildNavCard(
                      //   context,
                      //   icon: Icons.science_outlined,
                      //   iconColor: Colors.indigo,
                      //   title: 'Raster Lab',
                      //   subtitle: 'Staged Devanagari raster diagnostics',
                      //   onTap: () => Navigator.push(
                      //     context,
                      //     MaterialPageRoute(
                      //         builder: (_) => const RasterLabScreen()),
                      //   ),
                      // ),
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

                    const SizedBox(height: AppSpacing.space24),
                    _sectionLabel(context, l10n.settingsSectionAbout),
                    const SizedBox(height: AppSpacing.space8),
                    _buildNavCard(
                      context,
                      icon: Icons.help_outline,
                      iconColor: const Color(0xFF0891B2),
                      title: l10n.settingsHelpCenter,
                      subtitle: l10n.settingsHelpCenterSubtitle,
                      onTap: () => _openUrl(
                          context, 'https://vittam.vengurlatech.com/help'),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    _buildNavCard(
                      context,
                      icon: Icons.privacy_tip_outlined,
                      iconColor: const Color(0xFF16A34A),
                      title: l10n.settingsPrivacyPolicy,
                      subtitle: l10n.settingsPrivacyPolicySubtitle,
                      onTap: () => _openUrl(
                          context, 'https://vittam.vengurlatech.com/privacy'),
                    ),

                    const SizedBox(height: AppSpacing.space32),
                    _buildLogoutButton(),
                    const SizedBox(height: AppSpacing.space32),

                    // App version footer
                    Center(
                      child: Text(
                        l10n.settingsAppVersion(_appVersion),
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
        ))),
      ]),
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

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
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
            Text(
              context.l10n.logout,
              style: AppFont.style(
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
    final l10n = context.l10n;
    return switch (type) {
      'retail' => l10n.businessTypeRetail,
      'restaurant_with_tables' => l10n.businessTypeRestaurantTables,
      'restaurant_no_tables' => l10n.businessTypeRestaurantTakeaway,
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
                Text(context.l10n.settingsUnsyncedBills,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  _attentionCount > 0
                      ? context.l10n.settingsBillsNeedAttention(_attentionCount)
                      : context.l10n.settingsAllBillsSynced,
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

/// Reusable owner toggle for a boolean business-profile flag. Loads the current
/// value, persists changes immediately, and reverts on failure.
class _BusinessFlagToggle extends ConsumerStatefulWidget {
  /// The business-profile field name (e.g. 'inventory_enabled').
  final String field;
  final IconData icon;
  final String title;
  final String subtitle;

  const _BusinessFlagToggle({
    required this.field,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  ConsumerState<_BusinessFlagToggle> createState() =>
      _BusinessFlagToggleState();
}

class _BusinessFlagToggleState extends ConsumerState<_BusinessFlagToggle> {
  bool? _enabled;
  bool _saving = false;

  /// True when this is the GST toggle and the business has no GSTIN yet. A tax
  /// invoice must carry a GSTIN, so the switch stays locked until one is saved
  /// in Business Profile.
  bool _needsGstin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await getBusinessProfile();
      if (mounted) {
        setState(() {
          _enabled = profile[widget.field] == true;
          _needsGstin = widget.field == 'gst_enabled' &&
              ((profile['gst_number'] as String?)?.trim().isEmpty ?? true);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _enabled = false);
    }
  }

  Future<void> _toggle(bool value) async {
    final previous = _enabled;
    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      await updateBusinessProfile({widget.field: value});
      // Keep the cached session in sync so the feature turns on/off right away
      // (hasBarcodeProvider / inventoryEnabledProvider read from the session,
      // which is otherwise only refreshed at login).
      if (widget.field == 'inventory_enabled') {
        await updateInventoryEnabled(value);
        await ref.read(sessionProvider.notifier).refresh();
      } else if (widget.field == 'has_barcode_scanner') {
        await updateHasBarcodeScanner(value);
        await ref.read(sessionProvider.notifier).refresh();
      } else if (widget.field == 'gst_enabled') {
        await updateGstEnabled(value);
        await ref.read(sessionProvider.notifier).refresh();
      } else if (widget.field == 'round_off_enabled') {
        await updateRoundOffEnabled(value);
        await ref.read(sessionProvider.notifier).refresh();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _enabled = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: SwitchListTile(
        value: _enabled ?? false,
        // GST without a GSTIN is blocked: turning it on is disabled, but turning
        // it OFF stays allowed so a business that somehow has it on can escape.
        onChanged: (_enabled == null || _saving)
            ? null
            : (v) {
                if (v && _needsGstin) {
                  _promptForGstin();
                  return;
                }
                _toggle(v);
              },
        secondary: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Icon(widget.icon, color: AppColors.primary, size: 20),
        ),
        title: Text(widget.title),
        subtitle: Text(
          _needsGstin && !(_enabled ?? false)
              ? context.l10n.settingsGstNeedsGstin
              : widget.subtitle,
          style: _needsGstin && !(_enabled ?? false)
              ? const TextStyle(color: AppColors.warning)
              : null,
        ),
      ),
    );
  }

  /// Explain why GST can't be enabled yet and offer to open Business Profile,
  /// where the GSTIN is entered. Re-checks on return so the switch unlocks
  /// straight away once a GSTIN is saved.
  Future<void> _promptForGstin() async {
    final l10n = context.l10n;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsGstNeedsGstinTitle),
        content: Text(l10n.settingsGstNeedsGstinMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.settingsGstAddGstin),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BusinessProfileScreen()),
    );
    if (mounted) await _load();
  }
}

