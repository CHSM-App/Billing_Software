import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/printer_service.dart';

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

/// Convenience bool for widgets. Defaults to false while the async check is in
/// flight, so the UI degrades to "Save" rather than promising a failing print.
final printReadyProvider = Provider<bool>((ref) {
  return ref.watch(canPrintProvider).valueOrNull ?? false;
});
