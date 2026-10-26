import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/model_downloader.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';

class _MockSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 100;
  @override
  bool get isCharging => true;
  @override
  bool get isInSaveMode => false;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  bool isSafeForDownload() => true;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  String? unsafeReasonDownload() => null;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Stream<bool> get onHealthChanged => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

class _UnsafeSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 10;
  @override
  bool get isCharging => false;
  @override
  bool get isInSaveMode => true;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.none;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => false;
  @override
  bool isSafeForDownload() => false;
  @override
  String? unsafeReasonHeavy() => 'Battery too low';
  @override
  String? unsafeReasonDownload() => 'No connectivity';
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Stream<bool> get onHealthChanged => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

class _TestEnvironment implements ModelDownloadEnvironment {
  _TestEnvironment(this.directory, {this.usableBytes});

  final Directory directory;
  int? usableBytes;
  DateTime clock = DateTime.utc(2026, 9, 1);
  final List<Duration> delays = [];
  String? persistedPath;
  Object? persistenceFailure;
  Future<void> Function(String)? beforePersist;

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    clock = clock.add(duration);
  }

  @override
  Future<Directory> documentsDirectory() async => directory;

  @override
  DateTime now() => clock;

  @override
  Future<void> persistVerifiedModel(
    String filePath,
    ModelDownloadSpec spec,
  ) async {
    await beforePersist?.call(filePath);
    if (persistenceFailure case final Object error) throw error;
    expect(await File(filePath).readAsBytes(), isNotEmpty);
    persistedPath = filePath;
  }

  @override
  Future<int?> usableStorageBytes() async => usableBytes;
}

class _TestRegistry implements BundledModelRegistry {
  _TestRegistry([this.row]);

  Map<String, Object?>? row;
  String? clearedPath;

  @override
  Future<Map<String, Object?>?> read() async => row;

  @override
  Future<void> clearInstallation(String localPath) async {
    clearedPath = localPath;
    row = null;
  }
}

Map<String, Object?> _installedModel(String path) => {
  'id': BundledModelManifest.id,
  'display_name': BundledModelManifest.displayName,
  'local_path': path,
  'source': BundledModelManifest.source,
  'sha256': BundledModelManifest.sha256,
  'byte_size': BundledModelManifest.byteSize,
  'compatibility_status': 'compatible',
  'installation_state': 'installed',
};

class _LocalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

