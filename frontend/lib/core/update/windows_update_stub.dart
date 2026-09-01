import 'update_state.dart';

/// Web/other platforms — Windows self-update does not apply.
Future<UpdateState> checkWindowsUpdate(String currentVersion) async =>
    UpdateState.upToDate(currentVersion);

Future<void> runWindowsUpdate(
  String url,
  void Function(double) onProgress,
) async {}
