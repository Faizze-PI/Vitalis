import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/application_private_directory.dart';

void main() {
  for (final windows in [true, false]) {
    test(
      'private storage selects the correct platform adapter: $windows',
      () async {
        final expected = Directory.systemTemp;
        final result = await applicationPrivateDirectory(
          isWindows: windows,
          supportDirectory: () async {
            expect(windows, isTrue);
            return expected;
          },
          documentsDirectory: () async {
            expect(windows, isFalse);
            return expected;
          },
        );
        expect(identical(result, expected), isTrue);
      },
    );
  }
}
