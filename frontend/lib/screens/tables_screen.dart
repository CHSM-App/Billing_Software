import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  // Track drag offset per table id (purely local UI state)
  final Map<String, Offset> _dragOffsets = {};

  Color _tableColor(String status) {
    return switch (status) {
      'occupied' => AppColors.tableOccupied,
      'billed' => AppColors.tableBilled,
      _ => AppColors.tableEmpty,
    };
  }

  void _onTableTap(TableModel table) async {
    final userRole = ref.read(userRoleProvider);
    if (table.status == 'empty') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            tableId: table.id,
            tableNumber: table.tableNumber,
          ),
        ),
      );
      ref.invalidate(tablesProvider);
    } else if (table.status == 'occupied') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            tableId: table.id,
            tableNumber: table.tableNumber,
            activeBillId: table.activeBillId,
          ),
        ),
      );
      ref.invalidate(tablesProvider);
    } else if (table.status == 'billed') {
      _showBilledOptions(table, userRole);
    }
  }

  void _showBilledOptions(TableModel table, String userRole) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Table ${table.tableNumber}'),
        content: const Text(
            'This table has a billed order. What would you like to do?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _markTableEmpty(table);
            },
            child: const Text('Mark as Paid / Empty'),
          ),
          if (table.activeBillId != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _voidTableBill(table);
              },
              child: Text('Void Bill', style: TextStyle(color: AppColors.error)),
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
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Table'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(labelText: 'Table number (e.g. T1, A2)'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Table'),
        content: Text('Delete table "${table.tableNumber}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
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
    final userRole = ref.watch(userRoleProvider);
    final tablesAsync = ref.watch(tablesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tables'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.invalidate(tablesProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(tablesProvider);
            await ref.read(tablesProvider.future);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space32),
                child: Text(e.toString(),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.error)),
              ),
            ),
          ),
        ),
        data: (tables) {
          if (tables.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(tablesProvider);
                await ref.read(tablesProvider.future);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: AppSpacing.space48),
                      const Icon(Icons.table_restaurant_outlined,
                          size: 48, color: AppColors.textDisabled),
                      const SizedBox(height: AppSpacing.space16),
                      Text('No tables yet',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
                      if (userRole == 'owner') ...[
                        const SizedBox(height: AppSpacing.space16),
                        ElevatedButton.icon(
                          onPressed: _addTable,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Table'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(tablesProvider);
              await ref.read(tablesProvider.future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                    child: _buildCanvas(tables, userRole)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: userRole == 'owner'
          ? FloatingActionButton.extended(
              onPressed: _addTable,
              icon: const Icon(Icons.add),
              label: const Text('Add Table'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildCanvas(List<TableModel> tables, String userRole) {
    return Stack(
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
    );
  }
}

class _TableWidget extends StatelessWidget {
  final TableModel table;
  final Color color;

  const _TableWidget({required this.table, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          Text(table.status, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}
