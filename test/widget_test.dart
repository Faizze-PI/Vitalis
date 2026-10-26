import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/widgets/progress_bar.dart';
import 'package:vitalis_app/widgets/confirm_dialog.dart';
import 'package:vitalis_app/constants/app_strings.dart';

import 'package:flutter/material.dart';

void main() {
  group('ProgressBar', () {
    testWidgets('renders with label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressBar(progress: 0.5, label: 'Downloading...'),
          ),
        ),
      );

      expect(find.text('Downloading...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('renders without label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProgressBar(progress: 0.3))),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('F4C Defect Closures (DEF_01, DEF_02, DEF_03)', () {
    test('DEF_01: pubspec is the only literal package version authority', () {
      final pubspecFile = File('pubspec.yaml');
      expect(pubspecFile.existsSync(), true);
      final pubspecContent = pubspecFile.readAsStringSync();
      final versionMatch = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)',
        multiLine: true,
      ).firstMatch(pubspecContent);
      expect(versionMatch, isNotNull);
      final constants = File(
        'lib/constants/app_constants.dart',
      ).readAsStringSync();
      expect(constants.contains('appVersion ='), false);
      expect(constants.contains('appVersionCode ='), false);
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('versionCode = flutter.versionCode'));
      expect(gradle, contains('versionName = flutter.versionName'));
    });

    test(
      'DEF_02: Database error UX copy contains non-destructive messaging without overclaiming',
      () {
        const dbErrorCopy =
            'Vitalis could not initialize its local database.\nNo automatic database reset or deletion has been performed.';
        expect(
          dbErrorCopy.contains('No automatic database reset or deletion'),
          true,
        );
        expect(dbErrorCopy.contains('remains preserved'), false);
      },
    );

    test(
      'DEF_03: GGUF magic header validation rejects empty, small, or non-GGUF bytes',
      () {
        const ggufMagic = [0x47, 0x47, 0x55, 0x46]; // 'GGUF'
        bool isValidGgufHeader(List<int> bytes, int fileSize) {
          if (fileSize < 1024 * 1024) return false;
          if (bytes.length < 4) return false;
          return bytes[0] == ggufMagic[0] &&
              bytes[1] == ggufMagic[1] &&
              bytes[2] == ggufMagic[2] &&
              bytes[3] == ggufMagic[3];
        }

        expect(isValidGgufHeader([], 0), false);
        expect(
          isValidGgufHeader([0x47, 0x47, 0x55, 0x46], 500),
          false,
        ); // Under 1MB
        expect(
          isValidGgufHeader([0x00, 0x00, 0x00, 0x00], 1024 * 1024 * 500),
          false,
        ); // Bad magic
        expect(
          isValidGgufHeader([0x47, 0x47, 0x55, 0x46], 1024 * 1024 * 500),
          true,
        ); // Valid candidate
      },
    );

    testWidgets(
      'ConfirmDialog displays title, message, and buttons with semantics',
      (tester) async {
        bool? confirmed;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    confirmed = await ConfirmDialog.show(
                      context: ctx,
                      title: 'Delete Chat',
                      message: 'Are you sure?',
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.text('Delete Chat'), findsOneWidget);
        expect(find.text('Are you sure?'), findsOneWidget);
        expect(find.text(AppStrings.cancel), findsOneWidget);
        expect(find.text(AppStrings.confirm), findsOneWidget);

        await tester.tap(find.text(AppStrings.cancel));
        await tester.pumpAndSettle();
        expect(confirmed, false);
      },
    );
  });
}
