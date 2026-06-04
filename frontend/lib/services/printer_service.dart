// Conditional import: use the web stub on web, the native implementation elsewhere.
export 'printer_service_web.dart'
    if (dart.library.io) 'printer_service_native.dart';
