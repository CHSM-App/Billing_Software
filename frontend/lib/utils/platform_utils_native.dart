// Native implementation
import 'dart:io' show Platform;
bool get isWindows => Platform.isWindows;

/// True when running on a "desktop" device for the purpose of the device-access
/// entitlement. On native builds that means Windows (the only desktop target
/// actively distributed); Android/iOS are treated as mobile. The web build uses
/// the stub, which reports desktop.
bool get isDesktopDevice => Platform.isWindows;
