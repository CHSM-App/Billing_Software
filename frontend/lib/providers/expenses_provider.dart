import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------

class ExpenseFilter {
  final DateTime from;
  final DateTime to;
  final String? category;

  const ExpenseFilter({required this.from, required this.to, this.category});

  ExpenseFilter copyWith({DateTime? from, DateTime? to, String? category, bool clearCategory = false}) =>
      ExpenseFilter(
        from: from ?? this.from,
        to: to ?? this.to,
        category: clearCategory ? null : (category ?? this.category),
      );

  String get fromStr => '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
  String get toStr => '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
}

// Default: current month
ExpenseFilter _defaultFilter() {
  final now = DateTime.now();
  return ExpenseFilter(
    from: DateTime(now.year, now.month, 1),
    to: DateTime(now.year, now.month + 1, 0),
  );
}

final expenseFilterProvider = StateProvider<ExpenseFilter>((ref) => _defaultFilter());

// ---------------------------------------------------------------------------
// Expenses list
// ---------------------------------------------------------------------------

final expensesProvider = FutureProvider.autoDispose<List<Expense>>((ref) async {
  final filter = ref.watch(expenseFilterProvider);
  final raw = await api.getExpenses(
    from: filter.fromStr,
    to: filter.toStr,
    category: filter.category,
  );
  return raw.map((e) => Expense.fromJson(e)).toList();
});

// ---------------------------------------------------------------------------
// Expense categories (used by this business so far, plus defaults)
// ---------------------------------------------------------------------------

const List<String> kDefaultExpenseCategories = [
  'Rent',
  'Salary',
  'Utilities',
  'Stock Purchase',
  'Transport',
  'Marketing',
  'Maintenance',
  'Taxes',
  'Other',
];

final expenseCategoriesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  try {
    final remote = await api.getExpenseCategories();
    final merged = {...kDefaultExpenseCategories, ...remote}.toList()..sort();
    return merged;
  } catch (_) {
    return kDefaultExpenseCategories;
  }
});

// ---------------------------------------------------------------------------
// Recurring expenses
// ---------------------------------------------------------------------------

final recurringExpensesProvider = FutureProvider.autoDispose<List<RecurringExpense>>((ref) async {
  final raw = await api.getRecurringExpenses();
  return raw.map((e) => RecurringExpense.fromJson(e)).toList();
});

// ---------------------------------------------------------------------------
// Report summary provider
// ---------------------------------------------------------------------------

class ReportSummaryFilter {
  final DateTime from;
  final DateTime to;

  const ReportSummaryFilter({required this.from, required this.to});

  ReportSummaryFilter copyWith({DateTime? from, DateTime? to}) =>
      ReportSummaryFilter(from: from ?? this.from, to: to ?? this.to);

  String get fromStr => '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
  String get toStr => '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
}

ReportSummaryFilter _defaultReportFilter() {
  final now = DateTime.now();
  return ReportSummaryFilter(
    from: DateTime(now.year, now.month, 1),
    to: DateTime(now.year, now.month + 1, 0),
  );
}

final reportSummaryFilterProvider =
    StateProvider<ReportSummaryFilter>((ref) => _defaultReportFilter());

final reportSummaryProvider = FutureProvider.autoDispose<ReportSummary>((ref) async {
  final filter = ref.watch(reportSummaryFilterProvider);
  final raw = await api.getReportSummary(from: filter.fromStr, to: filter.toStr);
  return ReportSummary.fromJson(raw);
});

/// Last-7-days net sales, independent of [reportSummaryFilterProvider] so the
/// chart always shows the real last week regardless of the selected period.
final weeklySalesProvider =
    FutureProvider.autoDispose<List<DailyReport>>((ref) async {
  final now = DateTime.now();
  final today =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final raw = await api.getWeeklySales(date: today);
  return (raw['days'] as List? ?? [])
      .map((d) => DailyReport.fromJson(d))
      .toList();
});
