import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_downloader.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/model_registry_service.dart';

void main() {
  test(
    'reset preserves another installed model sharing the bundled file',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'vitalis-reset-alias-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final file = File('${sandbox.path}/disposable.gguf');
      await file.writeAsString('GGUF shared disposable fixture');
      final database = _ResetDatabase(file.path)
        ..alias = {
          'id': 'disposable-alias',
          'display_name': 'Disposable alias',
          'local_path': file.path,
          'source': 'fixture',
          'compatibility_status': 'compatible',
          'installation_state': 'installed',
        };
      final downloader = ModelDownloader(
        sentinel: _UnusedSafety(),
        registry: _Registry(file.path),
        resetRegistry: ModelRegistryService(
          database: database,
          allowedRoots: () async => [sandbox],
        ),
      );
      await downloader.resetState();
      expect(await file.exists(), isTrue);
      expect(database.row['installation_state'], 'not_installed');
      expect(database.alias!['installation_state'], 'installed');
      expect(database.alias!['local_path'], file.path);
    },
  );

  test('failed reset lookup is redacted and leaves files untouched', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'vitalis-reset-read-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final file = File('${sandbox.path}/disposable.gguf');
    await file.writeAsString('GGUF untouched disposable fixture');
    final downloader = ModelDownloader(
      sentinel: _UnusedSafety(),
      registry: _Registry(file.path)
        ..readFailure = StateError('/private/database token=secret'),
    );
    await expectLater(
      downloader.resetState(),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'redacted failure',
          isNot(contains('token=secret')),
        ),
      ),
    );
    expect(await file.exists(), isTrue);
  });

  test(
    'legacy reset cannot delete a file owned by another native writer',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'vitalis-reset-owner-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final file = File('${sandbox.path}/disposable.gguf');
      await file.writeAsString('GGUF disposable ownership fixture');
      final registry = _Registry(file.path);
      final database = _ResetDatabase(file.path);
      final downloader = ModelDownloader(
        sentinel: _UnusedSafety(),
        registry: registry,
        resetRegistry: ModelRegistryService(
          database: database,
          allowedRoots: () async => [sandbox],
        ),
      );
      await LlamaCppChatRepository.withModelFilesMutation(
        [file.path],
        () async {
          await expectLater(
            downloader.resetState(),
            throwsA(isA<InferenceRuntimeBusy>()),
          );
          expect(await file.exists(), isTrue);
          expect(database.clears, 0);
        },
      );
    },
  );

  test(
    'legacy reset reports registry projection failure instead of success',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'vitalis-reset-projection-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final file = File('${sandbox.path}/disposable.gguf');
      await file.writeAsString('GGUF disposable reset fixture');
      final database = _ResetDatabase(file.path)
        ..failure = StateError('/private/database token=secret');
      final downloader = ModelDownloader(
        sentinel: _UnusedSafety(),
        registry: _Registry(file.path),
        resetRegistry: ModelRegistryService(
          database: database,
          allowedRoots: () async => [sandbox],
        ),
      );
      await expectLater(
        downloader.resetState(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'redacted failure',
            isNot(contains('token=secret')),
          ),
        ),
      );
    },
  );
}

final class _ResetDatabase implements DatabaseHelper {
  _ResetDatabase(String path)
    : row = {
        'id': BundledModelManifest.id,
        'display_name': BundledModelManifest.displayName,
        'local_path': path,
        'source': 'fixture',
        'compatibility_status': 'compatible',
        'installation_state': 'installed',
      };
  final Map<String, dynamic> row;
  Map<String, dynamic>? alias;
  Object? failure;
  int clears = 0;
  @override
  Future<Map<String, dynamic>?> getModel(String id) async =>
      id == row['id'] ? row : alias;
  @override
  Future<List<Map<String, dynamic>>> getModels() async => [
    row,
    if (alias != null) alias!,
  ];
  @override
  Future<List<Map<String, dynamic>>> getModelFiles(String id) async => [];
  @override
  Future<void> clearModelInstallation(String id) async {
    if (failure case final Object error) throw error;
    clears++;
    row['local_path'] = null;
    row['installation_state'] = 'not_installed';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected reset database call');
}

final class _Registry implements BundledModelRegistry {
  _Registry(this.path);
  final String path;
  Object? failure;
  Object? readFailure;
  int clears = 0;

  @override
  Future<Map<String, Object?>?> read() async {
    if (readFailure case final Object error) throw error;
    return {'local_path': path};
  }

  @override
  Future<void> clearInstallation(String localPath) async {
    clears++;
    if (failure case final Object error) throw error;
  }
}

final class _UnusedSafety implements HardwareSentinelService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected safety access in reset ownership fixture');
}