Future<HttpServer> _server(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

ModelDownloadSpec _spec(HttpServer server, List<int> bytes) =>
    ModelDownloadSpec(
      url: 'http://${server.address.address}:${server.port}/model.gguf',
      fileName: 'model.gguf',
      byteSize: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _LocalHttpOverrides();

  group('DownloadResult', () {
    test('success factory creates success result', () {
      final result = DownloadResult.success('/path/to/file');
      expect(result.isSuccess, true);
      expect(result.isCancelled, false);
      expect(result.error, isNull);
      expect(result.filePath, '/path/to/file');
    });

    test('error factory creates error result', () {
      final result = DownloadResult.error('Something went wrong');
      expect(result.isSuccess, false);
      expect(result.isCancelled, false);
      expect(result.error, 'Something went wrong');
      expect(result.filePath, isNull);
    });

    test('cancelled factory creates cancelled result', () {
      final result = DownloadResult.cancelled();
      expect(result.isSuccess, false);
      expect(result.isCancelled, true);
      expect(result.error, isNull);
      expect(result.filePath, isNull);
    });
  });

  group('ModelDownloader', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'vitalis-downloader-',
      );
    });

    tearDown(() async {
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test(
      'verified existing model is reused without a network request or copy headroom',
      () async {
        final bytes = 'GGUFdisposable'.codeUnits;
        final file = File('${temporaryDirectory.path}/model.gguf');
        await file.writeAsBytes(bytes);
        var requests = 0;
        final server = await _server((request) async {
          requests++;
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        });
        addTearDown(server.close);
        final environment = _TestEnvironment(
          temporaryDirectory,
          usableBytes: 0,
        );
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isTrue);
        expect(requests, 0);
        expect(environment.persistedPath, file.path);
        expect(await file.readAsBytes(), bytes);
      },
    );

    test(
      'installed model discovery reflects file presence without deleting records',
      () async {
        final file = File('${temporaryDirectory.path}/installed.gguf');
        await file.writeAsString('GGUFdisposable');
        final records = _TestRegistry(_installedModel(file.path));
        final downloader = ModelDownloader(
          sentinel: _MockSentinel(),
          registry: records,
        );
        expect(await downloader.isModelDownloaded(), isTrue);
        await file.delete();
        expect(await downloader.isModelDownloaded(), isFalse);
        expect(records.row, isNotNull);
      },
    );

    for (final seconds in [9, 120]) {
      test('HTTP-date Retry-After is bounded for $seconds seconds', () async {
        final bytes = 'GGUFdisposable'.codeUnits;
        final environment = _TestEnvironment(temporaryDirectory);
        var requests = 0;
        final server = await _server((request) async {
          if (++requests == 1) {
            request.response.statusCode = HttpStatus.tooManyRequests;
            request.response.headers.set(
              'Retry-After',
              HttpDate.format(
                environment.clock.add(Duration(seconds: seconds)),
              ),
            );
          } else {
            request.response.contentLength = bytes.length;
            request.response.add(bytes);
          }
          await request.response.close();
        });
        addTearDown(server.close);
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isTrue);
        expect(requests, 2);
        expect(environment.delays, [
          Duration(seconds: seconds > 60 ? 60 : seconds),
        ]);
      });
    }

    test('permanent HTTP rejection removes only its owned partial', () async {
      final bytes = 'GGUFdisposable'.codeUnits;
      final partial = File('${temporaryDirectory.path}/model.gguf.part');
      final unrelated = File('${temporaryDirectory.path}/unrelated.part');
      await partial.writeAsBytes(bytes.sublist(0, 4));
      await unrelated.writeAsString('Disposable retained partial');
      final server = await _server((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(server.close);
      final result = await ModelDownloader(
        sentinel: _MockSentinel(),
        environment: _TestEnvironment(temporaryDirectory),
        spec: _spec(server, bytes),
      ).download(onProgress: (_, __, ___) {});
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('HTTP 404'));
      expect(await partial.exists(), isFalse);
      expect(await unrelated.readAsString(), 'Disposable retained partial');
    });

    for (final body in <List<int>>[[], 'GGUFshort'.codeUnits]) {
      test(
        'complete but undersized HTTP body (${body.length} bytes) cannot activate',
        () async {
          final bytes = 'GGUFdisposable'.codeUnits;
          final server = await _server((request) async {
            request.response.contentLength = body.length;
            request.response.add(body);
            await request.response.close();
          });
          addTearDown(server.close);
          final environment = _TestEnvironment(temporaryDirectory);
          final result = await ModelDownloader(
            sentinel: _MockSentinel(),
            environment: environment,
            spec: _spec(server, bytes),
          ).download(onProgress: (_, __, ___) {});
          expect(result.isSuccess, isFalse);
          expect(environment.persistedPath, isNull);
          expect(
            await File('${temporaryDirectory.path}/model.gguf').exists(),
            isFalse,
          );
        },
      );
    }

    test(
      'failed new activation rolls back to its valid partial when unowned',
      () async {
        final bytes = 'GGUFdisposable'.codeUnits;
        final server = await _server((request) async {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        });
        addTearDown(server.close);
        final environment = _TestEnvironment(temporaryDirectory)
          ..persistenceFailure = StateError('Injected projection failure');
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isFalse);
        expect(
          await File('${temporaryDirectory.path}/model.gguf').exists(),
          isFalse,
        );
        expect(
          await File(
            '${temporaryDirectory.path}/model.gguf.part',
          ).readAsBytes(),
          bytes,
        );
      },
    );

    test(
      'final installation cannot move into a destination owned by native work',
      () async {
        final bytes = 'GGUFdisposable'.codeUnits;
        final destination = File('${temporaryDirectory.path}/model.gguf');
        final entered = Completer<void>();
        final release = Completer<void>();
        final ownership = LlamaCppChatRepository.withModelFilesMutation(
          [destination.path],
          () async {
            entered.complete();
            await release.future;
          },
        );
        await entered.future;
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await ownership;
        });
        final server = await _server((request) async {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        });
        addTearDown(server.close);
        final environment = _TestEnvironment(temporaryDirectory);
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isFalse);
        expect(await destination.exists(), isFalse);
        expect(await File('${destination.path}.part').readAsBytes(), bytes);
        expect(environment.persistedPath, isNull);
      },
    );

    test(
      'activation rollback preserves a final file still owned by native work',
      () async {
        final bytes = 'GGUFdisposable'.codeUnits;
        final entered = Completer<void>();
        final release = Completer<void>();
        Future<void>? ownership;
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await ownership;
        });
        final environment = _TestEnvironment(temporaryDirectory)
          ..beforePersist = (path) async {
            ownership = LlamaCppChatRepository.withModelFilesMutation(
              [path],
              () async {
                entered.complete();
                await release.future;
              },
            );
            await entered.future;
          }
          ..persistenceFailure = StateError('Injected activation failure');
        final server = await _server((request) async {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        });
        addTearDown(server.close);
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isFalse);
        expect(
          await File('${temporaryDirectory.path}/model.gguf').readAsBytes(),
          bytes,
        );
        expect(
          await File('${temporaryDirectory.path}/model.gguf.part').exists(),
          isFalse,
        );
        expect(environment.persistedPath, isNull);
      },
    );

    test(
      'independent downloaders cannot write the same partial concurrently',
      () async {
        final bytes = 'GGUFdisposable'.codeUnits;
        final entered = Completer<void>();
        final duplicate = Completer<void>();
        final release = Completer<void>();
        var requests = 0;
        final server = await _server((request) async {
          if (++requests == 1) {
            entered.complete();
          } else if (!duplicate.isCompleted) {
            duplicate.complete();
          }
          await release.future;
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        });
        addTearDown(server.close);
        final environment = _TestEnvironment(temporaryDirectory);
        ModelDownloader downloader() => ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        );
        final first = downloader().download(onProgress: (_, __, ___) {});
        await entered.future;
        final second = downloader().download(onProgress: (_, __, ___) {});
        final duplicateWriter = await Future.any([
          duplicate.future.then((_) => true),
          second.then((_) => false),
        ]).timeout(const Duration(seconds: 10));
        release.complete();
        final results = await Future.wait([first, second]);
        expect(duplicateWriter, isFalse);
        expect(requests, 1);
        expect(results.first.isSuccess, isTrue);
        expect(results.last.isSuccess, isFalse);
        expect(
          await File('${temporaryDirectory.path}/model.gguf').readAsBytes(),
          bytes,
        );
      },
    );

    test(
      'failed activation never removes a preexisting verified model',
      () async {
        final bytes = 'GGUFdisposable'.codeUnits;
        final installed = File('${temporaryDirectory.path}/model.gguf');
        await installed.writeAsBytes(bytes);
        final server = await _server((request) async {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        });
        addTearDown(server.close);
        final environment = _TestEnvironment(temporaryDirectory)
          ..persistenceFailure = StateError('Injected activation failure');
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isFalse);
        expect(await installed.exists(), isTrue);
        expect(await installed.readAsBytes(), bytes);
      },
    );

    test(
      'download refuses to replace an existing different model file',
      () async {
        final bytes = 'GGUFnew'.codeUnits;
        final original = 'GGUFpreserved'.codeUnits;
        final installed = File('${temporaryDirectory.path}/model.gguf');
        await installed.writeAsBytes(original);
        final server = await _server((request) async {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        });
        addTearDown(server.close);
        final environment = _TestEnvironment(temporaryDirectory);
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isFalse);
        expect(await installed.readAsBytes(), original);
        expect(environment.persistedPath, isNull);
      },
    );

    test('isModelDownloaded returns false when no model saved', () async {
      final downloader = ModelDownloader(
        sentinel: _MockSentinel(),
        registry: _TestRegistry(),
      );
      final result = await downloader.isModelDownloaded();
      expect(result, false);
    });

    test(
      'resetState delegates bundled identity to registry ownership',
      () async {
        final model = File('${temporaryDirectory.path}/model.gguf');
        await model.writeAsBytes([1, 2, 3]);
        final registry = _TestRegistry(_installedModel(model.path));
        final resetRegistry = _ResetRegistry();
        final downloader = ModelDownloader(
          sentinel: _MockSentinel(),
          registry: registry,
          resetRegistry: resetRegistry,
        );
        await downloader.resetState();
        expect(resetRegistry.ids, [BundledModelManifest.id]);
        expect(await model.exists(), isTrue);
        expect(registry.clearedPath, isNull);
      },
    );

    test('download returns error when sentinel rejects', () async {
      final downloader = ModelDownloader(sentinel: _UnsafeSentinel());
      final result = await downloader.download(onProgress: (_, __, ___) {});
      expect(result.isSuccess, false);
      expect(result.error, 'No connectivity');
    });

    test('cooldown enforcement returns error within 3 seconds', () async {
      final environment = _TestEnvironment(temporaryDirectory);
      final downloader = ModelDownloader(
        sentinel: _MockSentinel(),
        environment: environment,
        spec: const ModelDownloadSpec(
          url: 'http://127.0.0.1:1/model.gguf',
          fileName: 'model.gguf',
          byteSize: 1,
          sha256:
              'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb',
        ),
      );
      final result1 = await downloader.download(
        onProgress: (_, __, ___) {},
        cancelToken: CancelToken()..cancel(),
      );
      expect(result1.isCancelled, true);

      final result2 = await downloader.download(onProgress: (_, __, ___) {});
      expect(result2.isSuccess, false);
      expect(result2.error, 'Please wait before retrying download.');
    });

    test(
      'resumes a partial file with Range and completes atomically',
      () async {
        final bytes = List<int>.generate(64, (index) => index);
        late HttpServer server;
        server = await _server((request) async {
          expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=8-');
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 8-63/64',
          );
          request.response.add(bytes.sublist(8));
          await request.response.close();
        });
        addTearDown(server.close);
        await File(
          '${temporaryDirectory.path}/model.gguf.part',
        ).writeAsBytes(bytes.sublist(0, 8));
        final environment = _TestEnvironment(temporaryDirectory);
        final result = await ModelDownloader(
          sentinel: _MockSentinel(),
          environment: environment,
          spec: _spec(server, bytes),
        ).download(onProgress: (_, __, ___) {});
        expect(result.isSuccess, isTrue);
        expect(await File(result.filePath!).readAsBytes(), bytes);
        expect(File('${result.filePath}.part').existsSync(), isFalse);
        expect(environment.persistedPath, result.filePath);
      },
    );

    test('restarts safely when a server ignores Range', () async {
      final bytes = List<int>.generate(32, (index) => 255 - index);
      var requests = 0;
      late HttpServer server;
      server = await _server((request) async {
        requests++;
        request.response.statusCode = HttpStatus.ok;
        request.response.add(bytes);
        await request.response.close();
      });
      addTearDown(server.close);
      await File(
        '${temporaryDirectory.path}/model.gguf.part',
      ).writeAsBytes(bytes.sublist(0, 4));
      final result = await ModelDownloader(
        sentinel: _MockSentinel(),
        environment: _TestEnvironment(temporaryDirectory),
        spec: _spec(server, bytes),
      ).download(onProgress: (_, __, ___) {});
      expect(result.isSuccess, isTrue);
      expect(requests, 2);
      expect(await File(result.filePath!).readAsBytes(), bytes);
    });

    test('honors Retry-After for 429 then succeeds', () async {
      final bytes = List<int>.generate(16, (index) => index * 3);
      var requests = 0;
      late HttpServer server;
      server = await _server((request) async {
        requests++;
        if (requests == 1) {
          request.response.statusCode = HttpStatus.tooManyRequests;
          request.response.headers.set(HttpHeaders.retryAfterHeader, '7');
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
      });
      addTearDown(server.close);
      final environment = _TestEnvironment(temporaryDirectory);
      final result = await ModelDownloader(
        sentinel: _MockSentinel(),
        environment: environment,
        spec: _spec(server, bytes),
      ).download(onProgress: (_, __, ___) {});
      expect(result.isSuccess, isTrue);
      expect(environment.delays, [const Duration(seconds: 7)]);
    });

    test('retries transient 5xx and preserves partial content', () async {
      final bytes = List<int>.generate(24, (index) => index + 10);
      var requests = 0;
      late HttpServer server;
      server = await _server((request) async {
        requests++;
        if (requests == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
        } else {
          request.response.add(bytes);
        }
        await request.response.close();
      });
      addTearDown(server.close);
      final environment = _TestEnvironment(temporaryDirectory);
      final result = await ModelDownloader(
        sentinel: _MockSentinel(),
        environment: environment,
        spec: _spec(server, bytes),
      ).download(onProgress: (_, __, ___) {});
      expect(result.isSuccess, isTrue);
      expect(requests, 2);
      expect(environment.delays, [const Duration(seconds: 2)]);
    });

    test('rejects disk shortage before opening HTTP', () async {
      final environment = _TestEnvironment(temporaryDirectory, usableBytes: 1);
      final result = await ModelDownloader(
        sentinel: _MockSentinel(),
        environment: environment,
        spec: const ModelDownloadSpec(
          url: 'http://127.0.0.1:1/model.gguf',
          fileName: 'model.gguf',
          byteSize: 10,
          sha256: 'unused',
        ),
      ).download(onProgress: (_, __, ___) {});
      expect(result.error, contains('Not enough free storage'));
    });

    test('rejects hash mismatch and never activates the file', () async {
      final bytes = [1, 2, 3, 4];
      late HttpServer server;
      server = await _server((request) async {
        request.response.add(bytes);
        await request.response.close();
      });
      addTearDown(server.close);
      final environment = _TestEnvironment(temporaryDirectory);
      final result = await ModelDownloader(
        sentinel: _MockSentinel(),
        environment: environment,
        spec: ModelDownloadSpec(
          url: 'http://${server.address.address}:${server.port}/model.gguf',
          fileName: 'model.gguf',
          byteSize: bytes.length,
          sha256: sha256.convert([9, 9, 9, 9]).toString(),
        ),
      ).download(onProgress: (_, __, ___) {});
      expect(result.error, 'Model file integrity check failed');
      expect(environment.persistedPath, isNull);
      expect(File('${temporaryDirectory.path}/model.gguf').existsSync(), false);
    });

    test('reports truncated content and preserves the partial file', () async {
      final bytes = List<int>.generate(40, (index) => index);
      final partial = File('${temporaryDirectory.path}/model.gguf.part');
      await partial.writeAsBytes(bytes.sublist(0, 5));
      late HttpServer server;
      server = await _server((request) async {
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=5-');
        request.response.statusCode = HttpStatus.partialContent;
        request.response.contentLength = bytes.length - 5;
        try {
          request.response.add(bytes.sublist(5, 10));
          await request.response.close();
        } on HttpException {
          // Intentionally terminate below Content-Length.
        }
      });
      addTearDown(server.close);
      final environment = _TestEnvironment(temporaryDirectory);
      final result = await ModelDownloader(
        sentinel: _MockSentinel(),
        environment: environment,
        spec: _spec(server, bytes),
      ).download(onProgress: (_, __, ___) {});
      expect(result.isSuccess, isFalse);
      expect(partial.existsSync(), isTrue);
      expect(partial.lengthSync(), greaterThan(0));
    });

    test('cancellation preserves an existing resumable partial file', () async {
      final partial = File('${temporaryDirectory.path}/model.gguf.part');
      await partial.writeAsBytes([1, 2, 3]);
      final result =
          await ModelDownloader(
            sentinel: _MockSentinel(),
            environment: _TestEnvironment(temporaryDirectory),
            spec: const ModelDownloadSpec(
              url: 'http://127.0.0.1:1/model.gguf',
              fileName: 'model.gguf',
              byteSize: 6,
              sha256: 'unused',
            ),
          ).download(
            onProgress: (_, __, ___) {},
            cancelToken: CancelToken()..cancel(),
          );
      expect(result.isCancelled, isTrue);
      expect(await partial.readAsBytes(), [1, 2, 3]);
    });

    test('getModelPath returns null when no model saved', () async {
      final downloader = ModelDownloader(
        sentinel: _MockSentinel(),
        registry: _TestRegistry(),
      );
      final path = await downloader.getModelPath();
      expect(path, isNull);
    });

    test('getModelPath returns path when model saved', () async {
      final registry = _TestRegistry(_installedModel('/some/path/model.gguf'));
      final downloader = ModelDownloader(
        sentinel: _MockSentinel(),
        registry: registry,
      );
      final path = await downloader.getModelPath();
      expect(path, '/some/path/model.gguf');
    });
  });
}

final class _ResetRegistry extends ModelRegistryService {
  final ids = <String>[];
  @override
  Future<void> uninstall(String modelId) async => ids.add(modelId);
}
