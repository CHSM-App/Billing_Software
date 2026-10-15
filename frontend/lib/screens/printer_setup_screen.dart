import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/l10n_ext.dart';
import '../services/printer_service.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Asks for a Wi-Fi/LAN printer's IP + port. Network printers can't be
/// scanned for, so this is how one gets saved. Shared with the kitchen
/// printer settings. Addresses added before are offered as chips that fill
/// the fields, so an IP is typed once per device.
Future<Printer?> showNetworkPrinterDialog(BuildContext context) async {
  final l10n = context.l10n;
  final recent = await getRecentNetworkPrinters();
  if (!context.mounted) return null;
  final ip = TextEditingController();
  final port = TextEditingController(text: '9100');
  final formKey = GlobalKey<FormState>();
  return showDialog<Printer>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.printerSetupNetworkTitle),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (recent.isNotEmpty)
            Wrap(spacing: AppSpacing.space8, runSpacing: AppSpacing.space4, children: [
              for (final address in recent)
                ActionChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text(address),
                  onPressed: () {
                    // Saved as "ip:port" by this dialog.
                    final i = address.lastIndexOf(':');
                    ip.text = i < 0 ? address : address.substring(0, i);
                    if (i >= 0) port.text = address.substring(i + 1);
                  },
                ),
            ]),
          TextFormField(
            controller: ip,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
                labelText: l10n.printerSetupNetworkIp,
                hintText: l10n.printerSetupNetworkIpHint),
            validator: (v) => (v == null || v.trim().isEmpty || v.contains(' '))
                ? l10n.printerSetupNetworkInvalid
                : null,
          ),
          TextFormField(
            controller: port,
            keyboardType: TextInputType.number,
            decoration:
                InputDecoration(labelText: l10n.printerSetupNetworkPort),
            validator: (v) {
              final p = int.tryParse(v ?? '');
              return (p == null || p < 1 || p > 65535) ? '1–65535' : null;
            },
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel)),
        TextButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final address = '${ip.text.trim()}:${port.text.trim()}';
            rememberNetworkPrinter(address);
            Navigator.pop(
                ctx,
                Printer(
                    name: l10n.printerSetupNetworkTitle,
                    address: address,
                    connectionType: ConnectionType.network));
          },
          child: Text(l10n.commonAdd),
        ),
      ],
    ),
  );
}

