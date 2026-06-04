// Conditional import: use the web stub on web, the SQLite implementation elsewhere.
export 'offline_service_web.dart'
    if (dart.library.io) 'offline_service_native.dart';
