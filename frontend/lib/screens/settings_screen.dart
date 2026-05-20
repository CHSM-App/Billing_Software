import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'login_screen.dart';
import 'printer_setup_screen.dart';
import 'staff_screen.dart';

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
      data: (session) => _buildContent(context, ref, session),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, session) {
    final isOwner = session.userRole == 'owner';

    Future<void> logout() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref.read(sessionProvider.notifier).clear();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space16),
          children: [
            // Business info
            _sectionHeader(context, 'Business'),
            const SizedBox(height: AppSpacing.space8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(context, 'Name', session.businessName),
                  const Divider(height: AppSpacing.space24),
                  _infoRow(context, 'Type', _formatType(session.businessType)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space24),

            // User info
            _sectionHeader(context, 'Account'),
            const SizedBox(height: AppSpacing.space8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(context, 'Name', session.userName),
                  const Divider(height: AppSpacing.space24),
                  _infoRow(context, 'Role', session.userRole.toUpperCase()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space24),

            // Staff management (owner only)
            if (isOwner) ...[
              _sectionHeader(context, 'Team'),
              const SizedBox(height: AppSpacing.space8),
              AppCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffScreen()),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: AppSpacing.space12),
                    Expanded(
                      child: Text('Manage Staff',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const Icon(Icons.chevron_right_outlined,
                        color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space24),
            ],

            // Printer setup
            _sectionHeader(context, 'Printer'),
            const SizedBox(height: AppSpacing.space8),
            AppCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
              ),
              child: Row(
                children: [
                  const Icon(Icons.print_outlined,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: AppSpacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Printer Setup',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('Configure thermal printer',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_outlined,
                      color: AppColors.textSecondary, size: 20),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space48),

            DestructiveButton(text: 'Logout', onPressed: logout),
            const SizedBox(height: AppSpacing.space32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: AppColors.textSecondary, letterSpacing: 0.8),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
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
