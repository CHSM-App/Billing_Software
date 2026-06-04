@echo off
REM Build Flutter web by temporarily using the web-safe pubspec
REM (excludes native-only packages: sqflite, flutter_thermal_printer, etc.)

echo Backing up pubspec.yaml...
copy /Y pubspec.yaml pubspec_native_backup.yaml

echo Switching to web pubspec...
copy /Y pubspec_web.yaml pubspec.yaml

echo Running flutter pub get for web...
call flutter pub get

echo Building web...
call flutter build web --no-tree-shake-icons

echo Restoring native pubspec...
copy /Y pubspec_native_backup.yaml pubspec.yaml
del pubspec_native_backup.yaml

echo Running flutter pub get to restore native deps...
call flutter pub get

echo Done! Web build output is in build\web\
