// Web: the browser keeps secure storage itself — nothing to back up.
bool get backupSupported => false;
Future<void> snapshot() async {}
Future<bool> restore(Object reason) async => false;
Future<bool> liveMissing() async => false;
