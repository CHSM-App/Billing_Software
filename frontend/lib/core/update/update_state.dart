class UpdateState {
  final bool updateAvailable;
  final bool forceUpdate;
  final String currentVersion;
  final String latestVersion;
  final String dialogTitle;
  final String dialogMessage;

  /// Windows installer URL. Empty on Android/iOS, where "Update now" opens the
  /// store instead of downloading anything.
  final String downloadUrl;

  const UpdateState({
    required this.updateAvailable,
    required this.forceUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.dialogTitle,
    required this.dialogMessage,
    this.downloadUrl = '',
  });

  const UpdateState.upToDate(String version)
      : updateAvailable = false,
        forceUpdate = false,
        currentVersion = version,
        latestVersion = version,
        dialogTitle = '',
        dialogMessage = '',
        downloadUrl = '';
}
