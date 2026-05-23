import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart' as ftp;
import 'package:flutter_thermal_printer/utils/printer.dart' as ftp show Printer, ConnectionType;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../theme/app_theme.dart';

/// Temporary screen to test all print methods on Windows.
/// Try each method and report which one prints correctly.
class PrinterTestWindowsScreen extends StatefulWidget {
  const PrinterTestWindowsScreen({super.key});

  @override
  State<PrinterTestWindowsScreen> createState() => _PrinterTestWindowsScreenState();
}

class _PrinterTestWindowsScreenState extends State<PrinterTestWindowsScreen> {
  String _log = 'Loading printers…';
  bool _busy = false;
  bool _loadingPrinters = false;

  List<ftp.Printer> _printers = [];
  String? _selectedAddress; // address string used for dropdown equality

  // Derive selected printer from address to avoid ftp.Printer == issues
  ftp.Printer? get _selectedPrinter =>
      _printers.where((p) => p.address == _selectedAddress).firstOrNull;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() => _loadingPrinters = true);
    try {
      final instance = ftp.FlutterThermalPrinter.instance;
      await instance.getPrinters(
        refreshDuration: const Duration(seconds: 3),
        connectionTypes: [ftp.ConnectionType.USB, ftp.ConnectionType.BLE],
      );
      final devices = await instance.devicesStream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => <ftp.Printer>[],
      );
      setState(() {
        _printers = devices;
        if (devices.isNotEmpty) {
          _selectedAddress = devices.first.address;
          _log = 'Found ${devices.length} printer(s). Select one and test.';
        } else {
          _log = 'No printers found. Make sure printer is connected via USB or BLE.';
        }
      });
    } catch (e) {
      _setLog('Error loading printers: $e');
    } finally {
      setState(() => _loadingPrinters = false);
    }
  }

  void _setLog(String msg) => setState(() => _log = msg);

  Future<bool> _connect() async {
    if (_selectedPrinter == null) {
      _setLog('No printer selected.');
      return false;
    }
    _setLog('Connecting to ${_selectedPrinter!.name}…');
    try {
      final ok = await ftp.FlutterThermalPrinter.instance.connect(_selectedPrinter!);
      if (!ok) {
        _setLog('❌ Connection failed.');
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 500));
      _setLog('✅ Connected to ${_selectedPrinter!.name}.');
      return true;
    } catch (e) {
      _setLog('❌ Connect error: $e');
      return false;
    }
  }

  Future<void> _sendBytes(List<int> bytes, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _connect();
      if (!ok) return;
      _setLog('Sending $label (${bytes.length} bytes)…');
      await ftp.FlutterThermalPrinter.instance
          .printData(_selectedPrinter!, bytes, longData: true);
      _setLog('✅ $label sent! Check printer output.');
    } catch (e) {
      _setLog('❌ Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ── METHOD 1: Raw plain text LF ───────────────────────────────────────────
  Future<void> _testRawLF() async {
    const text =
        'METHOD 1: RAW TEXT LF\n'
        '------------------------------------------\n'
        'Hello from billing app\n'
        'Line 2\n'
        '------------------------------------------\n'
        '\n\n\n';
    final bytes = text.codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 1: Raw LF');
  }

  // ── METHOD 2: Raw plain text CRLF ────────────────────────────────────────
  Future<void> _testRawCRLF() async {
    const text =
        'METHOD 2: RAW TEXT CRLF\r\n'
        '------------------------------------------\r\n'
        'Hello from billing app\r\n'
        'Line 2\r\n'
        '------------------------------------------\r\n'
        '\r\n\r\n\r\n';
    final bytes = text.codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 2: Raw CRLF');
  }

  // ── METHOD 3: ESC/POS 80mm via esc_pos_utils_plus ────────────────────────
  Future<void> _testEscPos80mm() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm80, profile);
    var bytes = <int>[];
    bytes += gen.text('METHOD 3: ESC/POS 80mm',
        styles: const PosStyles(bold: true, align: PosAlign.center));
    bytes += gen.hr();
    bytes += gen.text('Hello from billing app');
    bytes += gen.text('Line 2');
    bytes += gen.hr();
    bytes += gen.text('Thank you!', styles: const PosStyles(align: PosAlign.center));
    bytes += gen.feed(3);
    bytes += gen.cut();
    await _sendBytes(bytes, 'Method 3: ESC/POS 80mm');
  }

  // ── METHOD 4: ESC/POS 58mm via esc_pos_utils_plus ────────────────────────
  Future<void> _testEscPos58mm() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    var bytes = <int>[];
    bytes += gen.text('METHOD 4: ESC/POS 58mm',
        styles: const PosStyles(bold: true, align: PosAlign.center));
    bytes += gen.hr();
    bytes += gen.text('Hello from billing app');
    bytes += gen.text('Line 2');
    bytes += gen.hr();
    bytes += gen.text('Thank you!', styles: const PosStyles(align: PosAlign.center));
    bytes += gen.feed(3);
    bytes += gen.cut();
    await _sendBytes(bytes, 'Method 4: ESC/POS 58mm');
  }

  // ── METHOD 5: ESC/POS with reset (ESC @) ─────────────────────────────────
  Future<void> _testEscPosWithReset() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm80, profile);
    var bytes = <int>[];
    bytes += gen.reset();
    bytes += gen.text('METHOD 5: ESC/POS + RESET',
        styles: const PosStyles(bold: true, align: PosAlign.center));
    bytes += gen.hr();
    bytes += gen.text('Hello from billing app');
    bytes += gen.feed(3);
    bytes += gen.cut();
    await _sendBytes(bytes, 'Method 5: ESC/POS + reset');
  }

  // ── METHOD 6: Manual ESC/POS bytes (no library) ──────────────────────────
  Future<void> _testManualEscPos() async {
    final bytes = <int>[
      0x1B, 0x40,          // ESC @ initialize
      0x1B, 0x61, 0x01,    // center
      0x1B, 0x45, 0x01,    // bold on
    ];
    for (final c in 'METHOD 6: MANUAL ESC/POS\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    bytes.addAll([0x1B, 0x45, 0x00, 0x1B, 0x61, 0x00]); // bold off, left
    for (final c in 'Hello from billing app\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    bytes.addAll([0x0A, 0x0A, 0x0A]);
    bytes.addAll([0x1D, 0x56, 0x41, 0x10]); // partial cut
    await _sendBytes(bytes, 'Method 6: Manual ESC/POS');
  }

  // ── METHOD 7: TSPL label (fixed size) ────────────────────────────────────
  Future<void> _testTsplLabel() async {
    const tspl =
        'SIZE 80 mm,40 mm\r\n'
        'GAP 2 mm,0 mm\r\n'
        'DIRECTION 0\r\n'
        'CLS\r\n'
        'TEXT 10,10,"3",0,1,1,"METHOD 7: TSPL LABEL"\r\n'
        'TEXT 10,40,"3",0,1,1,"Hello from billing app"\r\n'
        'TEXT 10,70,"3",0,1,1,"If this prints = TSPL mode"\r\n'
        'PRINT 1,1\r\n';
    final bytes = tspl.codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 7: TSPL label');
  }

  // ── METHOD 8: TSPL receipt (continuous roll) ──────────────────────────────
  Future<void> _testTsplReceipt() async {
    const int lineH = 28;
    final lines = [
      '       METHOD 8: TSPL RECEIPT',
      '------------------------------------------',
      'Bill#: 0001',
      'Date : 22-May-2026 10:30 AM',
      'Cust : Test Customer',
      '------------------------------------------',
      'Item                Qty   Price      Total',
      '------------------------------------------',
      'Parle G Biscuit       2   10.00      20.00',
      'Coca Cola 500ml       1   40.00      40.00',
      'Dairy Milk 50g        3   20.00      60.00',
      '------------------------------------------',
      'TOTAL   :                          Rs.120.00',
      'Payment :                               CASH',
      '------------------------------------------',
      '        Thank you, visit again!',
      '',
      '',
    ];
    final totalHeight = 10 + lines.length * lineH + 20;
    final sb = StringBuffer();
    sb.write('SIZE 80 mm,$totalHeight\r\n');
    sb.write('GAP 0 mm,0 mm\r\n');
    sb.write('DIRECTION 0\r\n');
    sb.write('CODEPAGE 437\r\n');
    sb.write('CLS\r\n');
    int y = 10;
    for (final line in lines) {
      final escaped = line.replaceAll('"', '\\"');
      sb.write('TEXT 10,$y,"3",0,1,1,"$escaped"\r\n');
      y += lineH;
    }
    sb.write('PRINT 1,1\r\n');
    final bytes = sb.toString().codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 8: TSPL receipt');
  }

  // ── METHOD 9: ESC/POS no reset, plain text + LF (Android working method) ─
  Future<void> _testNoResetPlain() async {
    final lines = [
      '      METHOD 9: NO RESET PLAIN',
      '------------------------------------------',
      'Hello from billing app',
      'Line 2',
      '------------------------------------------',
    ];
    final bytes = <int>[];
    for (final line in lines) {
      for (final c in line.codeUnits) {
        bytes.add(c > 127 ? 63 : c);
      }
      bytes.add(0x0A);
    }
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
    await _sendBytes(bytes, 'Method 9: No-reset plain');
  }

  // ── METHOD 10: ESC/POS CP1252 code table ─────────────────────────────────
  Future<void> _testEscPosCP1252() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm80, profile);
    var bytes = <int>[];
    bytes += gen.setGlobalCodeTable('CP1252');
    bytes += gen.text('METHOD 10: ESC/POS CP1252',
        styles: const PosStyles(bold: true, align: PosAlign.center));
    bytes += gen.hr();
    bytes += gen.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
      PosColumn(text: 'Total', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Parle G', width: 6),
      PosColumn(text: '2', width: 2, styles: const PosStyles(align: PosAlign.right)),
      PosColumn(text: 'Rs.20', width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.hr();
    bytes += gen.text('TOTAL: Rs.20', styles: const PosStyles(bold: true, align: PosAlign.right));
    bytes += gen.feed(3);
    bytes += gen.cut();
    await _sendBytes(bytes, 'Method 10: ESC/POS CP1252');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Windows Printer Test (Temp)'),
        backgroundColor: const Color(0xFF0078D4), // Windows blue
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh printers',
            onPressed: _loadingPrinters ? null : _loadPrinters,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPrinterSelector(),
          _buildStatusPanel(),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildGroup('Raw Text', [
                  _TestButton(
                    label: 'Method 1: Raw Text (LF)',
                    subtitle: 'Plain ASCII, \\n line endings',
                    color: Colors.orange,
                    onTap: _busy ? null : _testRawLF,
                  ),
                  _TestButton(
                    label: 'Method 2: Raw Text (CRLF)',
                    subtitle: 'Plain ASCII, \\r\\n line endings',
                    color: Colors.orange,
                    onTap: _busy ? null : _testRawCRLF,
                  ),
                  _TestButton(
                    label: 'Method 9: No-reset plain + LF',
                    subtitle: 'Android working method — test on Windows',
                    color: Colors.orange,
                    onTap: _busy ? null : _testNoResetPlain,
                  ),
                ]),
                const SizedBox(height: 12),
                _buildGroup('ESC/POS Protocol', [
                  _TestButton(
                    label: 'Method 3: ESC/POS 80mm',
                    subtitle: 'esc_pos_utils_plus, PaperSize.mm80',
                    color: AppColors.primary,
                    onTap: _busy ? null : _testEscPos80mm,
                  ),
                  _TestButton(
                    label: 'Method 4: ESC/POS 58mm',
                    subtitle: 'esc_pos_utils_plus, PaperSize.mm58',
                    color: AppColors.primary,
                    onTap: _busy ? null : _testEscPos58mm,
                  ),
                  _TestButton(
                    label: 'Method 5: ESC/POS + reset',
                    subtitle: 'With gen.reset() (ESC @) before text',
                    color: AppColors.primary,
                    onTap: _busy ? null : _testEscPosWithReset,
                  ),
                  _TestButton(
                    label: 'Method 10: ESC/POS + CP1252',
                    subtitle: 'Code table + item rows',
                    color: AppColors.primary,
                    onTap: _busy ? null : _testEscPosCP1252,
                  ),
                ]),
                const SizedBox(height: 12),
                _buildGroup('Manual / TSPL', [
                  _TestButton(
                    label: 'Method 6: Manual ESC/POS bytes',
                    subtitle: 'Hand-crafted byte sequence',
                    color: const Color(0xFF7C3AED),
                    onTap: _busy ? null : _testManualEscPos,
                  ),
                  _TestButton(
                    label: 'Method 7: TSPL label (fixed size)',
                    subtitle: 'TSPL with SIZE + GAP 2mm',
                    color: AppColors.error,
                    onTap: _busy ? null : _testTsplLabel,
                  ),
                  _TestButton(
                    label: 'Method 8: TSPL receipt (continuous)',
                    subtitle: 'TSPL with GAP 0mm — receipt format',
                    color: AppColors.success,
                    onTap: _busy ? null : _testTsplReceipt,
                  ),
                ]),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _log.startsWith('✅')
                ? Icons.check_circle_outline
                : _log.startsWith('❌')
                    ? Icons.error_outline
                    : Icons.info_outline,
            size: 16,
            color: _log.startsWith('✅')
                ? AppColors.success
                : _log.startsWith('❌')
                    ? AppColors.error
                    : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _log,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _log.startsWith('✅')
                        ? AppColors.success
                        : _log.startsWith('❌')
                            ? AppColors.error
                            : AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterSelector() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: _loadingPrinters
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Scanning for printers (USB & BLE)…'),
                ],
              ),
            )
          : _printers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.print_disabled,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No printers found. Connect printer via USB or BLE.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _loadPrinters,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                    ],
                  ),
                )
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedAddress,
                    icon: const Icon(Icons.expand_more, size: 20),
                    items: _printers
                        .map((p) => DropdownMenuItem<String>(
                              value: p.address,
                              child: Row(
                                children: [
                                  Icon(
                                    p.connectionType == ftp.ConnectionType.USB
                                        ? Icons.usb
                                        : Icons.bluetooth,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(p.name ?? 'Unknown',
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600)),
                                        Text(
                                          '${p.connectionType == ftp.ConnectionType.USB ? 'USB' : 'BLE'} · ${p.address ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (val) => setState(() => _selectedAddress = val),
                  ),
                ),
    );
  }

  Widget _buildGroup(String title, List<Widget> buttons) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.8,
                )),
        const SizedBox(height: 6),
        ...buttons,
      ],
    );
  }
}

class _TestButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _TestButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: onTap == null
            ? AppColors.surfaceVariant
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(
                  color: onTap == null
                      ? AppColors.border
                      : color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onTap == null ? AppColors.textDisabled : color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: onTap == null
                                ? AppColors.textDisabled
                                : AppColors.textPrimary,
                          )),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.print_outlined,
                    size: 18,
                    color: onTap == null ? AppColors.textDisabled : color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
