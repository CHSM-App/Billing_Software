import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);
    try {
      final data = await getStaff();
      setState(() {
        _staff = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // Read l10n here (not at the top): _loadStaff is called from initState,
      // where the InheritedWidget lookup for context.l10n isn't safe yet.
      _showSnack(context.l10n.staffLoadFailed('$e'), isError: true);
    }
  }

  void _showStaffForm({Map<String, dynamic>? member, String? initialRole}) {
    final businessType = ref.read(businessTypeProvider);
    final allowKitchen = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
    showDialog(
      context: context,
      builder: (_) => _StaffFormDialog(
        member: member,
        allowKitchen: allowKitchen,
        initialRole: initialRole,
        onSaved: _loadStaff,
      ),
    );
  }

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.staffRemoveTitle),
        content: Text(l10n.staffRemoveBody('${member['name']}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonRemove,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await deleteStaff(member['id']);
      _loadStaff();
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.staffTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  message: l10n.staffNoCashiers,
                  actionLabel: l10n.staffAddStaff,
                  onAction: () => _showStaffForm(),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  itemCount: _staff.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space8),
                  itemBuilder: (_, i) {
                    final m = _staff[i];
                    return AppCard(
                      onTap: () => _showStaffForm(member: m),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.primaryLight,
                            child: Text(
                              (m['name'] as String).substring(0, 1).toUpperCase(),
                              style: AppFont.style(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(m['name'],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                    ),
                                    const SizedBox(width: AppSpacing.space8),
                                    _RoleBadge(role: m['role'] ?? 'cashier'),
                                  ],
                                ),
                                Text(m['phone'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.error, size: 20),
                            onPressed: () => _deleteMember(m),
                            visualDensity: VisualDensity.compact,
                            tooltip: l10n.commonRemove,
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_allowKitchen) ...[
            FloatingActionButton.extended(
              heroTag: 'add_kitchen',
              onPressed: () => _showStaffForm(initialRole: 'kitchen'),
              icon: const Icon(Icons.restaurant_menu_outlined),
              label: Text(l10n.staffAddKitchen),
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.space12),
          ],
          FloatingActionButton.extended(
            heroTag: 'add_staff',
            onPressed: () => _showStaffForm(),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(l10n.staffAddStaff),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }

  bool get _allowKitchen {
    final businessType = ref.read(businessTypeProvider);
    return businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
  }
}

/// Small colored pill showing a staff member's role (Waiter / Kitchen Chef).
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isKitchen = role == 'kitchen';
    final label = isKitchen ? l10n.staffRoleKitchen : l10n.staffRoleWaiter;
    final color = isKitchen ? AppColors.warning : AppColors.primary;
    final bg = isKitchen ? AppColors.warningLight : AppColors.primaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StaffFormDialog extends StatefulWidget {
  final Map<String, dynamic>? member;
  final bool allowKitchen;
  final String? initialRole;
  final VoidCallback onSaved;

  const _StaffFormDialog({
    this.member,
    this.allowKitchen = false,
    this.initialRole,
    required this.onSaved,
  });

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _role = 'cashier';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    if (m != null) {
      _nameCtrl.text = m['name'] ?? '';
      _phoneCtrl.text = m['phone'] ?? '';
      _role = (m['role'] as String?) ?? 'cashier';
    } else if (widget.initialRole != null) {
      _role = widget.initialRole!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final isEdit = widget.member != null;
    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'role': _role,
      if (_pinCtrl.text.trim().isNotEmpty) 'pin': _pinCtrl.text.trim(),
      if (!isEdit) 'pin': _pinCtrl.text.trim(),
    };

    try {
      if (isEdit) {
        await updateStaff(widget.member!['id'], data);
      } else {
        await createStaff(data);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.member != null;
    return AlertDialog(
      title: Text(isEdit ? l10n.staffEditStaff : l10n.staffAddStaff),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.allowKitchen) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.staffRole,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: AppSpacing.space8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'cashier', label: Text(l10n.staffRoleWaiter)),
                    ButtonSegment(
                        value: 'kitchen', label: Text(l10n.staffRoleKitchen)),
                  ],
                  selected: {_role == 'kitchen' ? 'kitchen' : 'cashier'},
                  onSelectionChanged: (s) =>
                      setState(() => _role = s.first),
                ),
                const SizedBox(height: AppSpacing.space12),
              ],
              AppTextField(
                label: l10n.staffName,
                controller: _nameCtrl,
                validator: (v) =>
                    v == null || v.isEmpty ? l10n.commonRequired : null,
              ),
              const SizedBox(height: AppSpacing.space12),
              AppTextField(
                label: l10n.staffPhone,
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.commonRequired;
                  if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                    return l10n.staffPhoneInvalid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.space12),
              AppTextField(
                label: isEdit ? l10n.staffPinNew : l10n.staffPinNewLabel,
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                validator: (v) {
                  if (!isEdit && (v == null || v.isEmpty)) {
                    return l10n.commonRequired;
                  }
                  if (v != null && v.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(v)) {
                    return l10n.staffPinInvalid;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel)),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEdit ? l10n.commonSave : l10n.commonAdd),
        ),
      ],
    );
  }
}
