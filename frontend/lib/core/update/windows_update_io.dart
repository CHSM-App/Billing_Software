import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/semver.dart';
import 'update_state.dart';

/// Windows has no Firebase Remote Config plugin, so the desktop update check
/// reads a small JSON asset published with every GitHub Release instead:
///   {"version":"1.2.3","url":"https://.../VittamSetup.exe","force":false}
/// `releases/latest/download/` always redirects to the newest release's copy,
/// so rolling out an update is just pushing a `v*` tag.
const _manifestUrl =
    'https://github.com/CHSM-App/Billing_Software/releases/latest/download/windows-latest.json';

Future<UpdateState> checkWindowsUpdate(String currentVersion) async {
  if (!Platform.isWindows) return UpdateState.upToDate(currentVersion);

  final res = await http
      .get(Uri.parse(_manifestUrl))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) return UpdateState.upToDate(currentVersion);

  return parseManifest(
    jsonDecode(res.body) as Map<String, dynamic>,
    currentVersion,
  );
}

/// Pure half of [checkWindowsUpdate] — anything malformed, missing or not
/// actually newer means "up to date", never a prompt the user cannot satisfy.
@visibleForTesting
UpdateState parseManifest(Map<String, dynamic> m, String currentVersion) {
  final latest = SemVer.tryParse('${m['version'] ?? ''}');
  final current = SemVer.tryParse(currentVersion);
  final url = '${m['url'] ?? ''}';

  if (latest == null || current == null || url.isEmpty || latest <= current) {
    return UpdateState.upToDate(currentVersion);
  }

  return UpdateState(
    updateAvailable: true,
    forceUpdate: m['force'] == true,
    currentVersion: currentVersion,
    latestVersion: latest.toString(),
    dialogTitle: '${m['title'] ?? ''}',
    dialogMessage: '${m['message'] ?? ''}',
    downloadUrl: url,
  );
}

/// Downloads VittamSetup.exe, launches it silently and quits so the installer
/// can overwrite the running binaries. The installer's [Run] entry has no
/// `skipifsilent`, so it relaunches the app when it is done.
Future<void> runWindowsUpdate(
  String url,
  void Function(double) onProgress,
) async {
  final req = await http.Client().send(http.Request('GET', Uri.parse(url)));
  final total = req.contentLength ?? 0;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/VittamSetup.exe');
  final sink = file.openWrite();

  var received = 0;
  await for (final chunk in req.stream) {
    sink.add(chunk);
    received += chunk.length;
    if (total > 0) onProgress(received / total);
  }
  await sink.close();

  // Detached: the installer must outlive the app it is about to replace.
  await Process.start(
    file.path,
    ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
    mode: ProcessStartMode.detached,
  );
  exit(0);
}
