import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class PlatformModelFolderOpener {
  bool get isAvailable;
  Future<void> open();
}

class ApplicationModelFolderOpener implements PlatformModelFolderOpener {
  const ApplicationModelFolderOpener();

  @override
  bool get isAvailable => Platform.isWindows || Platform.isLinux;

  @override
  Future<void> open() async {
    if (!isAvailable) {
      throw UnsupportedError('Open Model Folder is available on desktop only');
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'models'));
    await directory.create(recursive: true);
    final executable = Platform.isWindows ? 'explorer.exe' : 'xdg-open';
    final result = await Process.run(executable, [directory.path]);
    if (result.exitCode != 0) {
      throw StateError('The model folder could not be opened');
    }
  }
}