IconData printerIcon(ConnectionType? t) => switch (t) {
      ConnectionType.usb => Icons.usb_outlined,
      ConnectionType.network => Icons.wifi_outlined,
      _ => Icons.bluetooth_outlined,
    };

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
  String _paperSize = PaperSizes.mm80;

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  Future<void> _loadActive() async {
    final p = await PrinterService.instance.getActivePrinter();
    final size = await getPaperSize();
    setState(() {
      _activePrinter = p;
      _paperSize = size;
    });
  }

  Future<void> _selectPaperSize(String size) async {
    setState(() => _paperSize = size);
    await savePaperSize(size);
    // Bump the printer revision so paperSizeProvider (and the billing screen's
    // Print/Save button) reflect the change immediately.
    PrinterService.instance.activePrinterRevision.value++;
  }

  Future<void> _scan() async {
    final l10n = context.l10n;
    // Request Bluetooth permissions before listing devices. bluetoothConnect/
    // bluetoothScan are Android-only — on iOS they report permanentlyDenied
    // without prompting, so iOS asks for Permission.bluetooth instead.
    final statuses = await (defaultTargetPlatform == TargetPlatform.iOS
            ? [Permission.bluetooth]
            : [
                Permission.bluetoothConnect,
                Permission.bluetoothScan,
                Permission.location,
              ])
        .request();

    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied) {
      _showSnack(l10n.printerSetupPermissionDenied, isError: true);
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
        _showSnack(l10n.printerSetupNoPaired);
      }
    } catch (e) {
      _showSnack(l10n.printerSetupLoadFailed('$e'), isError: true);
    } finally {
      setState(() => _scanning = false);
    }
  }

  Future<void> _select(Printer printer) async {
    final l10n = context.l10n;
    await PrinterService.instance.setActivePrinter(printer);
    setState(() => _activePrinter = printer);
    _showSnack(l10n.printerSetupSelectedSnack(
        printer.name ?? l10n.printerSetupUnknownPrinter));
  }

  Future<void> _clearPrinter() async {
    final l10n = context.l10n;
    await PrinterService.instance.clearActivePrinter();
    setState(() => _activePrinter = null);
    _showSnack(l10n.printerSetupCleared);
  }

  Future<void> _testPrint() async {
    final l10n = context.l10n;
    setState(() => _testing = true);
    try {
      await PrinterService.instance
          .testPrint(paperDots: PaperSizes.thermalDots(_paperSize));
      _showSnack(l10n.printerSetupTestSent);
    } on PrinterException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (e) {
      _showSnack(l10n.printerSetupPrintFailed('$e'), isError: true);
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.printerSetupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space16),
        children: [
          // Active printer card
          _sectionHeader(l10n.printerSetupActivePrinter),
          const SizedBox(height: AppSpacing.space8),
          AppCard(
            child: _activePrinter == null
                ? Row(
                    children: [
                      const Icon(Icons.print_disabled_outlined,
                          color: AppColors.textDisabled, size: 20),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Text(l10n.printerSetupNotConfigured,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary)),
                      ),
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
                            Text(
                                _activePrinter!.name ??
                                    l10n.printerSetupUnknown,
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis),
                            Text(
                              '${_activePrinter!.connectionType?.name ?? ''}'
                              '${_activePrinter!.address != null ? ' · ${_activePrinter!.address}' : ''}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space8),
                      StatusBadge(
                          label: l10n.printerSetupActiveBadge,
                          status: StatusType.success),
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
                    label: Text(l10n.printerSetupTestPrint,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: AppSpacing.space8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearPrinter,
                    icon: const Icon(Icons.clear_outlined, size: 16),
                    label: Text(l10n.commonRemove,
                        overflow: TextOverflow.ellipsis),
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

          // Paper size section
          _sectionHeader(l10n.printerSetupPaperSize),
          const SizedBox(height: AppSpacing.space8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _paperSizeTile(PaperSizes.mm58, l10n.printerSetupPaperSize58, null),
                _paperSizeTile(PaperSizes.mm80, l10n.printerSetupPaperSize80, null),
                _paperSizeTile(
                    PaperSizes.a5, l10n.printerSetupPaperSizeA5, l10n.printerSetupPaperSizePdfHint),
                _paperSizeTile(
                    PaperSizes.a4, l10n.printerSetupPaperSizeA4, l10n.printerSetupPaperSizePdfHint),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.space24),

          // Scan section
          _sectionHeader(l10n.printerSetupAvailablePrinters),
          const SizedBox(height: AppSpacing.space8),
          PrimaryButton(
            text: _scanning
                ? l10n.printerSetupScanning
                : l10n.printerSetupScanButton,
            onPressed: _scanning ? null : _scan,
            isLoading: _scanning,
          ),
          const SizedBox(height: AppSpacing.space8),
          OutlinedButton.icon(
            onPressed: () async {
              final p = await showNetworkPrinterDialog(context);
              if (p != null && mounted) await _select(p);
            },
            icon: const Icon(Icons.wifi_outlined, size: 16),
            label: Text(l10n.printerSetupAddNetwork),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            l10n.printerSetupScanHint,
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
                  Expanded(
                    child: Text(l10n.printerSetupTapScan,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary)),
                  ),
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
                        printerIcon(printer.connectionType),
                        size: 20,
                        color: isActive ? AppColors.accent : AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(printer.name ?? l10n.printerSetupUnknownPrinter,
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis),
                            if (printer.address != null)
                              Text(printer.address!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textSecondary),
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space8),
                      if (isActive)
                        StatusBadge(
                            label: l10n.printerSetupSelectedBadge,
                            status: StatusType.success)
                      else
                        TextButton(
                            onPressed: () => _select(printer),
                            child: Text(l10n.printerSetupSelect)),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: AppSpacing.space32),
          _sectionHeader(l10n.printerSetupNotes),
          const SizedBox(height: AppSpacing.space8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _noteRow(Icons.bluetooth_outlined,
                    l10n.printerSetupNoteBluetooth),
                const SizedBox(height: AppSpacing.space8),
                _noteRow(Icons.laptop_outlined, l10n.printerSetupNoteWindows),
                const SizedBox(height: AppSpacing.space8),
                _noteRow(Icons.usb_outlined, l10n.printerSetupNoteUsb),
                const SizedBox(height: AppSpacing.space8),
                _noteRow(Icons.wifi_outlined, l10n.printerSetupNoteNetwork),
                const SizedBox(height: AppSpacing.space8),
                _noteRow(Icons.info_outline, l10n.printerSetupNoteThermal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperSizeTile(String value, String label, String? subtitle) {
    final selected = _paperSize == value;
    return InkWell(
      onTap: () => _selectPaperSize(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space12, vertical: AppSpacing.space12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.textDisabled,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
          ],
        ),
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
