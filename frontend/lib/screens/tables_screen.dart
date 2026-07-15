import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import 'home_screen.dart';

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  final Map<String, Offset> _dragOffsets = {};

  Color _tableColor(String status) {
    return switch (status) {
      'occupied' => AppColors.tableOccupied,
      'billed' => AppColors.tableBilled,
      _ => AppColors.tableEmpty,
    };
  }

  /// Maps the raw API status value to a localized display label.
  static String tableStatusLabel(AppLocalizations l10n, String status) {
    return switch (status) {
      'occupied' => l10n.tablesOccupied,
      'billed' => l10n.tablesBilled,
      _ => l10n.tablesEmpty,
    };
  }

  void _onTableTap(TableModel table) async {
    final userRole = ref.read(userRoleProvider);

    if (table.status == 'billed') {
      _showBilledOptions(table, userRole);
      return;
    }
    if (table.status == 'empty' || table.status == 'occupied') {
      if (table.activeBillId == null) {
        ref.read(cartProvider.notifier).clear();
      }

      // Retrieve from cache — populated when tables were last fetched.
      final cachedBill = ref
          .read(tablesProvider.notifier)
          .cachedBill(table.activeBillId);

      await Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 120),
          reverseTransitionDuration: const Duration(milliseconds: 120),
          pageBuilder: (_, __, ___) => HomeScreen(
            tableId: table.id,
            tableNumber: table.tableNumber,
            activeBillId: table.activeBillId,
            activeBillFuture: cachedBill != null
                ? Future.value(cachedBill)
                : table.activeBillId != null
                    ? getBill(table.activeBillId!)
                        .then<Bill?>((d) => Bill.fromJson(d))
                        .catchError((_) => null)
                    : null,
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      ref.invalidate(tablesProvider);
    }
  }

  void _showBilledOptions(TableModel table, String userRole) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.tablesTableLabel(table.tableNumber)),
        content: Text(l10n.tablesBilledOrderBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _markTableEmpty(table);
            },
            child: Text(l10n.tablesMarkPaidEmpty),
          ),
          if (table.activeBillId != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _voidTableBill(table);
              },
              child: Text(l10n.tablesVoidBill,
                  style: const TextStyle(color: AppColors.error)),
            ),
        ],
      ),
    );
  }

  Future<void> _markTableEmpty(TableModel table) async {
    try {
      await ref.read(tablesProvider.notifier).updateStatus(table.id, 'empty');
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _voidTableBill(TableModel table) async {
    if (table.activeBillId == null) return;
    try {
      await voidBill(table.activeBillId!);
      ref.invalidate(tablesProvider);
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _addTable() async {
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.tablesAddTable),
        content: TextField(
          controller: ctrl,
          decoration:
              InputDecoration(labelText: l10n.tablesTableNumberLabel),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonAdd),
          ),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty || !mounted) return;
    try {
      await ref.read(tablesProvider.notifier).addTable({
        'table_number': ctrl.text.trim(),
        'floor_x': 100.0,
        'floor_y': 100.0,
      });
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _deleteTable(TableModel table) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.tablesDeleteTitle),
        content: Text(l10n.tablesDeleteBody(table.tableNumber)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonDelete,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(tablesProvider.notifier).removeTable(table.id);
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
    final userRole = ref.watch(userRoleProvider);
    final tablesAsync = ref.watch(tablesProvider);

    return Scaffold(
      body: Column(children: [
        ShellAppBar(
          title: Text(l10n.tablesTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () => ref.invalidate(tablesProvider),
              tooltip: l10n.commonRefresh,
            ),
          ],
        ),
        Expanded(child: tablesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorWidget(
            error: e,
            onRetry: () => ref.invalidate(tablesProvider),
          ),
          data: (tables) {
            if (tables.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.table_restaurant_outlined,
                        size: 48, color: AppColors.textDisabled),
                    const SizedBox(height: AppSpacing.space16),
                    Text(l10n.tablesNoTablesYet,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary)),
                    if (userRole == 'owner') ...[
                      const SizedBox(height: AppSpacing.space16),
                      ElevatedButton.icon(
                        onPressed: _addTable,
                        icon: const Icon(Icons.add),
                        label: Text(l10n.tablesAddTable),
                      ),
                    ],
                  ],
                ),
              );
            }

            return _buildCanvas(tables, userRole);
          },
        )),
      ]),
      floatingActionButton: userRole == 'owner'
          ? FloatingActionButton.extended(
              onPressed: _addTable,
              icon: const Icon(Icons.add),
              label: Text(l10n.tablesAddTable),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildCanvas(List<TableModel> tables, String userRole) {
    // Compute canvas size to fit all tables with padding.
    double maxX = 600;
    double maxY = 600;
    for (final t in tables) {
      final ox = (_dragOffsets[t.id] ?? Offset(t.floorX, t.floorY));
      if (ox.dx + 100 > maxX) maxX = ox.dx + 100;
      if (ox.dy + 100 > maxY) maxY = ox.dy + 100;
    }

    return InteractiveViewer(
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.5,
      maxScale: 2.0,
      constrained: false,
      child: SizedBox(
        width: maxX,
        height: maxY,
        child: Stack(
          children: tables.map((table) {
        final offset =
            _dragOffsets[table.id] ?? Offset(table.floorX, table.floorY);
        final color = _tableColor(table.status);

        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: GestureDetector(
            onTap: () => _onTableTap(table),
            onLongPress: userRole == 'owner' ? () => _deleteTable(table) : null,
            onPanUpdate: userRole == 'owner'
                ? (details) {
                    setState(() {
                      final current = _dragOffsets[table.id] ??
                          Offset(table.floorX, table.floorY);
                      _dragOffsets[table.id] = current + details.delta;
                    });
                  }
                : null,
            onPanEnd: userRole == 'owner'
                ? (_) async {
                    final newOffset = _dragOffsets[table.id];
                    if (newOffset == null) return;
                    try {
                      await ref.read(tablesProvider.notifier).updatePosition(
                            table.id,
                            newOffset.dx,
                            newOffset.dy,
                          );
                    } catch (_) {}
                  }
                : null,
            child: _TableWidget(table: table, color: color),
          ),
        );
      }).toList(),
        ),
      ),
    );
  }
}

class _TableWidget extends StatelessWidget {
  final TableModel table;
  final Color color;

  const _TableWidget({required this.table, required this.color});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: 80,
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            table.tableNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFont.style(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _TablesScreenState.tableStatusLabel(l10n, table.status),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppFont.style(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}
