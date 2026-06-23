class UpdateState {
  final bool updateAvailable;
  final bool forceUpdate;
  final String currentVersion;
  final String latestVersion;
  final String dialogTitle;
  final String dialogMessage;

  const UpdateState({
    required this.updateAvailable,
    required this.forceUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.dialogTitle,
    required this.dialogMessage,
  });

  const UpdateState.upToDate(String version)
      : updateAvailable = false,
        forceUpdate = false,
        currentVersion = version,
        latestVersion = version,
        dialogTitle = '',
        dialogMessage = '';
}
