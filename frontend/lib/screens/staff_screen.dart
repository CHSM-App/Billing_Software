import 'package:flutter/material.dart';
import '../api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
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
      setState(() => _loading = false);
      _showSnack('Failed to load staff: $e', isError: true);
    }
  }

  void _showStaffForm({Map<String, dynamic>? member}) {
    showDialog(
      context: context,
      builder: (_) => _StaffFormDialog(
        member: member,
        onSaved: _loadStaff,
      ),
    );
  }

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text('Remove "${member['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove', style: TextStyle(color: AppColors.error)),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Staff')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  message: 'No cashiers added yet.',
                  actionLabel: 'Add Staff',
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
                              style: const TextStyle(
                                  color: AppColors.primary, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['name'],
                                    style: Theme.of(context).textTheme.titleMedium),
                                Text(m['phone'],
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
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showStaffForm(),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Staff'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _StaffFormDialog extends StatefulWidget {
  final Map<String, dynamic>? member;
  final VoidCallback onSaved;

  const _StaffFormDialog({this.member, required this.onSaved});

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    if (m != null) {
      _nameCtrl.text = m['name'] ?? '';
      _phoneCtrl.text = m['phone'] ?? '';
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
    final isEdit = widget.member != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Staff' : 'Add Staff'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Name',
                controller: _nameCtrl,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.space12),
              AppTextField(
                label: 'Phone',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^\d{10}$').hasMatch(v)) return '10-digit number required';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.space12),
              AppTextField(
                label: isEdit ? 'New PIN (leave blank to keep)' : 'PIN (4 digits)',
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                validator: (v) {
                  if (!isEdit && (v == null || v.isEmpty)) return 'Required';
                  if (v != null && v.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(v)) {
                    return 'PIN must be 4 digits';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
