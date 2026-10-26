import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/utils/app_logger.dart';

const privateMarker = 'VITALIS_PRIVATE_BOUND_TEXT_LOG_FIXTURE';

void main() {
  for (final privacy in [true, false]) {
    for (final kind in ['note', 'persona']) {
      for (final operation in ['load', 'create', 'update', 'delete']) {
        test(
          '$kind $operation excludes error payload with privacy=$privacy',
          () async {
            final parent = await Directory.systemTemp.resolveSymbolicLinks();
            final root = await Directory(
              parent,
            ).createTemp('vitalis_privacy_logs_');
            final ownedPath = await root.resolveSymbolicLinks();
            if (!ownedPath.startsWith('$parent${Platform.pathSeparator}')) {
              throw StateError('Log fixture escaped its temporary parent');
            }
            final logger = AppLogger.forTesting(
              directoryResolver: () async => root,
              privacyLoader: () async => privacy,
              privacySaver: (_) async {},
              clock: () => DateTime.utc(2026, 10, 24),
            );
            final notes = NoteProvider(
              database: _FailingDatabase(),
              logger: logger,
            );
            final personas = PersonaProvider(
              database: _FailingDatabase(),
              logger: logger,
            );
            addTearDown(() async {
              notes.dispose();
              personas.dispose();
              await logger.flush();
              if (await root.resolveSymbolicLinks() != ownedPath) {
                throw StateError('Log fixture changed ownership');
              }
              await root.delete(recursive: true);
            });
            await logger.loadPersistedState();
            if (kind == 'note') {
              switch (operation) {
                case 'load':
                  await notes.loadNotes();
                case 'create':
                  await notes.createNote('Disposable', privateMarker);
                case 'update':
                  await notes.updateNote(
                    Note(id: 1, title: 'Disposable', content: privateMarker),
                  );
                case 'delete':
                  await notes.deleteNote(1);
              }
            } else {
              switch (operation) {
                case 'load':
                  await personas.loadPersonas();
                case 'create':
                  await personas.createPersona('Disposable', privateMarker);
                case 'update':
                  await personas.updatePersona(
                    Persona(
                      id: 1,
                      name: 'Disposable',
                      systemPrompt: privateMarker,
                    ),
                  );
                case 'delete':
                  await personas.deletePersona(1);
              }
            }
            await logger.flush();
            final logs = await logger.getLogs();
            expect(
              logs,
              contains('[ERROR]'),
              reason: 'Do not hide failure diagnostics',
            );
            expect(logs, contains('_StorageFixtureFailure'));
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
          },
        );
      }
    }
  }
}

final class _StorageFixtureFailure implements Exception {
  @override
  String toString() =>
      '_StorageFixtureFailure SQLITE_ERROR boundValues=[$privateMarker]';
}

final class _FailingDatabase implements DatabaseHelper {
  @override
  dynamic noSuchMethod(Invocation invocation) => Error.throwWithStackTrace(
    _StorageFixtureFailure(),
    StackTrace.fromString('PRIVATE_STACK $privateMarker'),
  );
}
