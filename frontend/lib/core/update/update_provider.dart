import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/remote_config_service.dart';
import '../utils/semver.dart';
import 'update_state.dart';

final updateCheckProvider = FutureProvider<UpdateState>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final rc = VittamRemoteConfig.instance;
  final currentVersion = info.version;

  final current = SemVer.tryParse(currentVersion);
  final latest = SemVer.tryParse(rc.latestVersion);

  // Unparseable RC version → treat as up-to-date (RC not configured yet)
  if (current == null || latest == null) {
    return UpdateState.upToDate(currentVersion);
  }

  final minSupported = SemVer.tryParse(rc.minimumSupportedVersion);
  final forceBelow = SemVer.tryParse(rc.forceUpdateBelowVersion);

  final bool isForce = rc.forceUpdate ||
      (minSupported != null && current < minSupported) ||
      (forceBelow != null && current < forceBelow);

  if (latest <= current) {
    return UpdateState.upToDate(currentVersion);
  }

  return UpdateState(
    updateAvailable: true,
    forceUpdate: isForce,
    currentVersion: currentVersion,
    latestVersion: rc.latestVersion,
    dialogTitle: rc.updateTitle,
    dialogMessage: rc.updateMessage,
  );
});

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});
