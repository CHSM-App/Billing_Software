import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers.dart';
import '../api.dart' as api;
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

final _fmt = NumberFormat('#,##0.00');
final _dateFmt = DateFormat('dd MMM yyyy');

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
          ShellAppBar(
            title: const Text('Expenses'),
            bottom: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'This Month'),
                Tab(text: 'Recurring'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _ThisMonthTab(onSwitchToRecurring: () => _tabCtrl.animateTo(1)),
                const _RecurringTab(),
              ],
            ),
          ),
        ]),
    );
  }
}

// ---------------------------------------------------------------------------
// This Month tab
// ---------------------------------------------------------------------------

class _ThisMonthTab extends ConsumerWidget {
  final VoidCallback onSwitchToRecurring;

  const _ThisMonthTab({required this.onSwitchToRecurring});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(expenseFilterProvider);
    final expensesAsync = ref.watch(expensesProvider);
    final recurringAsync = ref.watch(recurringExpensesProvider);

    // Check if any recurring expenses haven't been added this month yet
    final thisMonthExpenses = expensesAsync.valueOrNull ?? [];
    final recurring = recurringAsync.valueOrNull ?? [];
    final pendingRecurring = recurring.where((r) {
      return !thisMonthExpenses.any((e) =>
          e.category == r.category &&
          e.expenseDate.year == filter.from.year &&
          e.expenseDate.month == filter.from.month);
    }).toList();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Filter bar
        SliverToBoxAdapter(
          child: _buildFilterBar(context, ref, filter, expensesAsync),
        ),

        // Recurring reminder banner
        if (pendingRecurring.isNotEmpty)
          SliverToBoxAdapter(
            child: _RecurringBanner(
              pending: pendingRecurring,
              filter: filter,
              onAdded: () => ref.invalidate(expensesProvider),
              onManage: onSwitchToRecurring,
            ),
          ),

