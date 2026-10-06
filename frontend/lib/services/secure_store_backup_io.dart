import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Crash-safe backup of flutter_secure_storage's Windows file.
//
// On Windows the plugin keeps every secure key (the login tokens included) in
// ONE file and rewrites it in place: truncate, then write. If the app is
// killed mid-write — closing the window or stopping it from the IDE while a
// focus-triggered license refresh is saving — the file is left torn. The next
// read cannot decrypt it, so the plugin DELETES it and the user is logged out.
//
// After each successful write we copy the good file to a backup via
// temp-file + rename (a rename is atomic, so the backup is never torn); when
// the live file is unreadable or missing we put the backup back. Other
// platforms store keys natively and need none of this.

const _fileName = 'flutter_secure_storage.dat'; // the plugin's own file name

bool get backupSupported => Platform.isWindows;

Future<String> _livePath() async =>
    p.join((await getApplicationSupportDirectory()).path, _fileName);

/// Atomically replaces [to] with a copy of [from].
Future<void> _atomicCopy(File from, String to) async {
  final tmp = '$to.tmp';
  await from.copy(tmp);
  await File(tmp).rename(to);
}

/// Back up the live file after a successful write; drop the backup when the
/// live file is gone (logout cleared the store).
Future<void> snapshot() async {
  if (!backupSupported) return;
  final live = File(await _livePath());
  final backup = '${live.path}.bak';
  if (await live.exists()) {
    await _atomicCopy(live, backup);
  } else if (await File(backup).exists()) {
    await File(backup).delete();
  }
}

/// Put the backup back in place of a torn or deleted live file. Returns false
/// when there is no backup to restore.
Future<bool> restore(Object reason) async {
  if (!backupSupported) return false;
  final live = await _livePath();
  final backup = File('$live.bak');
  if (!await backup.exists()) return false;
  debugPrint('[SECURE] token store unreadable ($reason) — restoring backup');
  await _atomicCopy(backup, live);
  return true;
}

/// True when the live file is missing but a backup exists — the plugin
/// already deleted a torn file on an earlier run.
Future<bool> liveMissing() async {
  if (!backupSupported) return false;
  final live = await _livePath();
  return !await File(live).exists() && await File('$live.bak').exists();
}
