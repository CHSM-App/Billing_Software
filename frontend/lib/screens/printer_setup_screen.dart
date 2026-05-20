import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/printer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  List<Printer> _printers = [];
  Printer? _activePrinter;
  bool _scanning = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    final p = await PrinterService.instance.getActivePrinter();
    setState(() => _activePrinter = p);
  }

  Future<void> _scan() async {
    // Request Bluetooth permissions on Android before listing paired devices
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied) {
      _showSnack('Bluetooth permission denied. Grant it in app settings.', isError: true);
      return;
    }

    setState(() {
      _scanning = true;
      _printers = [];
    });
    try {
      final found = await PrinterService.instance.listPrinters();
      setState(() => _printers = found);
      if (found.isEmpty) {
        _showSnack('No paired printers found. Pair your printer in phone Bluetooth settings first.');
      }
    } catch (e) {
      _showSnack('Failed to load printers: $e', isError: true);
    } finally {
      setState(() => _scanning = false);
    }
  }

  Future<void> _select(Printer printer) async {
    await PrinterService.instance.setActivePrinter(printer);
    setState(() => _activePrinter = printer);
    _showSnack('Printer "${printer.name}" selected');
  }

  Future<void> _clearPrinter() async {
    await PrinterService.instance.clearActivePrinter();
    setState(() => _activePrinter = null);
    _showSnack('Printer cleared');
  }

  Future<void> _testPrint() async {
    setState(() => _testing = true);
    try {
      await PrinterService.instance.testPrint();
      _showSnack('Test page sent!');
    } on PrinterException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (e) {
      _showSnack('Print failed: $e', isError: true);
    } finally {
      setState(() => _testing = false);
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
      appBar: AppBar(title: const Text('Printer Setup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space16),
        children: [
          // Active printer card
          _sectionHeader('Active Printer'),
          const SizedBox(height: AppSpacing.space8),
          AppCard(
            child: _activePrinter == null
                ? Row(
                    children: [
                      const Icon(Icons.print_disabled_outlined,
                          color: AppColors.textDisabled, size: 20),
                      const SizedBox(width: AppSpacing.space12),
                      Text('No printer configured',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
                    ],
                  )
                : Row(
                    children: [
                      const Icon(Icons.print_outlined,
                          color: AppColors.accent, size: 20),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_activePrinter!.name ?? 'Unknown',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(
                              '${_activePrinter!.connectionType?.name ?? ''}'
                              '${_activePrinter!.address != null ? ' · ${_activePrinter!.address}' : ''}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(label: 'Active', status: StatusType.success),
                    ],
                  ),
          ),

          if (_activePrinter != null) ...[
            const SizedBox(height: AppSpacing.space12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testPrint,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Test Print'),
                  ),
                ),
                const SizedBox(width: AppSpacing.space8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearPrinter,
                    icon: const Icon(Icons.clear_outlined, size: 16),
                    label: const Text('Remove'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.space24),

          // Scan section
          _sectionHeader('Available Printers'),
          const SizedBox(height: AppSpacing.space8),
          PrimaryButton(
            text: _scanning ? 'Scanning…' : 'Scan for Printers',
            onPressed: _scanning ? null : _scan,
            isLoading: _scanning,
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            'Shows printers already paired in your phone\'s Bluetooth settings. Pair the printer there first, then tap Scan.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space16),

          if (_printers.isEmpty && !_scanning)
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_searching_outlined,
                      color: AppColors.textDisabled, size: 20),
                  const SizedBox(width: AppSpacing.space12),
                  Text('Tap "Scan" to find printers',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            )
          else
            ..._printers.map((printer) {
              final isActive = _activePrinter?.address == printer.address;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                child: AppCard(
                  onTap: isActive ? null : () => _select(printer),
                  child: Row(
                    children: [
                      Icon(
                        printer.connectionType == ConnectionType.usb
                            ? Icons.usb_outlined
                            : Icons.bluetooth_outlined,
                        size: 20,
                        color: isActive ? AppColors.accent : AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(printer.name ?? 'Unknown Printer',
                                style: Theme.of(context).textTheme.titleMedium),
                            if (printer.address != null)
                              Text(printer.address!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      if (isActive)
                        const StatusBadge(label: 'Selected', status: StatusType.success)
                      else
                        TextButton(
                            onPressed: () => _select(printer),
                            child: const Text('Select')),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: AppSpacing.space32),
          _sectionHeader('Notes'),
          const SizedBox(height: AppSpacing.space8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _noteRow(Icons.bluetooth_outlined, 'Android/iPhone: pair the printer in phone Bluetooth settings first, then tap Scan here'),
                const SizedBox(height: AppSpacing.space8),
                _noteRow(Icons.laptop_outlined, 'Windows: uses BLE or USB — printer must be powered on during scan'),
                const SizedBox(height: AppSpacing.space8),
                _noteRow(Icons.usb_outlined, 'USB on Windows requires WinUSB driver installed for the printer'),
                const SizedBox(height: AppSpacing.space8),
                _noteRow(Icons.info_outline, 'Only 80mm thermal printers are supported'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: AppColors.textSecondary, letterSpacing: 0.8),
    );
  }

  Widget _noteRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.space8),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
