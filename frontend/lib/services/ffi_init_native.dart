import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initFfi() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
