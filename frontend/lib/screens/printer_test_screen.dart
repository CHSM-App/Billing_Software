import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../theme/app_theme.dart';

/// Temporary screen to test all possible ESC/POS printing methods on Android.
/// Navigate here from anywhere to test, then report which button prints correctly.
class PrinterTestScreen extends StatefulWidget {
  const PrinterTestScreen({super.key});

  @override
  State<PrinterTestScreen> createState() => _PrinterTestScreenState();
}

class _PrinterTestScreenState extends State<PrinterTestScreen> {
  String _log = 'Loading paired printers…';
  bool _busy = false;
  bool _loadingPrinters = false;

  List<BluetoothInfo> _pairedPrinters = [];
  BluetoothInfo? _selectedPrinter;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() => _loadingPrinters = true);
    try {
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      setState(() {
        _pairedPrinters = paired;
        if (paired.isNotEmpty) {
          _selectedPrinter = paired.first;
          _log = 'Select a printer, then tap a test button.';
        } else {
          _log = 'No paired Bluetooth printers found.\nPair a printer in Android Settings first.';
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
    final addr = _selectedPrinter!.macAdress;
    _setLog('Connecting to ${_selectedPrinter!.name}…');
    try {
      final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
      if (alreadyConnected) {
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: addr,
      );
      if (!connected) {
        _setLog('❌ Connection failed.');
        return false;
      }
      await Future.delayed(const Duration(seconds: 2));
      return true;
    } catch (e) {
      _setLog('❌ Connect error: $e');
      return false;
    }
  }

  /// Sends bytes in 512-byte chunks after connecting.
  Future<void> _sendBytes(List<int> bytes, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _connect();
      if (!ok) return;
      _setLog('Sending $label (${bytes.length} bytes)…');
      const chunkSize = 512;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, bytes.length);
        final result = await PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
        if (!result) {
          _setLog('❌ Write failed at chunk offset $i');
          return;
        }
        if (end < bytes.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
      _setLog('✅ $label sent! Check printer output.');
    } catch (e) {
      _setLog('❌ Error in _sendBytes: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ── METHOD 1: Raw plain text LF ───────────────────────────────────────────
  Future<void> _testRawText() async {
    const text =
        'METHOD 1: RAW TEXT LF\n'
        '--------------------------------\n'
        'Hello from billing app\n'
        'Line 2\n'
        '--------------------------------\n'
        '\n\n\n';
    final bytes = text.codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 1: Raw LF');
  }

  // ── METHOD 2: Raw plain text CRLF ────────────────────────────────────────
  Future<void> _testRawTextCRLF() async {
    const text =
        'METHOD 2: RAW TEXT CRLF\r\n'
        '--------------------------------\r\n'
        'Hello from billing app\r\n'
        'Line 2\r\n'
        '--------------------------------\r\n'
        '\r\n\r\n\r\n';
    final bytes = text.codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 2: Raw CRLF');
  }

  // ── METHOD 3: ESC/POS 80mm ───────────────────────────────────────────────
  Future<void> _testEscPos80mm() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm80, profile);
    var bytes = <int>[];
    bytes += gen.reset();
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

  // ── METHOD 4: ESC/POS 58mm ───────────────────────────────────────────────
  Future<void> _testEscPos58mm() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    var bytes = <int>[];
    bytes += gen.reset();
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

  // ── METHOD 5A: ESC/POS NO reset — just text + feed (no ESC @ init) ─────────
  // ESC @ (reset) was wiping the buffer on methods 3 & 4 causing blank paper.
  // This skips reset entirely.
  Future<void> _testManualEscPos() async {
    final bytes = <int>[];
    // NO ESC @ reset here — just start printing
    for (final c in 'METHOD 5A: NO RESET\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    for (final c in '------------------------\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    for (final c in 'Hello from billing app\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    for (final c in 'Line 2 test\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    bytes.addAll([0x0A, 0x0A, 0x0A]); // 3x line feed
    await _sendBytes(bytes, 'Method 5A: No-reset plain text');
  }

  // ── METHOD 5B: ESC/POS with init but NO cut command ───────────────────────
  // Tests if the cut command (GS V) was causing the issue
  Future<void> _testEscPosNoCut() async {
    final bytes = <int>[
      0x1B, 0x40, // ESC @ init
    ];
    for (final c in 'METHOD 5B: ESC INIT NO CUT\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    for (final c in '------------------------\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    for (final c in 'Hello from billing app\n'.codeUnits) {
      bytes.add(c > 127 ? 63 : c);
    }
    bytes.addAll([0x0A, 0x0A, 0x0A]); // 3x line feed, no cut
    await _sendBytes(bytes, 'Method 5B: ESC init, no cut');
  }

  // ── METHOD 6: TSPL label (fixed size) ────────────────────────────────────
  Future<void> _testTspl() async {
    const tspl =
        'SIZE 80 mm,40 mm\r\n'
        'GAP 2 mm,0 mm\r\n'
        'DIRECTION 0\r\n'
        'CLS\r\n'
        'TEXT 10,10,"3",0,1,1,"METHOD 6: TSPL LABEL"\r\n'
        'TEXT 10,40,"3",0,1,1,"Hello from billing app"\r\n'
        'TEXT 10,70,"3",0,1,1,"If this prints = TSPL printer"\r\n'
        'PRINT 1,1\r\n';
    final bytes = tspl.codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 6: TSPL label');
  }

  // ── METHOD 10: TSPL receipt (continuous roll) ─────────────────────────────
  // This is the correct format for printing receipts on a TSPL printer.
  Future<void> _testTsplReceipt() async {
    const int lineH = 28;
    const int marginX = 10;
    final lines = [
      '       METHOD 10: TSPL RECEIPT',
      '------------------------------------------',
      'Bill#: 0001',
      'Date : 22-May-2026 10:30 AM',
      'Cust : Test Customer',
      '------------------------------------------',
      'Item              Qty   Price     Total',
      '------------------------------------------',
      'Parle G Biscuit     2    10.00     20.00',
      'Coca Cola 500ml     1    40.00     40.00',
      'Dairy Milk 50g      3    20.00     60.00',
      '------------------------------------------',
      'TOTAL   :                      Rs.120.00',
      'Payment :                           CASH',
      '------------------------------------------',
      '      Thank you, visit again!',
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
      sb.write('TEXT $marginX,$y,"3",0,1,1,"$escaped"\r\n');
      y += lineH;
    }
    sb.write('PRINT 1,1\r\n');
    final bytes = sb.toString().codeUnits.map((c) => c > 127 ? 63 : c).toList();
    await _sendBytes(bytes, 'Method 10: TSPL Receipt');
  }

  // ── METHOD 7: ESC/POS + CP1252 + item rows ───────────────────────────────
  Future<void> _testEscPosCP1252() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm80, profile);
    var bytes = <int>[];
    bytes += gen.reset();
    bytes += gen.setGlobalCodeTable('CP1252');
    bytes += gen.text('METHOD 7: ESC/POS CP1252',
        styles: const PosStyles(bold: true, align: PosAlign.center));
    bytes += gen.hr();
    bytes += gen.row([
      PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Total', width: 6,
          styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(text: 'ParleG', width: 6),
      PosColumn(text: 'Rs.20', width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.hr();
    bytes += gen.text('TOTAL: Rs.20',
        styles: const PosStyles(bold: true, align: PosAlign.right));
    bytes += gen.feed(3);
    bytes += gen.cut();
    await _sendBytes(bytes, 'Method 7: ESC/POS CP1252');
  }

  // ── METHOD 8: writeString size 1 (high-level API) ────────────────────────
  Future<void> _testWriteStringNormal() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _connect();
      if (!ok) return;
      _setLog('Sending Method 8: writeString size 1…');
      const ticket =
          'METHOD 8: writeString size 1\n'
          '--------------------------------\n'
          'Hello from billing app\n'
          '--------------------------------\n'
          '\n\n\n';
      final result = await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: 1, text: ticket),
      );
      _setLog(result ? '✅ Method 8 success!' : '❌ Method 8 failed (returned false).');
    } catch (e) {
      _setLog('❌ Method 8 error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ── METHOD 9: writeString size 2 (high-level API) ────────────────────────
  Future<void> _testWriteStringBold() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _connect();
      if (!ok) return;
      _setLog('Sending Method 9: writeString size 2…');
      const ticket =
          'METHOD 9: writeString size 2\n'
          '--------------------------------\n'
          'Hello from billing app\n'
          '--------------------------------\n'
          '\n\n\n';
      final result = await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: 2, text: ticket),
      );
      _setLog(result ? '✅ Method 9 success!' : '❌ Method 9 failed (returned false).');
    } catch (e) {
      _setLog('❌ Method 9 error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Printer Test (Temp)'),
        backgroundColor: AppColors.warning,
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
          if (_busy)
            const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildGroup('Raw Text (simplest)', [
                  _TestButton(
                    label: 'Method 1: Raw Text (LF)',
                    subtitle: 'Plain ASCII bytes, \\n endings',
                    color: Colors.orange,
                    onTap: _busy ? null : _testRawText,
                  ),
                  _TestButton(
                    label: 'Method 2: Raw Text (CRLF)',
                    subtitle: 'Plain ASCII bytes, \\r\\n endings',
                    color: Colors.orange,
                    onTap: _busy ? null : _testRawTextCRLF,
                  ),
                ]),
                const SizedBox(height: 12),
                _buildGroup('ESC/POS Protocol', [
                  _TestButton(
                    label: 'Method 3: ESC/POS 80mm',
                    subtitle: 'PaperSize.mm80 + gen.reset()',
                    color: AppColors.primary,
                    onTap: _busy ? null : _testEscPos80mm,
                  ),
                  _TestButton(
                    label: 'Method 4: ESC/POS 58mm',
                    subtitle: 'PaperSize.mm58 + gen.reset()',
                    color: AppColors.primary,
                    onTap: _busy ? null : _testEscPos58mm,
                  ),
                  _TestButton(
                    label: 'Method 7: ESC/POS + CP1252',
                    subtitle: 'With code table + item rows',
                    color: AppColors.primary,
                    onTap: _busy ? null : _testEscPosCP1252,
                  ),
                ]),
                const SizedBox(height: 12),
                _buildGroup('Manual / Label Printer', [
                  _TestButton(
                    label: 'Method 5A: Plain text, no ESC init',
                    subtitle: 'No reset — skips ESC @ entirely',
                    color: const Color(0xFF7C3AED),
                    onTap: _busy ? null : _testManualEscPos,
                  ),
                  _TestButton(
                    label: 'Method 5B: ESC init, no cut',
                    subtitle: 'ESC @ init but no GS V cut command',
                    color: const Color(0xFF7C3AED),
                    onTap: _busy ? null : _testEscPosNoCut,
                  ),
                  _TestButton(
                    label: 'Method 6: TSPL label (fixed size)',
                    subtitle: 'Fixed label with GAP — confirmed working',
                    color: AppColors.error,
                    onTap: _busy ? null : _testTspl,
                  ),
                  _TestButton(
                    label: 'Method 10: TSPL Receipt (continuous)',
                    subtitle: 'No GAP, computed height — receipt format',
                    color: AppColors.success,
                    onTap: _busy ? null : _testTsplReceipt,
                  ),
                ]),
                const SizedBox(height: 12),
                _buildGroup('High-level writeString API', [
                  _TestButton(
                    label: 'Method 8: writeString size 1',
                    subtitle: 'PrintTextSize(size:1) — normal',
                    color: AppColors.accent,
                    onTap: _busy ? null : _testWriteStringNormal,
                  ),
                  _TestButton(
                    label: 'Method 9: writeString size 2',
                    subtitle: 'PrintTextSize(size:2) — larger text',
                    color: AppColors.accent,
                    onTap: _busy ? null : _testWriteStringBold,
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
                  Text('Scanning for paired printers…'),
                ],
              ),
            )
          : _pairedPrinters.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_disabled,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No paired printers. Pair in Android Settings.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _loadPrinters,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                )
              : DropdownButtonHideUnderline(
                  child: DropdownButton<BluetoothInfo>(
                    isExpanded: true,
                    value: _selectedPrinter,
                    icon: const Icon(Icons.expand_more, size: 20),
                    items: _pairedPrinters
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Row(
                                children: [
                                  const Icon(Icons.bluetooth,
                                      size: 18, color: AppColors.primary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(p.name,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600)),
                                        Text(p.macAdress,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (val) => setState(() => _selectedPrinter = val),
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
