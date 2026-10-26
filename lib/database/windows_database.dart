import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs inside the observable startup database task, after the first frame.
Future<void> initializeWindowsDatabase({
  Future<Directory> Function()? supportDirectory,
  bool? isWindows,
}) async {
  if (!(isWindows ?? Platform.isWindows)) return;
  final directory =
      await (supportDirectory ?? getApplicationSupportDirectory)();
  await directory.create(recursive: true);
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await databaseFactory.setDatabasesPath(directory.path);
}
