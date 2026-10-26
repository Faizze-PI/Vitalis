import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';

final class ShardRestoreFixture {
  static bool _factoryInitialized = false;
  final storage = DatabaseHelper.instance;
  late Directory sandbox;
  late Directory documents;
  late List<Map<String, dynamic>> beforeFiles;
  late Map<String, dynamic> beforeModel;
  late int chatId;
  late Map<String, dynamic> beforeSettings;
  final payloads = ['GGUFpayload-one'.codeUnits, 'GGUFpayload-two'.codeUnits];
  int picks = 0;
  int probes = 0;
  int closes = 0;
  bool failProbe = false;
  Completer<void>? closeGate;
  final closeStarted = Completer<void>();
  final probedPaths = <String>[];
  String fileName(int index) =>
      'fixture-${(index + 1).toString().padLeft(5, '0')}-of-00002.gguf';

  Future<void> initialize() async {
    if (!_factoryInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _factoryInitialized = true;
    }
    sandbox = await Directory.systemTemp.createTemp('vitalis_split_restore_');
    documents = await Directory(p.join(sandbox.path, 'documents')).create();
    await databaseFactory.setDatabasesPath(sandbox.path);
    await storage.upsertModel({
      'id': 'fixture',
      'display_name': 'Disposable',
      'source': 'huggingface',
      'local_path': p.join(documents.path, 'missing', fileName(0)),
      'sha256': sha256.convert(payloads.first).toString(),
      'byte_size': payloads.fold<int>(0, (n, data) => n + data.length),
      'compatibility_status': 'missing_file',
      'installation_state': 'installed',
      'repository': 'publisher/fixture',
      'revision': 'immutable',
    });
    await storage.replaceModelFiles('fixture', [
      for (var i = 0; i < payloads.length; i++)
        {
          'file_name': fileName(i),
          'local_path': p.join(documents.path, 'missing', fileName(i)),
          'sha256': sha256.convert(payloads[i]).toString(),
          'byte_size': payloads[i].length,
          'etag': 'original-entity-$i',
          'shard_index': i,
          'shard_count': payloads.length,
        },
    ]);
    beforeModel = (await storage.getModel('fixture'))!;
    beforeFiles = await storage.getModelFiles('fixture');
    final stamp = DateTime.utc(2026, 10, 15).toIso8601String();
    chatId = await storage.insertChat({
      'title': 'Disposable existing chat',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await storage.assignModelForChat(chatId, 'fixture');
    beforeSettings = (await storage.getModelSettings(chatId))!;
  }

  List<ImportedModelFile> picked({bool reverse = false}) => [
    for (final index in reverse ? [1, 0] : [0, 1])
      ImportedModelFile(
        name: 'arbitrary-$index.gguf',
        size: payloads[index].length,
        readStream: Stream.value(payloads[index]),
      ),
  ];

  ModelRegistryService registry({ModelImportSetPicker? picker}) =>
      ModelRegistryService(
        database: storage,
        documentsDirectory: () async => documents,
        allowedRoots: () async => [Directory(p.join(documents.path, 'models'))],
        restoreSetPicker: () async {
          picks++;
          return picker == null ? picked() : picker();
        },
        capabilitiesProvider: const _Capabilities(),
        checkProbeSafety: () {},
        metadataReader: (path) async {
          final metadata = <String, dynamic>{
            'general.architecture': 'qwen2',
            'tokenizer.ggml.model': 'bpe',
            'tokenizer.chat_template': '{{ enable_thinking }}',
            'qwen2.context_length': 8192,
          };
          return GgufMetadata(
            path: path,
            version: 3,
            tensorCount: 1,
            metadataKvCount: metadata.length,
            metadata: metadata,
          );
        },
        probeFactory:
            ({required String modelPath, required RuntimeProfile profile}) {
              probes++;
              probedPaths.add(modelPath);
              return _Probe(this);
            },
      );

  Future<void> destroy() async {
    await storage.close();
    await databaseFactory.deleteDatabase(
      p.join(sandbox.path, AppConstants.databaseName),
    );
    await sandbox.delete(recursive: true);
  }
}

final class _Capabilities implements RuntimeCapabilitiesProvider {
  const _Capabilities();
  @override
  Future<RuntimeCapabilities> snapshot() async => const RuntimeCapabilities(
    logicalProcessors: 4,
    performanceProcessors: 2,
    deviceFingerprint: 'fixture',
    abis: ['arm64-v8a'],
    packagedBackends: {'cpu'},
    thermalStatus: 0,
    lowMemory: false,
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
  );
}

final class _Probe implements LlamaCppChatRepository {
  _Probe(this.fixture);
  final ShardRestoreFixture fixture;
  Future<void>? _closing;
  @override
  Future<T> withExclusiveSession<T>(
    Future<T> Function() action, {
    RuntimeOperationKind kind = RuntimeOperationKind.interactive,
  }) => action();
  @override
  Future<void> prepare({RuntimeOperationKind? kind}) async {
    if (fixture.failProbe) throw StateError('fixture decode failure');
    for (var index = 0; index < fixture.payloads.length; index++) {
      final path = p.join(
        p.dirname(fixture.probedPaths.last),
        fixture.fileName(index),
      );
      if (!await File(path).exists()) throw StateError('fixture shard missing');
    }
  }

  @override
  Future<int> countChatTokens(
    List<LLMMessage> messages, {
    bool think = false,
  }) async => 1;
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
    yield LLMChunk(
      model: model,
      createdAt: DateTime.now(),
      done: false,
      message: LLMChunkMessage(content: 'Hello', role: LLMRole.assistant),
    );
    yield LLMChunk(
      model: model,
      createdAt: DateTime.now(),
      done: true,
      message: null,
    );
  }

  @override
  LlamaCppInferenceMetrics get lastMetrics => const LlamaCppInferenceMetrics(
    promptTokens: 1,
    generatedTokens: 1,
    modelLoadMicros: 1,
    contextInitMicros: 1,
    promptEvalMicros: 1,
    generationMicros: 1,
    timeToFirstTokenMicros: 1,
    completionReason: 'outputLimit',
  );
  @override
  Future<void> close() => _closing ??= _finish();
  Future<void> _finish() async {
    if (!fixture.closeStarted.isCompleted) fixture.closeStarted.complete();
    await fixture.closeGate?.future;
    fixture.closes++;
  }

  @override
  Future<void> cancelActiveInference() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
