// Web stub
bool get isWindows => false;

/// Web runs in a browser on a desktop/laptop, so for the device-access
/// entitlement it is treated as a desktop device.
bool get isDesktopDevice => true;
