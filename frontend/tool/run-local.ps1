# Runs the app against a LOCAL backend without editing source.
# Change $LocalUrl to your machine's LAN IP if it differs.
#
#   ./tool/run-local.ps1              # runs on default device
#   ./tool/run-local.ps1 -d chrome    # pass extra flutter args through
#
# A normal `flutter run` / `flutter build` (no override) always uses the
# production URL baked into api.dart's defaultValue.

param([Parameter(ValueFromRemainingArguments = $true)] $Args)

$LocalUrl = 'http://192.168.0.194:5000/api'
flutter run --dart-define=API_BASE_URL=$LocalUrl @Args
