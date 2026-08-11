import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/printer_service.dart';
import '../storage.dart';

/// Watches the service's active-printer revision inside [ref]: registers a
/// listener that rebuilds the provider whenever the printer is selected or
/// cleared (anywhere — the setup page, Settings). Call at the top of any
/// provider that must reflect the current printer.
void _watchPrinterRevision(Ref ref) {
  final notifier = PrinterService.instance.activePrinterRevision;
  void listener() => ref.invalidateSelf();
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));
}

/// The currently configured receipt printer, or null when none is set up.
/// Rebuilds when the active printer changes. Reflects saved settings only — for
/// "can a print actually happen right now" use [canPrintProvider].
final activePrinterProvider = FutureProvider<Printer?>((ref) {
  _watchPrinterRevision(ref);
  return PrinterService.instance.getActivePrinter();
});

/// Whether a receipt could actually print right now: a printer is configured
/// AND (on Bluetooth platforms) permission is granted and Bluetooth is on.
///
/// Rebuilds automatically when the active printer changes (selected/removed).
/// Bluetooth on/off isn't observable here, so app resume and a failed print
/// still invalidate this provider directly to catch those.
final canPrintProvider = FutureProvider<bool>((ref) {
  _watchPrinterRevision(ref);
  return PrinterService.instance.canPrint();
});

/// The chosen print paper size (e.g. 'mm80', 'a4'). Rebuilds when the printer
/// settings change (the size is edited on the same setup screen, which bumps
/// the printer revision).
final paperSizeProvider = FutureProvider<String>((ref) {
  _watchPrinterRevision(ref);
  return getPaperSize();
});

/// True when the selected size is a PDF page size (A5/A4) rather than a thermal
/// roll. PDF output doesn't require a paired thermal printer.
final pdfPaperSelectedProvider = Provider<bool>((ref) {
  final size = ref.watch(paperSizeProvider).valueOrNull;
  return size != null && !PaperSizes.isThermal(size);
});

/// Convenience bool for widgets: the primary finalize action should offer
/// "Print" when a thermal printer is ready OR a PDF size is selected (the PDF
/// path opens the OS dialog and needs no thermal printer). Defaults to false
/// while the async checks are in flight, so it degrades to "Save".
final printReadyProvider = Provider<bool>((ref) {
  final thermalReady = ref.watch(canPrintProvider).valueOrNull ?? false;
  final pdf = ref.watch(pdfPaperSelectedProvider);
  return thermalReady || pdf;
});
