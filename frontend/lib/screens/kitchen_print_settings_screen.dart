import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/printer_service.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Kitchen printing setup: the auto-print switch, which printer tickets go to,
/// and the roll width.
///
/// Separate from [PrinterSetupScreen] on purpose — that one configures the
/// counter printer that prints bills. A restaurant normally has a second
/// machine at the pass, and the two need independent settings. A shop with only
/// one printer can leave the printer here unset and tickets fall back to the
/// billing printer (see PrinterService.printKitchenTicket).
///
/// Strings are English-only, matching the other back-office setup screens.
class KitchenPrintSettingsScreen extends StatefulWidget {
  const KitchenPrintSettingsScreen({super.key});

  @override
  State<KitchenPrintSettingsScreen> createState() =>
      _KitchenPrintSettingsScreenState();
}

class _KitchenPrintSettingsScreenState
    extends State<KitchenPrintSettingsScreen> {
  bool _autoPrint = false;
  String _paperSize = PaperSizes.mm80;
  Printer? _kitchenPrinter;
  Printer? _billingPrinter;
  List<Printer> _found = [];
  bool _scanning = false;
  bool _testing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auto = await getKitchenAutoPrint();
    final size = await getKitchenPaperSize();
    final kitchen = await PrinterService.instance.getKitchenPrinter();
    final billing = await PrinterService.instance.getActivePrinter();
    if (!mounted) return;
    setState(() {
      _autoPrint = auto;
      _paperSize = size;
      _kitchenPrinter = kitchen;
      _billingPrinter = billing;
      _loading = false;
    });
  }

  Future<void> _setAutoPrint(bool on) async {
    setState(() => _autoPrint = on);
    await saveKitchenAutoPrint(on);
    // Turning it on with nothing to print to is the one combination that would
    // silently do nothing, so say so at the moment of the decision.
    if (on && _kitchenPrinter == null && _billingPrinter == null) {
      _snack('Auto-print is on, but no printer is connected yet.',
          isError: true);
    }
  }

  Future<void> _setPaperSize(String size) async {
    setState(() => _paperSize = size);
    await saveKitchenPaperSize(size);
  }

  Future<void> _scan() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      _snack('Bluetooth permission denied.', isError: true);
      return;
    }

    setState(() {
      _scanning = true;
      _found = [];
    });
    try {
      final found = await PrinterService.instance.listPrinters();
      if (!mounted) return;
      setState(() => _found = found);
      if (found.isEmpty) {
        _snack('No paired printers found. Pair it in system settings first.');
      }
    } catch (e) {
      _snack('Could not list printers: $e', isError: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _select(Printer p) async {
    await PrinterService.instance.setKitchenPrinter(p);
    if (!mounted) return;
    setState(() => _kitchenPrinter = p);
    _snack('Kitchen printer set to ${p.name ?? 'printer'}.');
  }

  Future<void> _clear() async {
    await PrinterService.instance.clearKitchenPrinter();
    if (!mounted) return;
    setState(() => _kitchenPrinter = null);
    _snack('Kitchen printer cleared.');
  }

  /// Prints a representative ticket so the layout, width and font size can be
  /// judged on the actual paper before a real order depends on it.
  Future<void> _testPrint() async {
    setState(() => _testing = true);
    try {
      await PrinterService.instance.printKitchenTicket(
        {
          'bill_number': 'INV-0000',
          'table_number': '5',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'items': [
            {'item_name': 'Cream of Mushroom Soup', 'quantity': 2},
            {'item_name': 'Paneer Butter Masala', 'quantity': 1},
            {'item_name': 'Butter Naan', 'quantity': 4, 'diner_name': 'Rahul'},
          ],
        },
        paperDots: PaperSizes.thermalDots(_paperSize),
        reprint: true,
      );
      _snack('Test ticket sent.');
    } on PrinterException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Could not print: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Only the kitchen printer is required to be set for the test button; if it
    // is not, the ticket still goes to the billing printer.
    final canPrint = _kitchenPrinter != null || _billingPrinter != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen printing')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.space16),
              children: [
                AppCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _autoPrint,
                    onChanged: _setAutoPrint,
                    title: const Text('Auto-print new orders',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Print a kitchen ticket by itself the moment an order '
                      'reaches this device. Only works while the Kitchen '
                      'screen is open.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.space24),
                _header('Kitchen printer'),
                const SizedBox(height: AppSpacing.space8),
                AppCard(child: _printerSummary()),

                if (_kitchenPrinter != null) ...[
                  const SizedBox(height: AppSpacing.space8),
                  OutlinedButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.space16),
                PrimaryButton(
                  text: _scanning ? 'Scanning…' : 'Scan for printers',
                  onPressed: _scanning ? null : _scan,
                  isLoading: _scanning,
                ),
                const SizedBox(height: AppSpacing.space12),
                ..._found.map(_printerTile),

                const SizedBox(height: AppSpacing.space24),
                _header('Ticket width'),
                const SizedBox(height: AppSpacing.space8),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _sizeTile(PaperSizes.mm58, '58 mm', 'Narrow roll'),
                    _sizeTile(PaperSizes.mm80, '80 mm', 'Standard roll'),
                  ]),
                ),
                const SizedBox(height: AppSpacing.space4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.space4),
                  child: Text(
                    'Thermal only — a kitchen ticket is a slip torn off at the '
                    'pass, so the A5/A4 options used for invoices do not apply.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),

                const SizedBox(height: AppSpacing.space24),
                OutlinedButton.icon(
                  onPressed: (_testing || !canPrint) ? null : _testPrint,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(_testing ? 'Printing…' : 'Print a test ticket'),
                ),
                const SizedBox(height: AppSpacing.space32),
              ],
            ),
    );
  }

  Widget _printerSummary() {
    if (_kitchenPrinter != null) {
      return Row(children: [
        const Icon(Icons.print_outlined, color: AppColors.accent, size: 20),
        const SizedBox(width: AppSpacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_kitchenPrinter!.name ?? 'Unknown printer',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis),
              Text(
                '${_kitchenPrinter!.connectionType?.name ?? ''}'
                '${_kitchenPrinter!.address != null ? ' · ${_kitchenPrinter!.address}' : ''}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const StatusBadge(label: 'Active', status: StatusType.success),
      ]);
    }

    // No dedicated kitchen printer. Say which printer will actually be used
    // rather than just "not set", so the fallback is never a surprise.
    final fallback = _billingPrinter?.name;
    return Row(children: [
      const Icon(Icons.print_disabled_outlined,
          color: AppColors.textDisabled, size: 20),
      const SizedBox(width: AppSpacing.space12),
      Expanded(
        child: Text(
          fallback == null
              ? 'Not set. Connect a printer, or set the billing printer up '
                  'first and tickets will use that.'
              : 'Not set — tickets will print on the billing printer '
                  '($fallback).',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    ]);
  }

  Widget _printerTile(Printer p) {
    final selected = p.address != null && p.address == _kitchenPrinter?.address;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space8),
      child: AppCard(
        onTap: selected ? null : () => _select(p),
        child: Row(children: [
          Icon(selected ? Icons.check_circle : Icons.print_outlined,
              size: 20,
              color: selected ? AppColors.success : AppColors.textSecondary),
          const SizedBox(width: AppSpacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name ?? 'Unknown printer',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${p.connectionType?.name ?? ''}'
                  '${p.address != null ? ' · ${p.address}' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sizeTile(String value, String label, String subtitle) {
    final selected = _paperSize == value;
    return InkWell(
      onTap: () => _setPaperSize(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space12, vertical: AppSpacing.space12),
        child: Row(children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? AppColors.primary : AppColors.textDisabled,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.space12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _header(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary),
      );
}
