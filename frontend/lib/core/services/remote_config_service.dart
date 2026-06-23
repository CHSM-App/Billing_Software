import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class VittamRemoteConfig {
  VittamRemoteConfig._();
  static final VittamRemoteConfig instance = VittamRemoteConfig._();

  static const _keyLatestVersion = 'latest_version';
  static const _keyMinSupportedVersion = 'minimum_supported_version';
  static const _keyUpdateTitle = 'update_title';
  static const _keyUpdateMessage = 'update_message';
  static const _keyForceUpdate = 'force_update';
  static const _keyForceUpdateBelowVersion = 'force_update_below_version';

  late final FirebaseRemoteConfig _rc;

  Future<void> initialize() async {
    _rc = FirebaseRemoteConfig.instance;
    await _rc.setDefaults({
      _keyLatestVersion: '',
      _keyMinSupportedVersion: '',
      _keyUpdateTitle: 'नया अपडेट उपलब्ध है',
      _keyUpdateMessage: 'बेहतर अनुभव के लिए कृपया ऐप को अपडेट करें।',
      _keyForceUpdate: false,
      _keyForceUpdateBelowVersion: '',
    });
    await _rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval:
          kDebugMode ? Duration.zero : const Duration(hours: 1),
    ));
    await fetchAndActivate();
  }

  Future<void> fetchAndActivate() async {
    try {
      await _rc.fetchAndActivate();
    } catch (e) {
      debugPrint('RemoteConfig fetchAndActivate error: $e');
    }
  }

  Future<void> refresh() => fetchAndActivate();

  String get latestVersion => _rc.getString(_keyLatestVersion);
  String get minimumSupportedVersion =>
      _rc.getString(_keyMinSupportedVersion);
  String get updateTitle => _rc.getString(_keyUpdateTitle);
  String get updateMessage => _rc.getString(_keyUpdateMessage);
  bool get forceUpdate => _rc.getBool(_keyForceUpdate);
  String get forceUpdateBelowVersion =>
      _rc.getString(_keyForceUpdateBelowVersion);
}
