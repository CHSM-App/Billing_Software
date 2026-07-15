import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../providers/tables_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Overrides the four cart providers with fresh instances so each billing
/// panel has its own completely independent cart state.
List<Override> _cartOverrides() => [
      cartProvider.overrideWith(CartNotifier.new),
      cartSubtotalProvider.overrideWith(
        (ref) => ref.watch(cartProvider).fold(
            0.0, (s, e) => s + e.item.price * e.quantity),
      ),
      cartTaxProvider.overrideWith(
        (ref) => ref.watch(cartProvider).fold(0.0, (s, e) {
          if (e.item.taxRate == null) return s;
          return s + e.item.price * e.quantity * (e.item.taxRate! / 100);
        }),
      ),
      cartTotalProvider.overrideWith(
        (ref) =>
            ref.watch(cartSubtotalProvider) + ref.watch(cartTaxProvider),
      ),
      cartItemCountProvider.overrideWith(
        (ref) =>
            ref.watch(cartProvider).fold(0, (s, e) => s + e.quantity),
      ),
    ];

/// Shows two billing panels side by side on wide screens.
/// Each panel has its own isolated cart via a nested [ProviderScope].
class SplitBillingScreen extends ConsumerStatefulWidget {
  final TableModel leftTable;
  final TableModel? rightTable;

  const SplitBillingScreen({
    super.key,
    required this.leftTable,
    this.rightTable,
  });

  @override
  ConsumerState<SplitBillingScreen> createState() =>
      _SplitBillingScreenState();
}

class _SplitBillingScreenState extends ConsumerState<SplitBillingScreen> {
  late TableModel? _rightTable;

  @override
  void initState() {
    super.initState();
    _rightTable = widget.rightTable;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left panel — always present
          Expanded(
            child: ProviderScope(
              overrides: _cartOverrides(),
              child: HomeScreen(
                tableId: widget.leftTable.id,
                tableNumber: widget.leftTable.tableNumber,
                activeBillId: widget.leftTable.activeBillId,
                onBillDone: () => Navigator.pop(context),
              ),
            ),
          ),

          Container(width: 1, color: AppColors.border),

          // Right panel — table selector or active billing
          Expanded(
            child: _rightTable == null
                ? _TablePickerPanel(
                    excludeTableId: widget.leftTable.id,
                    onTableSelected: (t) =>
                        setState(() => _rightTable = t),
                  )
                : ProviderScope(
                    overrides: _cartOverrides(),
                    child: HomeScreen(
                      tableId: _rightTable!.id,
                      tableNumber: _rightTable!.tableNumber,
                      activeBillId: _rightTable!.activeBillId,
                      onBillDone: () => setState(() => _rightTable = null),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table picker shown in the right panel when no table is selected yet
// ---------------------------------------------------------------------------

class _TablePickerPanel extends ConsumerWidget {
  final String excludeTableId;
  final void Function(TableModel) onTableSelected;

  const _TablePickerPanel({
    required this.excludeTableId,
    required this.onTableSelected,
  });

  /// Human-readable label for a table's status. The raw values ('empty',
  /// 'occupied', 'billed') stay untranslated — they are API values.
  String _statusLabel(AppLocalizations l10n, String status) => switch (status) {
        'occupied' => l10n.tablesOccupied,
        'billed' => l10n.tablesBilled,
        _ => l10n.tablesEmpty,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tablesAsync = ref.watch(tablesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.splitSelectSecondTable,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Text(
              l10n.commonErrorWithMessage(e.toString()),
              textAlign: TextAlign.center,
              style: AppFont.style(color: AppColors.textSecondary),
            ),
          ),
        ),
        data: (tables) {
          final available = tables
              .where((t) =>
                  t.id != excludeTableId && t.status != 'billed')
              .toList();

          if (available.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.table_restaurant_outlined,
                        size: 48, color: AppColors.textDisabled),
                    const SizedBox(height: AppSpacing.space16),
                    Text(
                      l10n.splitNoOtherTables,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.space16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: AppSpacing.space12,
              crossAxisSpacing: AppSpacing.space12,
              childAspectRatio: 1,
            ),
            itemCount: available.length,
            itemBuilder: (_, i) {
              final t = available[i];
              final color = switch (t.status) {
                'occupied' => AppColors.tableOccupied,
                _ => AppColors.tableEmpty,
              };
              return GestureDetector(
                onTap: () => onTableSelected(t),
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(color: color, width: 2),
                    borderRadius:
                        BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          t.tableNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.style(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _statusLabel(l10n, t.status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppFont.style(fontSize: 11, color: color),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