        // Expenses list
        expensesAsync.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: AppErrorWidget(
              error: e,
              onRetry: () => ref.invalidate(expensesProvider),
            ),
          ),
          data: (expenses) => expenses.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'No expenses this month.\nTap + to add one.',
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: expenses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _ExpenseCard(
                      expense: expenses[i],
                      onChanged: () => ref.invalidate(expensesProvider),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context, WidgetRef ref,
      ExpenseFilter filter, AsyncValue<List<Expense>> expensesAsync) {
    final total = expensesAsync.valueOrNull?.fold(0.0, (s, e) => s + e.amount) ?? 0;
    final now = DateTime.now();
    final isCurrentMonth =
        filter.from.year == now.year && filter.from.month == now.month;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Prev month
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              final prev = DateTime(filter.from.year, filter.from.month - 1, 1);
              ref.read(expenseFilterProvider.notifier).state = ExpenseFilter(
                from: prev,
                to: DateTime(prev.year, prev.month + 1, 0),
              );
            },
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(filter.from),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Rs. ${_fmt.format(total)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error,
                      fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          // Next month (disabled if current month)
          IconButton(
            icon: Icon(Icons.chevron_right, size: 20,
                color: isCurrentMonth ? AppColors.textDisabled : null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: isCurrentMonth
                ? null
                : () {
                    final next = DateTime(filter.from.year, filter.from.month + 1, 1);
                    ref.read(expenseFilterProvider.notifier).state = ExpenseFilter(
                      from: next,
                      to: DateTime(next.year, next.month + 1, 0),
                    );
                  },
          ),
          // Add button
          FloatingActionButton.small(
            heroTag: 'addExpense',
            onPressed: () => _showAddSheet(context, ref),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            child: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseForm(
        onSaved: () => ref.invalidate(expensesProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recurring reminder banner
// ---------------------------------------------------------------------------

class _RecurringBanner extends ConsumerWidget {
  final List<RecurringExpense> pending;
  final ExpenseFilter filter;
  final VoidCallback onAdded;
  final VoidCallback onManage;

  const _RecurringBanner({
    required this.pending,
    required this.filter,
    required this.onAdded,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.repeat_rounded, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${pending.length} recurring expense${pending.length > 1 ? 's' : ''} not yet added this month',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // List pending items
          ...pending.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 24),
                    Expanded(
                      child: Text(
                        '${r.category}${r.description != null ? ' – ${r.description}' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    Text(
                      'Rs. ${_fmt.format(r.amount)}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onManage,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: AppColors.warning),
                    foregroundColor: AppColors.warning,
                  ),
                  child: const Text('Manage', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _addAll(context, ref),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add All to This Month',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addAll(BuildContext context, WidgetRef ref) async {
    final today = DateTime.now();
    // Use last day of selected month if today is beyond it, else today
    final expDate = today.year == filter.from.year && today.month == filter.from.month
        ? today
        : DateTime(filter.from.year, filter.from.month + 1, 0);
    final dateStr =
        '${expDate.year}-${expDate.month.toString().padLeft(2, '0')}-${expDate.day.toString().padLeft(2, '0')}';

    try {
      for (final r in pending) {
        await api.createExpense({
          'category': r.category,
          'description': r.description,
          'amount': r.amount,
          'payment_mode': r.paymentMode,
          'expense_date': dateStr,
        });
      }
      onAdded();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${pending.length} recurring expense${pending.length > 1 ? 's' : ''} added')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Recurring tab — manage recurring expenses
// ---------------------------------------------------------------------------

class _RecurringTab extends ConsumerWidget {
  const _RecurringTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurringAsync = ref.watch(recurringExpensesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: recurringAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(
          error: e,
          onRetry: () => ref.invalidate(recurringExpensesProvider),
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.repeat_rounded,
                message:
                    'No recurring expenses yet.\nAdd expenses that repeat every month\n(e.g. Rent, Salary).',
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) =>
                    _RecurringCard(recurring: list[i], ref: ref),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addRecurring',
        onPressed: () => _showForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Recurring'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, {RecurringExpense? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecurringForm(
        item: item,
        onSaved: () => ref.invalidate(recurringExpensesProvider),
      ),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  final RecurringExpense recurring;
  final WidgetRef ref;

  const _RecurringCard({required this.recurring, required this.ref});

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(recurring.category);
    return AppCard(
      onTap: () => _showOptions(context),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Center(
              child: Icon(Icons.repeat_rounded, color: color, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recurring.category,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (recurring.description != null && recurring.description!.isNotEmpty)
                  Text(recurring.description!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Icon(_paymentIcon(recurring.paymentMode),
                        size: 12, color: AppColors.textDisabled),
                    const SizedBox(width: 4),
                    Text(recurring.paymentMode.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textDisabled)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Monthly',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Rs. ${_fmt.format(recurring.amount)}',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.primary),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _RecurringForm(
                      item: recurring,
                      onSaved: () => ref.invalidate(recurringExpensesProvider),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Delete',
                    style: TextStyle(color: AppColors.error)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Remove Recurring Expense?'),
                      content: Text(
                          'Remove "${recurring.category}" from recurring list? This won\'t delete past entries.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Remove',
                                style: TextStyle(color: AppColors.error))),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    try {
                      await api.deleteRecurringExpense(recurring.id);
                      ref.invalidate(recurringExpensesProvider);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')));
                      }
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Color _categoryColor(String cat) {
    const colors = [
      Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFDB2777),
      Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF059669),
      Color(0xFF0891B2),
    ];
    return colors[cat.hashCode.abs() % colors.length];
  }

  IconData _paymentIcon(String mode) {
    switch (mode) {
      case 'upi': return Icons.qr_code_outlined;
      case 'card': return Icons.credit_card_outlined;
      case 'other': return Icons.more_horiz;
      default: return Icons.money_outlined;
    }
  }
}

// ---------------------------------------------------------------------------
// Recurring expense form
// ---------------------------------------------------------------------------

class _RecurringForm extends ConsumerStatefulWidget {
  final RecurringExpense? item;
  final VoidCallback onSaved;

  const _RecurringForm({this.item, required this.onSaved});

  @override
  ConsumerState<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<_RecurringForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late String _category;
  late String _paymentMode;
  bool _saving = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final e = widget.item;
    _amountCtrl = TextEditingController(
        text: e != null ? e.amount.toStringAsFixed(2) : '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _category = e?.category ?? kDefaultExpenseCategories.first;
    _paymentMode = e?.paymentMode ?? 'cash';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? kDefaultExpenseCategories;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.repeat_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isEdit ? 'Edit Recurring Expense' : 'Add Recurring Expense',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'These appear every month as a reminder.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // Category
              const Text('Category',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...categories.map((cat) => _CategoryChip(
                        label: cat,
                        selected: _category == cat,
                        onTap: () => setState(() => _category = cat),
                      )),
                  _CategoryChip(
                    label: '+ Custom',
                    selected: false,
                    onTap: () => _showCustomDialog(context),
                    color: AppColors.accent,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs.)',
                  prefixIcon: Icon(Icons.currency_rupee_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Amount is required';
                  if (double.tryParse(v) == null || double.parse(v) <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Description
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // Payment mode
              const Text('Payment Mode',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: ['cash', 'upi', 'card', 'other'].map((mode) {
                  final selected = _paymentMode == mode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(mode.toUpperCase()),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _paymentMode = mode),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: _saving
                      ? 'Saving…'
                      : (_isEdit ? 'Update' : 'Save Recurring Expense'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Insurance'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _category = result);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'category': _category,
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'amount': double.parse(_amountCtrl.text),
        'payment_mode': _paymentMode,
      };
      if (_isEdit) {
        await api.updateRecurringExpense(widget.item!.id, data);
      } else {
        await api.createRecurringExpense(data);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Expense card (This Month tab)
// ---------------------------------------------------------------------------

class _ExpenseCard extends ConsumerWidget {
  final Expense expense;
  final VoidCallback onChanged;

  const _ExpenseCard({required this.expense, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryColor = _categoryColor(expense.category);
    return AppCard(
      onTap: () => _showOptions(context),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Center(
              child: Text(
                expense.category.isNotEmpty
                    ? expense.category[0].toUpperCase()
                    : 'E',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: categoryColor),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.category,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (expense.description != null &&
                    expense.description!.isNotEmpty)
                  Text(expense.description!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(_paymentIcon(expense.paymentMode),
                        size: 12, color: AppColors.textDisabled),
                    const SizedBox(width: 4),
                    Text(expense.paymentMode.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textDisabled)),
                    const SizedBox(width: 8),
                    Text(_dateFmt.format(expense.expenseDate),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textDisabled)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Rs. ${_fmt.format(expense.amount)}',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.error),
          ),
        ],
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading:
                    const Icon(Icons.edit_outlined, color: AppColors.primary),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) =>
                        _ExpenseForm(expense: expense, onSaved: onChanged),
                  );
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Delete',
                    style: TextStyle(color: AppColors.error)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete Expense?'),
                      content: Text(
                          'Delete ${expense.category} of Rs. ${_fmt.format(expense.amount)}?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete',
                                style: TextStyle(color: AppColors.error))),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    try {
                      await api.deleteExpense(expense.id);
                      onChanged();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')));
                      }
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Color _categoryColor(String cat) {
    const colors = [
      Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFDB2777),
      Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF059669),
      Color(0xFF0891B2),
    ];
    return colors[cat.hashCode.abs() % colors.length];
  }

  IconData _paymentIcon(String mode) {
    switch (mode) {
      case 'upi': return Icons.qr_code_outlined;
      case 'card': return Icons.credit_card_outlined;
      case 'other': return Icons.more_horiz;
      default: return Icons.money_outlined;
    }
  }
}

// ---------------------------------------------------------------------------
// Add / Edit expense form (This Month)
// ---------------------------------------------------------------------------

class _ExpenseForm extends ConsumerStatefulWidget {
  final Expense? expense;
  final VoidCallback onSaved;

  const _ExpenseForm({this.expense, required this.onSaved});

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late String _category;
  late String _paymentMode;
  late DateTime _expenseDate;
  bool _saving = false;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amountCtrl = TextEditingController(
        text: e != null ? e.amount.toStringAsFixed(2) : '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _category = e?.category ?? kDefaultExpenseCategories.first;
    _paymentMode = e?.paymentMode ?? 'cash';
    _expenseDate = e?.expenseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? kDefaultExpenseCategories;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text(_isEdit ? 'Edit Expense' : 'Add Expense',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 20),

              // Category
              const Text('Category',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...categories.map((cat) => _CategoryChip(
                        label: cat,
                        selected: _category == cat,
                        onTap: () => setState(() => _category = cat),
                      )),
                  _CategoryChip(
                    label: '+ Custom',
                    selected: false,
                    onTap: () => _showCustomCategoryDialog(context),
                    color: AppColors.accent,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs.)',
                  prefixIcon: Icon(Icons.currency_rupee_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Amount is required';
                  if (double.tryParse(v) == null || double.parse(v) <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),

              const Text('Payment Mode',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: ['cash', 'upi', 'card', 'other'].map((mode) {
                  final selected = _paymentMode == mode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(mode.toUpperCase()),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _paymentMode = mode),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: () => _pickDate(context),
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Text(_dateFmt.format(_expenseDate),
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary)),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textDisabled),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: _saving
                      ? 'Saving…'
                      : (_isEdit ? 'Update Expense' : 'Add Expense'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expenseDate = picked);
  }

  Future<void> _showCustomCategoryDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Insurance'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _category = result);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'category': _category,
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'amount': double.parse(_amountCtrl.text),
        'payment_mode': _paymentMode,
        'expense_date':
            '${_expenseDate.year}-${_expenseDate.month.toString().padLeft(2, '0')}-${_expenseDate.day.toString().padLeft(2, '0')}',
      };
      if (_isEdit) {
        await api.updateExpense(widget.expense!.id, data);
      } else {
        await api.createExpense(data);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Category chip
// ---------------------------------------------------------------------------

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.12) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(
              color: selected ? c : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? c : AppColors.textSecondary)),
      ),
    );
  }
}
