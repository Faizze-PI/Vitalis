import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/models/model_verification_phase.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';
import 'package:vitalis_app/services/runtime_profile_store.dart';

void main() {
  late Directory sandbox;
  late Directory documents;
  late _Probe probe;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = Directory.systemTemp.createTempSync('vitalis_registry_full_');
    documents = Directory(p.join(sandbox.path, 'documents'))
      ..createSync(recursive: true);
    await databaseFactory.setDatabasesPath(sandbox.path);
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    final database = File(p.join(sandbox.path, 'vitalis.db'));
    if (await database.exists()) await database.delete();
    final models = Directory(p.join(documents.path, 'models'));
    if (await models.exists()) await models.delete(recursive: true);
    probe = _Probe();
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  ModelRegistryService registry({
    ModelImportPicker? picker,
    GgufMetadataReader? metadata,
    _Probe? runtime,
    Duration probeDeadline = const Duration(seconds: 30),
    ModelRootResolver? roots,
    RuntimeProfileStore? profiles,
    RuntimeCapabilitiesProvider? capabilities,
    void Function()? safetyCheck,
    Stream<bool>? safetyChanges,
  }) => ModelRegistryService(
    database: DatabaseHelper.instance,
    profileStore: profiles ?? _Profiles(),
    capabilitiesProvider: capabilities ?? const _Capabilities(),
    allowedRoots:
        roots ?? () async => [Directory(p.join(documents.path, 'models'))],
    documentsDirectory: () async => documents,
    importPicker: picker ?? () async => null,
    metadataReader: metadata ?? (_) async => _metadata(),
    probeFactory:
        ({required String modelPath, required RuntimeProfile profile}) =>
            (runtime ?? probe).repository(modelPath, profile),
    clock: () => DateTime.utc(2026, 2, 3),
    probeDeadline: probeDeadline,
    checkProbeSafety: safetyCheck ?? () {},
    probeSafetyChanges: safetyChanges,
  );

  for (final reason in ['policy', 'memory']) {
    test(
      'unsafe $reason rejects native verification without changing the model',
      () async {
        final file = File(p.join(documents.path, 'model.gguf'));
        await file.writeAsString('GGUFpayload');
        await _insertModel(
          'verify',
          file.path,
          hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
        );
        final before = await DatabaseHelper.instance.getModel('verify');
        final service = registry(
          safetyCheck: reason == 'policy'
              ? () => throw StateError('fixture safety denial')
              : null,
          capabilities: _Capabilities(severe: reason == 'memory'),
        );
        await expectLater(
          service.verifyInstallation('verify'),
          throwsA(isA<ModelProbeSafetyStop>()),
        );
        expect(probe.repositoryCalls, 0);
        expect(await DatabaseHelper.instance.getModel('verify'), before);
      },
    );
  }

  test(
    'bundled installation rejects non-publisher bytes without changing saved identity',
    () async {
      final previous = p.join(documents.path, 'previous.gguf');
      await _insertModel(
        BundledModelManifest.id,
        previous,
        size: BundledModelManifest.byteSize,
        hash: BundledModelManifest.sha256,
      );
      final before = await DatabaseHelper.instance.getModel(
        BundledModelManifest.id,
      );
      final candidate = File(p.join(documents.path, 'candidate.gguf'));
      await candidate.writeAsString('GGUF non-publisher fixture');
      final service = registry();
      await expectLater(
        service.installBundledModel(candidate.path),
        throwsA(anything),
      );
      expect(
        await DatabaseHelper.instance.getModel(BundledModelManifest.id),
        before,
      );
      expect(probe.repositoryCalls, 0);
      expect(await candidate.readAsString(), 'GGUF non-publisher fixture');
      await service.close();
    },
  );

  test(
    'disposed bundled installer rejects before file or registry work',
    () async {
      final before = await DatabaseHelper.instance.getModel(
        BundledModelManifest.id,
      );
      final service = registry();
      await service.close();
      await expectLater(
        service.installBundledModel('missing-fixture.gguf'),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      expect(probe.repositoryCalls, 0);
      expect(
        await DatabaseHelper.instance.getModel(BundledModelManifest.id),
        before,
      );
    },
  );

  test(
    'bundled installation cannot reinterpret a saved different-content identity',
    () async {
      await _insertModel(
        BundledModelManifest.id,
        'preserved-fixture.gguf',
        hash: 'different-content-hash',
      );
      final before = await DatabaseHelper.instance.getModel(
        BundledModelManifest.id,
      );
      final service = registry();
      await expectLater(
        service.installBundledModel('missing-candidate.gguf'),
        throwsA(isA<ModelIdentityMismatch>()),
      );
      expect(
        await DatabaseHelper.instance.getModel(BundledModelManifest.id),
        before,
      );
      expect(probe.repositoryCalls, 0);
      await service.close();
    },
  );

  test(
    'missing safety authority blocks a default native probe without changing records',
    () async {
      final file = File(p.join(documents.path, 'model.gguf'));
      await file.writeAsString('GGUFpayload');
      await _insertModel(
        'verify',
        file.path,
        hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
      );
      final before = await DatabaseHelper.instance.getModel('verify');
      final service = ModelRegistryService(
        metadataReader: (_) async => _metadata(),
        capabilitiesProvider: const _Capabilities(),
      );
      await expectLater(
        service.verifyInstallation('verify'),
        throwsA(isA<ModelProbeSafetyStop>()),
      );
      expect(await DatabaseHelper.instance.getModel('verify'), before);
      await service.close();
    },
  );

  for (final stop in ['unsafe', 'closed', 'error']) {
    test(
      'probe safety $stop retains preparation until shutdown acknowledges',
      () async {
        final file = File(p.join(documents.path, 'model.gguf'));
        await file.writeAsString('GGUFpayload');
        await _insertModel(
          'verify',
          file.path,
          hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
        );
        final before = await DatabaseHelper.instance.getModel('verify');
        final safety = StreamController<bool>();
        probe.prepareGate = Completer<void>();
        probe.closeAcknowledgement = Completer<void>();
        final service = registry(safetyChanges: safety.stream);
        final result = service
            .verifyInstallation('verify')
            .then<Object?>((value) => value, onError: (Object error) => error);
        await probe.prepareStarted.future;
        if (stop == 'closed') {
          unawaited(safety.close());
        } else if (stop == 'error') {
          safety.addError(StateError('fixture observation lost'));
        } else {
          safety.add(false);
        }
        await probe.closeStarted.future;
        expect(probe.generateCalls, 0);
        expect(probe.prepareGate!.isCompleted, isFalse);
        expect(await DatabaseHelper.instance.getModel('verify'), before);
        probe.closeAcknowledgement!.complete();
        expect(await result, isA<ModelProbeSafetyStop>());
        expect(service.requiresProbeRecovery, isFalse);
        expect(await DatabaseHelper.instance.getModel('verify'), before);
        await service.close();
        await safety.close();
      },
    );
  }

  for (final cleanupFails in [false, true]) {
    test(
      'unsafe probe decoding preserves records and retains failed cleanup ($cleanupFails)',
      () async {
        final file = File(p.join(documents.path, 'model.gguf'));
        await file.writeAsString('GGUFpayload');
        await _insertModel(
          'verify',
          file.path,
          hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
        );
        final before = await DatabaseHelper.instance.getModel('verify');
        final safety = StreamController<bool>();
        probe.stalled = Completer<void>();
        probe.closeInterruptsGeneration = true;
        probe.closeSuppressesOutput = true;
        probe.closeAcknowledgement = Completer<void>();
        probe.failClose = cleanupFails;
        final service = registry(safetyChanges: safety.stream);
        final result = service
            .verifyInstallation('verify')
            .then<Object?>((value) => value, onError: (Object error) => error);
        await probe.generationStarted.future;
        safety.add(false);
        await probe.closeStarted.future;
        expect(probe.stalled!.isCompleted, isFalse);
        expect(await DatabaseHelper.instance.getModel('verify'), before);
        probe.closeAcknowledgement!.complete();
        expect(
          await result,
          cleanupFails
              ? isA<InferenceRecoveryRequired>()
              : isA<ModelProbeSafetyStop>(),
        );
        expect(service.requiresProbeRecovery, cleanupFails);
        expect(await DatabaseHelper.instance.getModel('verify'), before);
        if (cleanupFails) {
          await expectLater(
            service.verifyInstallation('verify'),
            throwsA(isA<InferenceRecoveryRequired>()),
          );
          expect(
            await service.recoverProbeCleanup(),
            RuntimeRecoveryOutcome.recovered,
          );
        }
        await service.close();
        await safety.close();
      },
    );
  }

  test(
    'missing-file recovery preserves identity only for exact bytes',
    () async {
      final bytes = 'GGUFpayload'.codeUnits;
      final missing = p.join(documents.path, 'models', 'lost.gguf');
      await _insertModel(
        'saved-identity',
        missing,
        size: bytes.length,
        hash: sha256.convert(bytes).toString(),
      );
      final service = registry(
        picker: () async => ImportedModelFile(
          name: 'replacement.gguf',
          size: bytes.length,
          readStream: Stream.value(bytes),
        ),
      );
      final restored = await service.restoreMissingFile('saved-identity');
      expect(restored?.id, 'saved-identity');
      expect(restored?.localPath, isNot(missing));
      expect(await File(restored!.localPath!).readAsBytes(), bytes);
      expect(
        (await service.findById('saved-identity'))?.localPath,
        restored.localPath,
      );
    },
  );

  test(
    'replacement rejects an oversized stream before accepting later chunks',
    () async {
      final missing = p.join(documents.path, 'models', 'lost.gguf');
      await _insertModel('saved-identity', missing, size: 4);
      final before = await DatabaseHelper.instance.getModel('saved-identity');
      var laterChunkRead = false;
      Stream<List<int>> input() async* {
        yield 'GGUFoverflow'.codeUnits;
        laterChunkRead = true;
        yield 'unwanted'.codeUnits;
      }

      final service = registry(
        picker: () async => ImportedModelFile(
          name: 'oversized.gguf',
          size: 4,
          readStream: input(),
        ),
      );
      await expectLater(
        service.restoreMissingFile('saved-identity'),
        throwsA(isA<ModelIdentityMismatch>()),
      );
      expect(laterChunkRead, isFalse);
      expect(await DatabaseHelper.instance.getModel('saved-identity'), before);
    },
  );

  test(
    'registered single-file Hub model can restore its exact artifact',
    () async {
      final bytes = 'GGUFpayload'.codeUnits;
      final hash = sha256.convert(bytes).toString();
      final missing = p.join(documents.path, 'models', 'lost-hub.gguf');
      await _insertModel('saved-hub', missing, size: bytes.length, hash: hash);
      await DatabaseHelper.instance.replaceModelFiles('saved-hub', [
        {
          'file_name': 'weights.gguf',
          'local_path': missing,
          'byte_size': bytes.length,
          'sha256': hash,
          'shard_index': 0,
          'shard_count': 1,
          'etag': 'immutable-entity',
        },
      ]);
      final service = registry(
        picker: () async => ImportedModelFile(
          name: 'replacement.gguf',
          size: bytes.length,
          readStream: Stream.value(bytes),
        ),
      );
      final restored = await service.restoreMissingFile('saved-hub');
      expect(restored?.id, 'saved-hub');
      expect(await File(restored!.localPath!).readAsBytes(), bytes);
      final artifact = (await DatabaseHelper.instance.getModelFiles(
        'saved-hub',
      )).single;
      expect(artifact['local_path'], restored.localPath);
      expect(artifact['file_name'], 'weights.gguf');
      expect(artifact['sha256'], hash);
      expect(artifact['etag'], 'immutable-entity');
      expect(
        (await service.verifyInstallation('saved-hub')).isInstalled,
        isTrue,
      );
    },
  );

  test('restoration owns the picker until disposal drains it', () async {
    final missing = p.join(documents.path, 'models', 'lost.gguf');
    await _insertModel('saved-identity', missing);
    final picked = Completer<ImportedModelFile?>();
    final entered = Completer<void>();
    final service = registry(
      picker: () {
        entered.complete();
        return picked.future;
      },
    );
    final operation = service
        .restoreMissingFile('saved-identity')
        .then<Object?>((value) => value, onError: (Object error) => error);
    await entered.future;
    await expectLater(
      registry().restoreMissingFile('saved-identity'),
      throwsA(isA<ModelStorageBusy>()),
    );
    var closed = false;
    final closing = service.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    picked.complete(null);
    expect(await operation, isA<InferenceRepositoryDisposed>());
    await closing;
    expect(closed, isTrue);
    expect((await service.findById('saved-identity'))?.localPath, missing);
  });

  test('single-file picker cannot restore a registered shard set', () async {
    final missing = p.join(documents.path, 'models', 'lost.gguf');
    await _insertModel('saved-identity', missing);
    await DatabaseHelper.instance.replaceModelFiles('saved-identity', [
      {
        'file_name': 'shard.gguf',
        'local_path': missing,
        'shard_index': 0,
        'shard_count': 2,
      },
    ]);
    var pickerCalls = 0;
    final service = registry(
      picker: () async {
        pickerCalls++;
        return null;
      },
    );
    await expectLater(
      service.restoreMissingFile('saved-identity'),
      throwsStateError,
    );
    expect(pickerCalls, 0);
    expect(
      (await DatabaseHelper.instance.getModelFiles(
        'saved-identity',
      )).single['local_path'],
      missing,
    );
  });

  test(
    'replacement rejects present files and unavailable identity before picking',
    () async {
      final file = File(p.join(documents.path, 'present.gguf'));
      await file.writeAsString('GGUFpayload');
      await _insertModel('present', file.path);
      await _insertModel('no-path', null);
      await DatabaseHelper.instance.upsertModel({
        'id': 'no-hash',
        'display_name': 'Unknown',
        'source': 'fixture',
        'local_path': '${documents.path}/missing.gguf',
        'compatibility_status': 'unvalidated',
      });
      var picks = 0;
      final service = registry(
        picker: () async {
          picks++;
          return null;
        },
      );
      for (final id in ['absent', 'present', 'no-path', 'no-hash']) {
        await expectLater(service.restoreMissingFile(id), throwsStateError);
      }
      expect(picks, 0);
      expect(await file.readAsString(), 'GGUFpayload');
    },
  );

  test(
    'replacement cleanup quarantine retains staging until native acknowledgement',
    () async {
      final bytes = 'GGUFpayload'.codeUnits;
      final missing = p.join(documents.path, 'models', 'lost.gguf');
      await _insertModel(
        'saved-identity',
        missing,
        size: bytes.length,
        hash: sha256.convert(bytes).toString(),
      );
      final before = await DatabaseHelper.instance.getModel('saved-identity');
      probe.failClose = true;
      final service = registry(
        picker: () async => ImportedModelFile(
          name: 'replacement.gguf',
          size: bytes.length,
          readStream: Stream.value(bytes),
        ),
      );
      await expectLater(
        service.restoreMissingFile('saved-identity'),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(service.requiresProbeRecovery, isTrue);
      final models = Directory(p.join(documents.path, 'models'));
      expect(models.listSync().whereType<Directory>(), hasLength(1));
      expect(await DatabaseHelper.instance.getModel('saved-identity'), before);
      await expectLater(
        service.restoreMissingFile('saved-identity'),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(
        await service.recoverProbeCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(models.listSync(), isEmpty);
    },
  );

  test('different replacement leaves missing identity untouched', () async {
    final expected = 'GGUFpayload'.codeUnits;
    final different = 'GGUFchanged'.codeUnits;
    final missing = p.join(documents.path, 'models', 'lost.gguf');
    await _insertModel(
      'saved-identity',
      missing,
      hash: sha256.convert(expected).toString(),
    );
    final before = await DatabaseHelper.instance.getModel('saved-identity');
    final service = registry(
      picker: () async => ImportedModelFile(
        name: 'different.gguf',
        size: different.length,
        readStream: Stream.value(different),
      ),
    );
    await expectLater(
      service.restoreMissingFile('saved-identity'),
      throwsA(isA<ModelIdentityMismatch>()),
    );
    expect(await DatabaseHelper.instance.getModel('saved-identity'), before);
    expect(await File(missing).exists(), isFalse);
  });

  test(
    'cancelled replacement picker leaves missing identity untouched',
    () async {
      final missing = p.join(documents.path, 'models', 'lost.gguf');
      await _insertModel('saved-identity', missing);
      final before = await DatabaseHelper.instance.getModel('saved-identity');
      final service = registry(picker: () async => null);
      expect(await service.restoreMissingFile('saved-identity'), isNull);
      expect(await DatabaseHelper.instance.getModel('saved-identity'), before);
    },
  );

  test('failed replacement probe cannot activate missing identity', () async {
    final bytes = 'GGUFpayload'.codeUnits;
    final missing = p.join(documents.path, 'models', 'lost.gguf');
    await _insertModel(
      'saved-identity',
      missing,
      size: bytes.length,
      hash: sha256.convert(bytes).toString(),
    );
    final before = await DatabaseHelper.instance.getModel('saved-identity');
    probe.failGeneration = true;
    final service = registry(
      picker: () async => ImportedModelFile(
        name: 'replacement.gguf',
        size: bytes.length,
        readStream: Stream.value(bytes),
      ),
    );
    await expectLater(
      service.restoreMissingFile('saved-identity'),
      throwsStateError,
    );
    expect(await DatabaseHelper.instance.getModel('saved-identity'), before);
    expect(await File(missing).exists(), isFalse);
  });

  test(
    'uninstall preserves files referenced by another model identity',
    () async {
      final file = File(p.join(documents.path, 'models', 'shared.gguf'));
      await file.parent.create(recursive: true);
      await file.writeAsString('GGUFpayload');
      await _insertModel('first-owner', file.path);
      await _insertModel('second-owner', file.path);
      final service = registry();
      await service.uninstall('first-owner');
      expect(await file.exists(), isTrue);
      expect(
        (await service.requireInstalled('second-owner')).id,
        'second-owner',
      );
      expect((await service.findById('first-owner'))?.isInstalled, isFalse);
      await service.uninstall('second-owner');
      expect(await file.exists(), isFalse);
    },
  );

  test('failed native cleanup still drains every admitted reader', () async {
    final firstFile = File(
      p.join(documents.path, 'models', 'drain-first.gguf'),
    );
    final secondFile = File(
      p.join(documents.path, 'models', 'drain-second.gguf'),
    );
    for (final file in [firstFile, secondFile]) {
      await file.parent.create(recursive: true);
      await file.writeAsString('GGUFpayload');
      await _insertModel(
        p.basenameWithoutExtension(file.path),
        file.path,
        hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
      );
    }
    final entered = [Completer<void>(), Completer<void>()];
    final metadata = [Completer<GgufMetadata>(), Completer<GgufMetadata>()];
    probe.failClose = true;
    probe.closeAcknowledgement = Completer<void>();
    final service = registry(
      metadata: (path) {
        final index = path == firstFile.path ? 0 : 1;
        entered[index].complete();
        return metadata[index].future;
      },
    );
    final before = await DatabaseHelper.instance.getModel('drain-second');
    final first = service
        .verifyInstallation('drain-first')
        .then<Object?>((value) => value, onError: (Object error) => error);
    final second = service
        .verifyInstallation('drain-second')
        .then<Object?>((value) => value, onError: (Object error) => error);
    await Future.wait(entered.map((signal) => signal.future));
    metadata[0].complete(_metadata());
    await probe.closeStarted.future;
    var settled = false;
    final closing = service.close().then<Object?>(
      (_) {
        settled = true;
        return null;
      },
      onError: (Object error) {
        settled = true;
        return error;
      },
    );
    probe.closeAcknowledgement!.complete();
    try {
      expect(await first, isA<InferenceRecoveryRequired>());
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      expect(service.requiresProbeRecovery, isTrue);
    } finally {
      metadata[1].complete(_metadata());
      await second;
      await closing;
    }
    expect(await second, isA<InferenceRepositoryDisposed>());
    expect(await closing, isA<InferenceRecoveryRequired>());
    expect(await DatabaseHelper.instance.getModel('drain-second'), before);
    expect(await secondFile.exists(), isTrue);
    expect(
      await service.recoverProbeCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
  });

  test(
    'shutdown during import capabilities prevents probe construction',
    () async {
      final capabilities = _WaitingCapabilities();
      final service = registry(
        picker: _validPicker,
        capabilities: capabilities,
      );
      final before = (await service.listModels())
          .map((model) => model.toMap())
          .toList();
      final observed = service.importGguf().then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
      await capabilities.entered.future;
      final closing = service.close();
      capabilities.result.complete(await const _Capabilities().snapshot());
      expect(await observed, isA<InferenceRepositoryDisposed>());
      await closing;
      expect(probe.repositoryCalls, 0);
      expect(
        (await service.listModels()).map((model) => model.toMap()).toList(),
        before,
      );
      final models = Directory(p.join(documents.path, 'models'));
      expect(models.listSync(), isEmpty);
    },
  );

  test('import and uninstall reject overlapping storage ownership', () async {
    final file = File(p.join(documents.path, 'models', 'owned.gguf'));
    await file.parent.create(recursive: true);
    await file.writeAsString('GGUFpayload');
    await _insertModel('owned', file.path);
    final picked = Completer<ImportedModelFile?>();
    final importing = registry(picker: () => picked.future).importGguf();
    await expectLater(
      registry().uninstall('owned'),
      throwsA(isA<ModelStorageBusy>()),
    );
    expect(await file.exists(), isTrue);
    picked.complete(null);
    await importing;
    final entered = Completer<void>();
    final roots = Completer<List<Directory>>();
    final removing = registry(
      roots: () {
        entered.complete();
        return roots.future;
      },
    ).uninstall('owned');
    await entered.future;
    await expectLater(
      registry(picker: _validPicker).importGguf(),
      throwsA(isA<ModelStorageBusy>()),
    );
    await expectLater(
      registry().validateDownloadedModel(
        modelId: 'owned',
        primaryPath: file.path,
      ),
      throwsA(isA<ModelStorageBusy>()),
    );
    await expectLater(
      registry().verifyInstallation('owned'),
      throwsA(isA<ModelStorageBusy>()),
    );
    roots.complete([Directory(p.join(documents.path, 'models'))]);
    await removing;
    expect(await file.exists(), isFalse);
  });

  test('shutdown waits for admitted removal and preserves its file', () async {
    final file = File(p.join(documents.path, 'models', 'closing-removal.gguf'));
    await file.parent.create(recursive: true);
    await file.writeAsString('GGUFpayload');
    await _insertModel('closing-removal', file.path);
    final entered = Completer<void>();
    final roots = Completer<List<Directory>>();
    final service = registry(
      roots: () {
        entered.complete();
        return roots.future;
      },
    );
    Object? failure;
    final removal = service
        .uninstall('closing-removal')
        .then<void>(
          (_) {},
          onError: (Object error) {
            failure = error;
          },
        );
    await entered.future;
    var closed = false;
    final closing = service.close().then((_) {
      closed = true;
    });
    try {
      await Future<void>.delayed(
        Duration.zero,
      ); // Drain scheduled shutdown, not a timing estimate.
      expect(closed, isFalse);
      await expectLater(
        service.uninstall('closing-removal'),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
    } finally {
      roots.complete([file.parent]);
      await removal;
      await closing;
    }
    expect(failure, isA<InferenceRepositoryDisposed>());
    expect(await file.exists(), isTrue);
    expect((await registry().findById('closing-removal'))?.isInstalled, isTrue);
    await registry().uninstall('closing-removal');
  });

  for (final operation in ['verification', 'validation']) {
    test('shutdown waits for admitted $operation metadata', () async {
      final file = File(p.join(documents.path, 'models', 'closing-read.gguf'));
      await file.parent.create(recursive: true);
      await file.writeAsString('GGUFpayload');
      await _insertModel(
        'closing-read',
        file.path,
        hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
      );
      final before = await DatabaseHelper.instance.getModel('closing-read');
      final entered = Completer<void>();
      final metadata = Completer<GgufMetadata>();
      final service = registry(
        metadata: (_) {
          entered.complete();
          return metadata.future;
        },
      );
      Object? failure;
      final pending =
          (operation == 'verification'
                  ? service.verifyInstallation('closing-read')
                  : service.validateDownloadedModel(
                      modelId: 'closing-read',
                      primaryPath: file.path,
                    ))
              .then<void>(
                (_) {},
                onError: (Object error) {
                  failure = error;
                },
              );
      await entered.future;
      var closed = false;
      final closing = service.close().then((_) {
        closed = true;
      });
      try {
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
      } finally {
        metadata.complete(_metadata());
        await pending;
        await closing;
      }
      expect(failure, isA<InferenceRepositoryDisposed>());
      expect(await DatabaseHelper.instance.getModel('closing-read'), before);
      expect(probe.prepareCalls, 0);
      await registry().uninstall('closing-read');
    });
  }

  for (final operation in ['verification', 'validation']) {
    test(
      'late $operation metadata error after shutdown cannot invalidate a model',
      () async {
        final file = File(p.join(documents.path, 'models', 'late-error.gguf'));
        await file.parent.create(recursive: true);
        await file.writeAsString('GGUFpayload');
        await _insertModel(
          'late-error',
          file.path,
          hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
        );
        final before = await DatabaseHelper.instance.getModel('late-error');
        final entered = Completer<void>();
        final metadata = Completer<GgufMetadata>();
        final service = registry(
          metadata: (_) {
            entered.complete();
            return metadata.future;
          },
        );
        final observed =
            (operation == 'verification'
                    ? service.verifyInstallation('late-error')
                    : service.validateDownloadedModel(
                        modelId: 'late-error',
                        primaryPath: file.path,
                      ))
                .then<Object?>(
                  (value) => value,
                  onError: (Object error) => error,
                );
        await entered.future;
        final closing = service.close();
        metadata.completeError(
          const FormatException('fixture stale metadata failure'),
        );
        final outcome = await observed;
        await closing;
        expect(await DatabaseHelper.instance.getModel('late-error'), before);
        expect(outcome, isA<InferenceRepositoryDisposed>());
        expect(await file.exists(), isTrue);
      },
    );
  }

  test(
    'shutdown during capability discovery prevents probe construction',
    () async {
      final file = File(
        p.join(documents.path, 'models', 'late-capabilities.gguf'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('GGUFpayload');
      await _insertModel(
        'late-capabilities',
        file.path,
        hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
      );
      final before = await DatabaseHelper.instance.getModel(
        'late-capabilities',
      );
      final capabilities = _WaitingCapabilities();
      final service = registry(capabilities: capabilities);
      final observed = service
          .verifyInstallation('late-capabilities')
          .then<Object?>((value) => value, onError: (Object error) => error);
      await capabilities.entered.future;
      final closing = service.close();
      expect(identical(closing, service.close()), isTrue);
      capabilities.result.complete(await const _Capabilities().snapshot());
      expect(await observed, isA<InferenceRepositoryDisposed>());
      await closing;
      expect(probe.repositoryCalls, 0);
      expect(
        await DatabaseHelper.instance.getModel('late-capabilities'),
        before,
      );
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'shared model hash retains profile until final installed owner leaves',
    () async {
      final file = File(
        p.join(documents.path, 'models', 'profile-shared.gguf'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('GGUFpayload');
      final hash = List.filled(64, 'a').join();
      await _insertModel('first-profile-owner', file.path, hash: hash);
      await _insertModel(
        'second-profile-owner',
        file.path,
        hash: hash.toUpperCase(),
      );
      final profiles = _Profiles();
      final service = registry(profiles: profiles);
      await service.uninstall('first-profile-owner');
      expect(profiles.invalidated, isEmpty);
      expect(await file.exists(), isTrue);
      await service.uninstall('second-profile-owner');
      expect(profiles.invalidated, [hash.toUpperCase()]);
      expect(await file.exists(), isFalse);
    },
  );

  test('uninstall cannot enter another reserved runtime session', () async {
    final file = File(p.join(documents.path, 'models', 'runtime-owned.gguf'));
    await file.parent.create(recursive: true);
    await file.writeAsString('GGUFpayload');
    await _insertModel('runtime-owned', file.path);
    final owner = LlamaCppChatRepository.withModelPath(file.path);
    try {
      await owner.withExclusiveSession(() async {
        await expectLater(
          registry().uninstall('runtime-owned'),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        expect(await file.exists(), isTrue);
        expect(
          (await registry().findById('runtime-owned'))?.isInstalled,
          isTrue,
        );
      });
    } finally {
      await owner.close();
    }
  });

  test(
    'uninstall preserves another model shard even when its primary differs',
    () async {
      final shared = File(
        p.join(documents.path, 'models', 'shared-shard.gguf'),
      );
      final primary = File(
        p.join(documents.path, 'models', 'other-primary.gguf'),
      );
      await shared.parent.create(recursive: true);
      await shared.writeAsString('GGUFshared');
      await primary.writeAsString('GGUFprimary');
      await _insertModel('first-owner', shared.path);
      await _insertModel('sharded-owner', primary.path);
      await DatabaseHelper.instance.replaceModelFiles('sharded-owner', [
        {
          'file_name': 'other-primary.gguf',
          'local_path': primary.path,
          'byte_size': primary.lengthSync(),
          'shard_index': 1,
          'shard_count': 2,
        },
        {
          'file_name': 'shared-shard.gguf',
          'local_path': shared.path,
          'byte_size': shared.lengthSync(),
          'shard_index': 2,
          'shard_count': 2,
        },
      ]);
      final service = registry();
      await service.uninstall('first-owner');
      expect(await shared.exists(), isTrue);
      expect(await primary.exists(), isTrue);
      expect(
        await DatabaseHelper.instance.getModelFiles('sharded-owner'),
        hasLength(2),
      );
      await service.uninstall('sharded-owner');
      expect(await shared.exists(), isFalse);
      expect(await primary.exists(), isFalse);
    },
  );

  test(
    'list, lookup, activation, and installation guards are explicit',
    () async {
      final file = File(p.join(documents.path, 'models', 'ready.gguf'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes('GGUF'.codeUnits);
      await _insertModel('ready', file.path, installationState: 'installed');
      await _insertModel('missing', null, installationState: 'not_installed');
      final service = registry();

      expect(
        (await service.listModels()).map((model) => model.id),
        containsAll(['ready', 'missing']),
      );
      expect((await service.findById('ready'))?.displayName, 'ready');
      expect((await service.findByPath(file.path))?.id, 'ready');
      expect(await service.findById('absent'), isNull);
      await service.activate((await service.findById('ready'))!);
      await expectLater(
        service.activate((await service.findById('missing'))!),
        throwsStateError,
      );
      expect((await service.requireInstalled('ready')).id, 'ready');
      await expectLater(service.requireInstalled('missing'), throwsStateError);
      await expectLater(service.requireInstalled('absent'), throwsStateError);

      await file.delete();
      await expectLater(service.requireInstalled('ready'), throwsStateError);
    },
  );

  test(
    'import cancellation and basic file validation preserve storage',
    () async {
      expect(await registry().importGguf(), isNull);

      final tooSmall = registry(
        picker: () async => ImportedModelFile(
          name: 'tiny.gguf',
          size: 4,
          readStream: Stream.value('GGUF'.codeUnits),
        ),
      );
      await expectLater(tooSmall.importGguf(), throwsFormatException);

      final unreadable = registry(
        picker: () async => const ImportedModelFile(
          name: 'missing.gguf',
          size: 1024 * 1024,
          readStream: null,
        ),
      );
      await expectLater(unreadable.importGguf(), throwsStateError);

      final wrongMagic = registry(
        picker: () async => ImportedModelFile(
          name: 'wrong.gguf',
          size: 1024 * 1024,
          readStream: Stream.value('NOPE'.codeUnits),
        ),
      );
      await expectLater(wrongMagic.importGguf(), throwsFormatException);
      expect(
        Directory(
          p.join(documents.path, 'models'),
        ).listSync().whereType<File>(),
        isEmpty,
      );
    },
  );

  test(
    'import rejects missing architecture, tokenizer, and template',
    () async {
      final metadataCases = <Map<String, dynamic>>[
        {'tokenizer.ggml.model': 'bpe', 'tokenizer.chat_template': 'chat'},
        {'general.architecture': 'qwen2', 'tokenizer.chat_template': 'chat'},
        {'general.architecture': 'qwen2', 'tokenizer.ggml.model': 'bpe'},
      ];
      for (final values in metadataCases) {
        final service = registry(
          picker: _validPicker,
          metadata: (path) async => _metadata(values),
        );
        await expectLater(service.importGguf(), throwsFormatException);
      }
    },
  );

  test('valid import hashes, probes, copies, and registers model', () async {
    final service = registry(picker: _validPicker);

    final imported = await service.importGguf();

    expect(imported, isNotNull);
    expect(imported!.id, startsWith('local-'));
    expect(imported.displayName, 'Fixture Model');
    expect(imported.architecture, 'qwen2');
    // A template mentioning a knob is not evidence that its behavior is verified.
    expect(imported.supportsThinking, isFalse);
    expect(imported.installationState, 'installed');
    expect(await File(imported.localPath!).readAsString(), 'GGUFpayload');
    expect(imported.sha256, sha256.convert('GGUFpayload'.codeUnits).toString());
    expect(probe.prepareCalls, 1);
    expect(probe.countCalls, 1);
    expect(probe.generateCalls, 1);
    expect(probe.unloadCalls, 1);
    expect(probe.disposeCalls, 1);
    expect((await service.findById(imported.id))?.id, imported.id);
  });

  test(
    'probe cannot activate imported bytes before close acknowledges',
    () async {
      probe.closeAcknowledgement = Completer<void>();
      final service = registry(picker: _validPicker);
      final operation = service.importGguf();
      final outcome = operation.then<Object?>((value) => value);
      try {
        await Future.any<Object?>([
          probe.closeStarted.future.then<Object?>((_) => null),
          outcome,
        ]);
        expect(
          probe.closeStarted.isCompleted,
          isTrue,
          reason: 'Verification must await repository close, not call dispose',
        );
        expect(
          (await service.listModels()).where(
            (model) => model.source == 'local_import',
          ),
          isEmpty,
        );
      } finally {
        probe.closeAcknowledgement!.complete();
        await outcome;
      }
      expect(
        (await service.listModels())
            .singleWhere((model) => model.source == 'local_import')
            .isInstalled,
        isTrue,
      );
    },
  );

  test('probe close failure cannot become an installed model', () async {
    probe.failClose = true;
    final service = registry(picker: _validPicker);
    await expectLater(
      service.importGguf(),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(
      (await service.listModels()).where(
        (model) => model.source == 'local_import',
      ),
      isEmpty,
    );
    expect(service.requiresProbeRecovery, isTrue);
    final models = Directory(p.join(documents.path, 'models'));
    expect(models.listSync().whereType<Directory>(), hasLength(1));
    await expectLater(
      service.importGguf(),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    probe.recoveryAcknowledgement = Completer<void>();
    final first = service.recoverProbeCleanup();
    final second = service.recoverProbeCleanup();
    expect(identical(first, second), isTrue);
    await probe.recoveryStarted.future;
    expect(models.listSync().whereType<Directory>(), hasLength(1));
    await expectLater(
      service.importGguf(),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    probe.recoveryAcknowledgement!.complete();
    expect(await first, RuntimeRecoveryOutcome.recovered);
    expect(service.requiresProbeRecovery, isFalse);
    expect(models.listSync(), isEmpty);
    expect(
      (await service.listModels()).where(
        (model) => model.source == 'local_import',
      ),
      isEmpty,
    );
    probe.failClose = false;
    expect(await service.importGguf(), isNotNull);
  });

  test(
    'registry shutdown retains an unfinished picker and rejects late import',
    () async {
      final pickerStarted = Completer<void>();
      final picked = Completer<ImportedModelFile?>();
      final service = registry(
        picker: () {
          pickerStarted.complete();
          return picked.future;
        },
      );
      final operation = service.importGguf().then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
      await pickerStarted.future;
      final close = service.close();
      expect(identical(close, service.close()), isTrue);
      var closed = false;
      close.then((_) => closed = true);
      await expectLater(
        service.importGguf(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      expect(closed, isFalse);
      picked.complete(null);
      expect(await operation, isA<InferenceRepositoryDisposed>());
      await close;
      expect(closed, isTrue);
      expect(probe.prepareCalls, 0);
    },
  );

  test(
    'scope shutdown during probe cleanup cannot activate the import',
    () async {
      probe.closeAcknowledgement = Completer<void>();
      final service = registry(picker: _validPicker);
      final operation = service.importGguf().then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
      await probe.closeStarted.future;
      final close = service.close();
      probe.closeAcknowledgement!.complete();
      expect(await operation, isA<InferenceRepositoryDisposed>());
      await close;
      expect(probe.disposeCalls, 1);
      expect(
        (await service.listModels()).where(
          (model) => model.source == 'local_import',
        ),
        isEmpty,
      );
    },
  );

  test(
    'busy runtime rejects probe without cancelling or unloading its owner',
    () async {
      probe.leaseBusy = true;
      await expectLater(
        registry(picker: _validPicker).importGguf(),
        throwsStateError,
      );
      expect(probe.prepareCalls, 0);
      expect(probe.cancelCalls, 0);
      expect(probe.unloadCalls, 0);
      expect(probe.disposeCalls, 0);
    },
  );

  for (final failure in ['decode', 'missingCompletion', 'cancelled']) {
    test('probe $failure cannot activate an imported model', () async {
      probe.failGeneration = failure == 'decode';
      probe.omitCompletion = failure == 'missingCompletion';
      probe.cancelCompletion = failure == 'cancelled';
      final service = registry(picker: _validPicker);
      await expectLater(service.importGguf(), throwsStateError);
      expect(
        (await service.listModels()).where((model) => model.isInstalled),
        isEmpty,
      );
      expect(probe.generateCalls, 1);
      expect(probe.unloadCalls, 1);
      expect(probe.disposeCalls, 1);
      if (failure == 'decode') expect(probe.cancelCalls, 1);
    });
  }

  test('probe timeout waits for cancellation before cleanup', () async {
    probe.stalled = Completer<void>();
    probe.cancelAcknowledgement = Completer<void>();
    final service = registry(
      picker: _validPicker,
      probeDeadline: const Duration(milliseconds: 1),
    );
    final failure = expectLater(
      service.importGguf(),
      throwsA(isA<TimeoutException>()),
    );
    await probe.cancelRequested.future;
    expect(probe.unloadCalls, 0);
    expect(probe.disposeCalls, 0);
    probe.cancelAcknowledgement!.complete();
    await failure;
    expect(probe.unloadCalls, 1);
    expect(probe.disposeCalls, 1);
    expect(
      (await service.listModels()).where((model) => model.isInstalled),
      isEmpty,
    );
  });

  test(
    'failed import probe deletes copied model and propagates failure',
    () async {
      probe.failPrepare = true;
      final service = registry(picker: _validPicker);

      await expectLater(service.importGguf(), throwsStateError);

      final files = Directory(
        p.join(documents.path, 'models'),
      ).listSync().whereType<File>();
      expect(files, isEmpty);
      expect(probe.unloadCalls, 1);
      expect(probe.disposeCalls, 1);
    },
  );

  test(
    'reimport reuses verified file and preserves registry metadata',
    () async {
      final service = registry(picker: _validPicker);
      final original = (await service.importGguf())!;
      final before = await DatabaseHelper.instance.getModel(original.id);
      probe.failPrepare = true;
      final again = (await service.importGguf())!;
      expect(again.localPath, original.localPath);
      expect(await File(original.localPath!).readAsString(), 'GGUFpayload');
      expect(await DatabaseHelper.instance.getModel(original.id), before);
      expect(probe.prepareCalls, 1);
      expect(
        Directory(
          p.join(documents.path, 'models'),
        ).listSync().whereType<Directory>(),
        isEmpty,
      );
    },
  );

  test(
    'failed probe never deletes a preexisting content-addressed file',
    () async {
      final hash = sha256.convert('GGUFpayload'.codeUnits).toString();
      final id = 'local-${hash.substring(0, 16)}';
      final existing = File(p.join(documents.path, 'models', '$id.gguf'));
      await existing.parent.create(recursive: true);
      await existing.writeAsString('GGUFpayload');
      probe.failPrepare = true;
      await expectLater(
        registry(picker: _validPicker).importGguf(),
        throwsStateError,
      );
      expect(await existing.readAsString(), 'GGUFpayload');
      expect(await DatabaseHelper.instance.getModel(id), isNull);
    },
  );

  test(
    'existing mismatched file requires repair instead of overwrite',
    () async {
      final hash = sha256.convert('GGUFpayload'.codeUnits).toString();
      final existing = File(
        p.join(documents.path, 'models', 'local-${hash.substring(0, 16)}.gguf'),
      );
      await existing.parent.create(recursive: true);
      await existing.writeAsString('preserve existing bytes');
      await expectLater(
        registry(picker: _validPicker).importGguf(),
        throwsStateError,
      );
      expect(await existing.readAsString(), 'preserve existing bytes');
    },
  );

  test(
    'concurrent registry imports cannot share probe or overwrite staging',
    () async {
      final pending = Completer<ImportedModelFile?>();
      final first = registry(picker: () => pending.future).importGguf();
      await expectLater(
        registry(picker: _validPicker).importGguf(),
        throwsStateError,
      );
      pending.complete(null);
      expect(await first, isNull);
    },
  );

  test(
    'download validation rejects absent registry, file, and magic',
    () async {
      final service = registry();
      final missing = p.join(documents.path, 'missing.gguf');
      await expectLater(
        service.validateDownloadedModel(
          modelId: 'absent',
          primaryPath: missing,
        ),
        throwsStateError,
      );
      await _insertModel('download', missing);
      await expectLater(
        service.validateDownloadedModel(
          modelId: 'download',
          primaryPath: missing,
        ),
        throwsStateError,
      );
      final file = File(missing)..writeAsStringSync('NOPE');
      await expectLater(
        service.validateDownloadedModel(
          modelId: 'download',
          primaryPath: file.path,
        ),
        throwsFormatException,
      );
    },
  );

  test('download validation probes and preserves remote metadata', () async {
    final file = File(p.join(documents.path, 'download.gguf'))
      ..writeAsStringSync('GGUFpayload');
    await DatabaseHelper.instance.upsertModel({
      'id': 'download',
      'display_name': 'Remote',
      'local_path': file.path,
      'source': 'huggingface',
      'sha256': sha256.convert('GGUFpayload'.codeUnits).toString(),
      'byte_size': file.lengthSync(),
      'compatibility_status': 'pending',
      'installation_state': 'downloaded',
      'repository': 'owner/model',
      'revision': List.filled(40, 'a').join(),
      'quantization': 'Q4_K_M',
      'parameter_count': 800000000,
      'license': 'apache-2.0',
    });
    final service = registry();

    final result = await service.validateDownloadedModel(
      modelId: 'download',
      primaryPath: file.path,
    );

    expect(result.compatibilityStatus, 'compatible');
    expect(result.repository, 'owner/model');
    expect(result.quantization, 'Q4_K_M');
    expect(result.installedAt, DateTime.utc(2026, 2, 3));
    expect(probe.prepareCalls, 1);
    expect(probe.disposeCalls, 1);
  });

  for (final observerFails in [false, true]) {
    test(
      'verification phases ${observerFails ? 'isolate observer failure' : 'follow actual work order'}',
      () async {
        final file = File(p.join(documents.path, 'phase.gguf'))
          ..writeAsStringSync('GGUFpayload');
        await _insertModel(
          'phase',
          file.path,
          size: file.lengthSync(),
          hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
        );
        final phases = <ModelVerificationPhase>[];
        final service = registry();
        final result = await service.verifyInstallation(
          'phase',
          onPhase: (phase) {
            phases.add(phase);
            if (observerFails) throw StateError('fixture observer failure');
          },
        );
        expect(result.id, 'phase');
        expect(result.compatibilityStatus, 'compatible');
        expect(phases, ModelVerificationPhase.values);
        expect(probe.prepareCalls, 1);
        expect(probe.disposeCalls, 1);
      },
    );
  }

  for (final competingAction in ['uninstall', 'import']) {
    test(
      'verification hashing retains file ownership against $competingAction',
      () async {
        final file = File(p.join(documents.path, 'models', 'reading.gguf'));
        await file.parent.create(recursive: true);
        await file.writeAsString('GGUFpayload');
        await _insertModel(
          'reading',
          file.path,
          size: file.lengthSync(),
          hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
        );
        Future<void>? rejected;
        await registry().verifyInstallation(
          'reading',
          onPhase: (phase) {
            if (phase == ModelVerificationPhase.hashing) {
              rejected = expectLater(
                competingAction == 'uninstall'
                    ? registry().uninstall('reading')
                    : registry().importGguf(),
                throwsA(isA<ModelStorageBusy>()),
              );
            }
          },
        );
        await rejected;
        expect(await file.exists(), isTrue);
        expect((await registry().findById('reading'))?.isInstalled, isTrue);
      },
    );
  }

  test(
    'one completed verification cannot release another file reader',
    () async {
      final file = File(p.join(documents.path, 'models', 'two-readers.gguf'));
      await file.parent.create(recursive: true);
      await file.writeAsString('GGUFpayload');
      await _insertModel(
        'two-readers',
        file.path,
        size: file.lengthSync(),
        hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
      );
      final enteredFirst = Completer<void>();
      final enteredSecond = Completer<void>();
      final metadataFirst = Completer<GgufMetadata>();
      final metadataSecond = Completer<GgufMetadata>();
      final first = registry(
        metadata: (_) {
          enteredFirst.complete();
          return metadataFirst.future;
        },
      ).verifyInstallation('two-readers');
      await enteredFirst.future;
      final second = registry(
        metadata: (_) {
          enteredSecond.complete();
          return metadataSecond.future;
        },
      ).verifyInstallation('two-readers');
      await enteredSecond.future;
      metadataFirst.complete(_metadata());
      await first;
      await expectLater(
        registry().uninstall('two-readers'),
        throwsA(isA<ModelStorageBusy>()),
      );
      expect(await file.exists(), isTrue);
      metadataSecond.complete(_metadata());
      await second;
      await registry().uninstall('two-readers');
      expect(await file.exists(), isFalse);
    },
  );

  test('failed verification releases file ownership after cleanup', () async {
    final file = File(p.join(documents.path, 'models', 'failed-reading.gguf'));
    await file.parent.create(recursive: true);
    await file.writeAsString('GGUFpayload');
    await _insertModel(
      'failed-reading',
      file.path,
      size: file.lengthSync(),
      hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
    );
    probe.failGeneration = true;
    await expectLater(
      registry().verifyInstallation('failed-reading'),
      throwsStateError,
    );
    probe.failGeneration = false;
    await registry().uninstall('failed-reading');
    expect(await file.exists(), isFalse);
  });

  for (final state in ['busy', 'recovery', 'decode']) {
    test(
      'verification preserves models on runtime contention ($state)',
      () async {
        final file = File(p.join(documents.path, 'verify.gguf'))
          ..writeAsStringSync('GGUFpayload');
        await _insertModel(
          'verify',
          file.path,
          hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
        );
        final before = await DatabaseHelper.instance.getModel('verify');
        probe.leaseBusy = state == 'busy';
        probe.recoveryRequired = state == 'recovery';
        probe.failGeneration = state == 'decode';
        await expectLater(
          registry().verifyInstallation('verify'),
          throwsStateError,
        );
        final after = await DatabaseHelper.instance.getModel('verify');
        if (state != 'decode') {
          expect(after, before);
          expect(probe.unloadCalls, 0);
        } else {
          expect(after?['installation_state'], 'verification_failed');
        }
        expect(await file.readAsString(), 'GGUFpayload');
      },
    );
  }

  test(
    'disposed verification preserves valid model records during metadata read',
    () async {
      final file = File(p.join(documents.path, 'dispose-verify.gguf'))
        ..writeAsStringSync('GGUFpayload');
      await _insertModel(
        'dispose-verify',
        file.path,
        hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
      );
      final before = await DatabaseHelper.instance.getModel('dispose-verify');
      final metadataStarted = Completer<void>();
      final metadata = Completer<GgufMetadata>();
      final service = registry(
        metadata: (_) {
          metadataStarted.complete();
          return metadata.future;
        },
      );
      final operation = service.verifyInstallation('dispose-verify');
      final observed = operation.then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
      await metadataStarted.future;
      final closing = service.close();
      metadata.complete(_metadata());
      expect(await observed, isA<InferenceRepositoryDisposed>());
      await closing;
      expect(await DatabaseHelper.instance.getModel('dispose-verify'), before);
      expect(await file.readAsString(), 'GGUFpayload');
      expect(probe.prepareCalls, 0);
    },
  );

  test('verification checks size and hash and records failure state', () async {
    final file = File(p.join(documents.path, 'verify.gguf'))
      ..writeAsStringSync('GGUFpayload');
    await _insertModel(
      'verify',
      file.path,
      size: file.lengthSync() + 1,
      hash: sha256.convert('GGUFpayload'.codeUnits).toString(),
    );
    final service = registry();

    await expectLater(service.verifyInstallation('verify'), throwsStateError);

    final failed = await service.findById('verify');
    expect(failed?.installationState, 'verification_failed');
    await expectLater(service.verifyInstallation('absent'), throwsStateError);
  });
}

Future<ImportedModelFile?> _validPicker() async => ImportedModelFile(
  name: 'fixture.gguf',
  size: 1024 * 1024,
  readStream: Stream.value('GGUFpayload'.codeUnits),
);

GgufMetadata _metadata([Map<String, dynamic>? override]) {
  final values =
      override ??
      <String, dynamic>{
        'general.name': 'Fixture Model',
        'general.architecture': 'qwen2',
        'tokenizer.ggml.model': 'bpe',
        'tokenizer.chat_template': '{{ enable_thinking }}',
        'qwen2.context_length': 8192,
        'qwen2.block_count': 8,
      };
  return GgufMetadata(
    path: 'fixture.gguf',
    version: 3,
    tensorCount: 1,
    metadataKvCount: values.length,
    metadata: values,
  );
}

Future<void> _insertModel(
  String id,
  String? path, {
  String installationState = 'installed',
  int? size,
  String hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => DatabaseHelper.instance.upsertModel({
  'id': id,
  'display_name': id,
  'local_path': path,
  'source': 'fixture',
  'sha256': hash,
  'byte_size': size,
  'compatibility_status': 'compatible',
  'installation_state': installationState,
});

final class _WaitingCapabilities implements RuntimeCapabilitiesProvider {
  final entered = Completer<void>();
  final result = Completer<RuntimeCapabilities>();
  @override
  Future<RuntimeCapabilities> snapshot() {
    entered.complete();
    return result.future;
  }
}

final class _Capabilities implements RuntimeCapabilitiesProvider {
  const _Capabilities({this.severe = false});
  final bool severe;
  @override
  Future<RuntimeCapabilities> snapshot() async => RuntimeCapabilities(
    logicalProcessors: 4,
    performanceProcessors: 2,
    deviceFingerprint: 'fixture',
    abis: ['arm64-v8a'],
    packagedBackends: {'cpu'},
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    thermalStatus: 0,
    lowMemory: severe,
  );
}

final class _Profiles implements RuntimeProfileStore {
  final invalidated = <String>[];
  @override
  Future<bool> writeIfCurrent(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    required bool Function() isCurrent,
    String? fallbackReason,
  }) async => isCurrent();
  @override
  Future<void> invalidateModel(String modelSha256) async {
    invalidated.add(modelSha256);
  }

  @override
  Future<void> invalidate(RuntimeProfileKey key) async {}
  @override
  Future<StoredRuntimeProfile?> read(RuntimeProfileKey key) async => null;
  @override
  Future<void> write(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    String? fallbackReason,
  }) async {}
}

final class _Probe {
  bool closeSuppressesOutput = false;
  bool closeInterruptsGeneration = false;
  final generationStarted = Completer<void>();
  Completer<void>? prepareGate;
  final prepareStarted = Completer<void>();
  final closeStarted = Completer<void>();
  Completer<void>? closeAcknowledgement;
  bool failClose = false;
  final recoveryStarted = Completer<void>();
  Completer<void>? recoveryAcknowledgement;
  bool leaseBusy = false;
  bool recoveryRequired = false;
  Completer<void>? stalled;
  Completer<void>? cancelAcknowledgement;
  final cancelRequested = Completer<void>();
  bool failGeneration = false;
  bool omitCompletion = false;
  bool cancelCompletion = false;
  int generateCalls = 0;
  int cancelCalls = 0;
  bool failPrepare = false;
  int prepareCalls = 0;
  int countCalls = 0;
  int unloadCalls = 0;
  int disposeCalls = 0;
  int repositoryCalls = 0;

  LlamaCppChatRepository repository(String path, RuntimeProfile profile) {
    repositoryCalls++;
    return _ProbeRepository(this);
  }
}

final class _ProbeRepository implements LlamaCppChatRepository {
  _ProbeRepository(this.owner);
  final _Probe owner;
  Future<void>? _closeFuture;
  @override
  Future<T> withExclusiveSession<T>(
    Future<T> Function() action, {
    RuntimeOperationKind kind = RuntimeOperationKind.interactive,
  }) async {
    if (owner.leaseBusy) throw InferenceRuntimeBusy();
    if (owner.recoveryRequired) throw InferenceRecoveryRequired();
    return action();
  }

  @override
  LlamaCppInferenceMetrics? get lastMetrics => LlamaCppInferenceMetrics(
    promptTokens: 1,
    generatedTokens: 1,
    modelLoadMicros: 1,
    contextInitMicros: 1,
    promptEvalMicros: 1,
    generationMicros: 1,
    timeToFirstTokenMicros: 1,
    completionReason: owner.cancelCompletion ? 'cancelled' : 'outputLimit',
  );

  @override
  Future<void> cancelActiveInference() async {
    owner.cancelCalls++;
    if (!owner.cancelRequested.isCompleted) owner.cancelRequested.complete();
    await owner.cancelAcknowledgement?.future;
    if (owner.stalled != null && !owner.stalled!.isCompleted)
      owner.stalled!.complete();
  }

  @override
  Stream<LLMChunk> streamChatWithGenerationOptions(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
    GenerationOptions? generationOptions,
  }) async* {
    owner.generateCalls++;
    if (!owner.generationStarted.isCompleted)
      owner.generationStarted.complete();
    expect(generationOptions?.maxTokens, greaterThan(0));
    if (owner.failGeneration) throw StateError('decode failed');
    await owner.stalled?.future;
    if (owner.closeSuppressesOutput && _closeFuture != null) return;
    yield LLMChunk(
      model: model,
      createdAt: DateTime.now(),
      message: LLMChunkMessage(content: 'Hello', role: LLMRole.assistant),
      done: false,
    );
    if (!owner.omitCompletion) {
      yield LLMChunk(
        model: model,
        createdAt: DateTime.now(),
        message: null,
        done: true,
      );
    }
  }

  @override
  Future<void> prepare({RuntimeOperationKind? kind}) async {
    owner.prepareCalls++;
    if (!owner.prepareStarted.isCompleted) owner.prepareStarted.complete();
    await owner.prepareGate?.future;
    if (owner.failPrepare) throw StateError('probe failed');
  }

  @override
  Future<int> countChatTokens(
    List<LLMMessage> messages, {
    bool think = false,
  }) async {
    owner.countCalls++;
    return 1;
  }

  @override
  Future<void> unloadPersistentModel() async => owner.unloadCalls++;
  @override
  Future<void> close() => _closeFuture ??= _finishClose();

  Future<void> _finishClose() async {
    if (!owner.closeStarted.isCompleted) owner.closeStarted.complete();
    await owner.closeAcknowledgement?.future;
    if (owner.closeInterruptsGeneration &&
        owner.stalled != null &&
        !owner.stalled!.isCompleted)
      owner.stalled!.complete();
    if (owner.prepareGate != null && !owner.prepareGate!.isCompleted)
      owner.prepareGate!.complete();
    if (owner.failClose) throw StateError('fixture close failure');
    await unloadPersistentModel();
    dispose();
  }

  @override
  Future<RuntimeRecoveryOutcome> recoverAfterClose() async {
    if (!owner.recoveryStarted.isCompleted) owner.recoveryStarted.complete();
    await owner.recoveryAcknowledgement?.future;
    return RuntimeRecoveryOutcome.recovered;
  }

  @override
  void dispose() => owner.disposeCalls++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
