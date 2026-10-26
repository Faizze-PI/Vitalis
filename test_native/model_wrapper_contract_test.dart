import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/native_runtime_bridge.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late File stub;
  late LlamaCppModelLoader loader;
  late String fixture;

  setUpAll(() async {
    fixture = Platform.environment['VITALIS_TEST_MODEL'] ?? '';
    expect(fixture, isNotEmpty, reason: 'Verified model fixture is mandatory');
    expect(
      (await sha256.bind(File(fixture).openRead()).first).toString(),
      BundledModelManifest.sha256,
    );
    sandbox = await Directory.systemTemp.createTemp('vitalis-model-contract-');
    stub = File('${sandbox.path}/record-only.gguf');
    await stub.writeAsString('GGUF parameter recording fixture');
    loader = LlamaCppModelLoader();
    loader.initializeBackend();
  });
  tearDownAll(() async {
    loader.dispose();
    await sandbox.delete(recursive: true);
  });

  for (final mapped in [false, true]) {
    for (final locked in [false, true]) {
      test('native params apply mmap=$mapped mlock=$locked', () {
        final bindings = _RecordingBindings();
        expect(
          () => LlamaCppModel.load(
            stub.path,
            bindings,
            useMemoryMap: mapped,
            useMemoryLock: locked,
            vocabOnly: true,
          ),
          throwsException,
        );
        final expected = mapped
            ? (locked
                  ? llama_load_mode.LLAMA_LOAD_MODE_MMAP_MLOCK
                  : llama_load_mode.LLAMA_LOAD_MODE_MMAP)
            : (locked
                  ? llama_load_mode.LLAMA_LOAD_MODE_MLOCK
                  : llama_load_mode.LLAMA_LOAD_MODE_NONE);
        expect(bindings.observedMode, expected);
        expect(bindings.observedVocabOnly, isTrue);
        expect(bindings.observedGpuLayers, 0);
        final bridge = NativeRuntimeBridge(loadLlamaLibrary());
        final writer = bridge.acquireModelMutation(modelPath: stub.path);
        try {
          expect(
            writer.address,
            isNot(0),
            reason: 'Failed load must release reader lease',
          );
        } finally {
          if (writer.address != 0) bridge.releaseModelAccess(writer);
        }
      });
    }
  }

  for (final capability in ['mmap', 'mlock']) {
    test('unsupported $capability is rejected before native loading', () {
      final bindings = _RecordingBindings()
        ..supportsMap = capability != 'mmap'
        ..supportsLock = capability != 'mlock';
      expect(
        () => LlamaCppModel.load(
          stub.path,
          bindings,
          useMemoryMap: capability == 'mmap',
          useMemoryLock: capability == 'mlock',
        ),
        throwsUnsupportedError,
      );
      expect(bindings.observedMode, isNull);
    });
  }

  test(
    'pooled model rejects changed options without changing references',
    () async {
      const options = ModelLoadOptions(vocabOnly: true);
      final model = await loader.loadModel(fixture, options: options);
      try {
        for (final changed in const [
          ModelLoadOptions(vocabOnly: false),
          ModelLoadOptions(vocabOnly: true, useMemoryMap: false),
          ModelLoadOptions(vocabOnly: true, useMemoryLock: true),
          ModelLoadOptions(vocabOnly: true, nGpuLayers: 1),
        ]) {
          await expectLater(
            loader.loadModel(fixture, options: changed),
            throwsA(isA<ModelLoadException>()),
          );
          expect(loader.getModelRefCount(fixture), 1);
          expect(model.vocabSize, greaterThan(0));
        }
        expect(await loader.loadModel(fixture, options: options), same(model));
        expect(loader.getModelRefCount(fixture), 2);
        loader.unloadModel(fixture);
        expect(loader.getModelRefCount(fixture), 1);
        expect(model.vocabSize, greaterThan(0));
        loader.unloadModel(fixture);
        expect(loader.getModelRefCount(fixture), 0);
        expect(() => model.vocabSize, throwsStateError);
      } finally {
        loader.unloadModel(fixture, force: true);
      }
    },
  );

  test('missing and empty files never enter native loading', () async {
    final empty = File('${sandbox.path}/empty.gguf');
    await empty.create();
    for (final path in ['${sandbox.path}/absent.gguf', empty.path]) {
      final bindings = _RecordingBindings();
      expect(() => LlamaCppModel.load(path, bindings), throwsException);
      expect(bindings.observedMode, isNull);
    }
  });

  test('file writer prevents model loading without affecting its lease', () {
    final bridge = NativeRuntimeBridge(loadLlamaLibrary());
    final writer = bridge.acquireModelMutation(modelPath: stub.path);
    try {
      expect(writer.address, isNot(0));
      final bindings = _RecordingBindings();
      expect(
        () => LlamaCppModel.load(stub.path, bindings),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(bindings.observedMode, isNull);
      final competingReader = bridge.acquireModelRead(modelPath: stub.path);
      expect(competingReader.address, 0);
    } finally {
      if (writer.address != 0) bridge.releaseModelAccess(writer);
    }
  });

  test('malformed native model releases its file lease', () {
    expect(
      () => LlamaCppModel.load(stub.path, loader.bindings),
      throwsException,
    );
    final bridge = NativeRuntimeBridge(loadLlamaLibrary());
    final writer = bridge.acquireModelMutation(modelPath: stub.path);
    try {
      expect(writer.address, isNot(0));
    } finally {
      if (writer.address != 0) bridge.releaseModelAccess(writer);
    }
  });

  test('real model accessors reject use after idempotent disposal', () async {
    final model = await loader.loadModel(
      fixture,
      options: const ModelLoadOptions(),
    );
    final bindings = loader.bindings;
    expect(model.pointer.address, isNot(0));
    expect(model.vocab.address, isNot(0));
    expect(model.vocabSize, greaterThan(0));
    expect(model.contextSizeTrain, greaterThan(0));
    expect(model.embeddingSize, greaterThan(0));
    expect(model.bosToken, bindings.llama_vocab_bos(model.vocab));
    expect(model.eosToken, bindings.llama_vocab_eos(model.vocab));
    expect(model.nlToken, bindings.llama_vocab_nl(model.vocab));
    expect(model.padToken, bindings.llama_vocab_pad(model.vocab));
    expect(
      model.isEogToken(model.eosToken),
      bindings.llama_vocab_is_eog(model.vocab, model.eosToken),
    );
    expect(
      model.isControlToken(0),
      bindings.llama_vocab_is_control(model.vocab, 0),
    );
    model.dispose();
    model.dispose();
    for (final access in <void Function()>[
      () {
        model.pointer;
      },
      () {
        model.vocab;
      },
      () {
        model.vocabSize;
      },
      () {
        model.contextSizeTrain;
      },
      () {
        model.embeddingSize;
      },
      () {
        model.bosToken;
      },
      () {
        model.eosToken;
      },
      () {
        model.nlToken;
      },
      () {
        model.padToken;
      },
      () {
        model.isEogToken(0);
      },
      () {
        model.isControlToken(0);
      },
    ]) {
      expect(access, throwsStateError);
    }
    final bridge = NativeRuntimeBridge(loadLlamaLibrary());
    final writer = bridge.acquireModelMutation(modelPath: fixture);
    try {
      expect(writer.address, isNot(0));
    } finally {
      if (writer.address != 0) bridge.releaseModelAccess(writer);
    }
  });
}

/// Records params at the native-call boundary without loading or locking memory.
final class _RecordingBindings extends LlamaBindings {
  _RecordingBindings() : super(loadLlamaLibrary());
  bool supportsMap = true;
  bool supportsLock = true;
  llama_load_mode? observedMode;
  bool? observedVocabOnly;
  int? observedGpuLayers;
  @override
  bool llama_supports_mmap() => supportsMap;
  @override
  bool llama_supports_mlock() => supportsLock;
  @override
  ffi.Pointer<llama_model> llama_load_model_from_file(
    ffi.Pointer<ffi.Char> path,
    llama_model_params params,
  ) {
    observedMode = params.load_mode;
    observedVocabOnly = params.vocab_only;
    observedGpuLayers = params.n_gpu_layers;
    return ffi.nullptr;
  }
}
