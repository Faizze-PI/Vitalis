import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keep Android's established paths; desktop app data belongs in user support.
Future<Directory> applicationPrivateDirectory({
  bool? isWindows,
  Future<Directory> Function()? supportDirectory,
  Future<Directory> Function()? documentsDirectory,
}) => (isWindows ?? Platform.isWindows)
    ? (supportDirectory ?? getApplicationSupportDirectory)()
    : (documentsDirectory ?? getApplicationDocumentsDirectory)();
