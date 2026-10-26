import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/application_error_reporter.dart';
import 'package:vitalis_app/utils/app_logger.dart';

const privateMarker = 'PRIVATE_GLOBAL_ERROR_PAYLOAD_FIXTURE';

void main() {
  for (final privacy in [true, false]) {
    for (final boundary in ['framework', 'frameworkDefault', 'platform']) {
      final framework = boundary != 'platform';
      final useDefaultConsole = boundary == 'frameworkDefault';
      test('$boundary diagnostics exclude payload privacy=$privacy', () async {
        final parent = await Directory.systemTemp.resolveSymbolicLinks();
        final root = await Directory(
          parent,
        ).createTemp('vitalis_error_boundary_');
        final owned = await root.resolveSymbolicLinks();
        if (!owned.startsWith('$parent${Platform.pathSeparator}')) {
          throw StateError('Fixture escaped temporary parent');
        }
        final logger = AppLogger.forTesting(
          directoryResolver: () async => root,
          privacyLoader: () async => privacy,
          privacySaver: (_) async {},
          clock: () => DateTime.utc(2026, 10, 24),
        );
        addTearDown(() async {
          await logger.flush();
          if (await root.resolveSymbolicLinks() != owned) {
            throw StateError('Fixture ownership changed');
          }
          await root.delete(recursive: true);
        });
        await logger.loadPersistedState();
        final presented = <FlutterErrorDetails>[];
        final printed = <String>[];
        final previousPresenter = FlutterError.presentError;
        final previousPrint = debugPrint;
        addTearDown(() {
          FlutterError.presentError = previousPresenter;
          debugPrint = previousPrint;
          FlutterError.resetErrorCount();
        });
        if (useDefaultConsole) {
          debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
        }
        final reporter = ApplicationErrorReporter(
          logger: logger,
          presenter: useDefaultConsole ? null : presented.add,
        );
        if (useDefaultConsole) {
          FlutterError.presentError = (details) {
            presented.add(details);
            FlutterError.dumpErrorToConsole(details, forceReport: true);
          };
        }
        final failure = _PrivateFixtureFailure();
        final stack = StackTrace.fromString('PRIVATE_STACK $privateMarker');
        if (framework) {
          reporter.framework(
            FlutterErrorDetails(
              exception: failure,
              stack: stack,
              library: privateMarker,
              silent: privacy,
              context: ErrorDescription(privateMarker),
              informationCollector: () => [
                StringProperty('private', privateMarker),
              ],
            ),
          );
          expect(
            presented,
            hasLength(1),
            reason:
                'Default presenter changes after construction remain effective',
          );
          final safe = presented.single;
          expect(safe.silent, privacy);
          expect(safe.stack, isNotNull);
          expect(
            safe.stack.toString(),
            isEmpty,
            reason: 'Default presenter must not synthesize a fresh stack',
          );
          final console = [
            safe.exceptionAsString(),
            '${safe.stack}',
            '${safe.library}',
            '${safe.context}',
            '${safe.informationCollector?.call().toList()}',
          ].join('\n');
          expect(console, isNot(contains(privateMarker)));
          expect(console, contains('_PrivateFixtureFailure'));
          if (useDefaultConsole) {
            expect(printed, isNotEmpty);
            expect(printed.join('\n'), isNot(contains(privateMarker)));
            expect(printed.join('\n'), contains('_PrivateFixtureFailure'));
          }
        } else {
          expect(reporter.platform(failure, stack), isTrue);
          expect(presented, isEmpty);
        }
        await logger.flush();
        final logs = await logger.getLogs();
        expect(logs, contains('[ERROR]'));
        expect(logs, contains('_PrivateFixtureFailure'));
        expect(logs, isNot(contains(privateMarker)));
        final files = await root
            .list(recursive: true)
            .where((entity) => entity is File)
            .cast<File>()
            .toList();
        expect(files, isNotEmpty);
        for (final file in files) {
          expect(await file.readAsString(), isNot(contains(privateMarker)));
        }
      });
    }
  }
}

final class _PrivateFixtureFailure implements Exception {
  @override
  String toString() => '_PrivateFixtureFailure $privateMarker';
}
