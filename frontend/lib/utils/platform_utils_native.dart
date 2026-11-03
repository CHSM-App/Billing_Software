// Native implementation
import 'dart:io' show Platform;
bool get isWindows => Platform.isWindows;

/// True when running on a "desktop" device for the purpose of the device-access
/// entitlement. On native builds that means Windows (the only desktop target
/// actively distributed); Android/iOS are treated as mobile. The web build uses
/// the stub, which reports desktop.
bool get isDesktopDevice => Platform.isWindows;

/// True on iOS builds. Apple's Guideline 3.1.1 treats in-app business/org
/// account creation as access to a purchase/subscription mechanism that lives
/// outside IAP — our subscriptions are sold and managed outside the app — so
/// new-account sign-up must not be reachable from the iOS build; existing
/// customers still log in with credentials issued outside the app. Also used
/// to gate the in-app account-deletion sheet (Guideline 5.1.1(v)), which only
/// needs to exist on iOS.
bool get isIOS => Platform.isIOS;
