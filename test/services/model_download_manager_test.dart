import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_download_job.dart';
import 'package:vitalis_app/models/model_verification_phase.dart';
import 'package:vitalis_app/services/model_download_manager.dart';
import 'package:vitalis_app/services/model_download_staging.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/native_transfer_stop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('vitalis/model_transfers');
  late Directory sandbox;

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
  });

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = Directory.systemTemp.createTempSync('vitalis_download_manager_');
    await databaseFactory.setDatabasesPath(sandbox.path);
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    final database = File(p.join(sandbox.path, 'vitalis.db'));
    if (await database.exists()) await database.delete();
    for (final entity in sandbox.listSync()) {
      if (entity is Directory && p.basename(entity.path) != 'databases') {
        await entity.delete(recursive: true);
      }
    }
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  _Harness harness({int? usableBytes, _Transfer? transfer, _Jobs? jobs}) =>
      _Harness(
        root: sandbox,
        usableBytes: usableBytes,
        transfer: transfer,
        jobs: jobs,
      );

  test(
    'download again creates a new job after a completed model is uninstalled',
    () async {
      final h = harness(
        transfer: _Transfer(
          payloads: {
            'one.gguf': [71, 71, 85, 70],
          },
        ),
      );
      final first = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      expect(
        (await h.manager.run(first)).state,
        ModelDownloadJobState.completed,
      );
      await DatabaseHelper.instance.clearModelInstallation(first.modelId);
      final next = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      expect(next.id, isNot(first.id));
      expect(next.state, ModelDownloadJobState.queued);
      expect(h.jobs.values.first.state, ModelDownloadJobState.completed);
      expect(h.jobs.values, hasLength(2));
      expect(
        (await h.manager.run(next)).state,
        ModelDownloadJobState.completed,
      );
    },
  );

  test('paused progress includes bytes retained after the last poll', () async {
    final h = harness(
      transfer: _Transfer(
        payloads: {
          'one.gguf': [71, 71],
        },
        pauseAfterWrite: true,
      ),
    );
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    final paused = await h.manager.run(job);
    expect(paused.state, ModelDownloadJobState.paused);
    expect(paused.downloadedBytes, 2);
    expect(h.jobs.values.single.downloadedBytes, 2);
  });

  test(
    'enqueue rejects gated, mismatched, incomplete, and disk-risk artifacts',
    () async {
      final h = harness(usableBytes: 1);
      await expectLater(
        h.manager.enqueue(model: _model(gated: true), variant: _variant()),
        throwsStateError,
      );
      await expectLater(
        h.manager.enqueue(
          model: _model(),
          variant: const GgufVariant(
            repository: 'other/model',
            revision: _revision,
            displayName: 'Q4',
            files: [GgufFile(name: 'one.gguf', sizeBytes: 1)],
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        h.manager.enqueue(
          model: _model(),
          variant: const GgufVariant(
            repository: 'owner/model',
            revision: _revision,
            displayName: 'Q4',
            files: [GgufFile(name: 'one.gguf', sizeBytes: null)],
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        h.manager.enqueue(model: _model(), variant: _variant()),
        throwsStateError,
      );
    },
  );

  test('enqueue persists immutable model, shards, and job', () async {
    final h = harness(usableBytes: 1000000);
    final job = await h.manager.enqueue(
      model: _model(),
      variant: _variant(split: true),
    );

    expect(job.state, ModelDownloadJobState.queued);
    expect(job.totalBytes, 8);
    expect(job.modelId, startsWith('hf-'));
    expect(h.jobs.values.single.id, job.id);
    final descriptor = await DatabaseHelper.instance.getModel(job.modelId);
    expect(descriptor?['installation_state'], 'downloading');
    expect(
      await DatabaseHelper.instance.getModelFiles(job.modelId),
      hasLength(2),
    );
  });

  test(
    'pending native stop rejection retains a hold without Dart cancellation',
    () async {
      final h = harness(usableBytes: 1000000);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final partial = await ModelDownloadStaging(
        await h.files.modelDirectory(job.modelId),
      ).partial(job.id, 'one.gguf');
      await partial.writeAsString('GG');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            nativeChannel,
            (_) async => throw PlatformException(code: 'transfer_stop_pending'),
          );
      final manager = ModelDownloadManager(
        jobs: h.jobs,
        files: h.files,
        registry: h.registry,
        transfers: const AndroidDurableTransferAdapter(channel: nativeChannel),
      );
      await expectLater(
        manager.run(job),
        throwsA(isA<NativeTransferStopUnconfirmed>()),
      );
      expect(h.jobs.values.single.errorCode, 'native_cancellation_pending');
      expect(await partial.readAsString(), 'GG');
      await expectLater(
        manager.enqueue(model: _model(), variant: _variant()),
        throwsStateError,
      );
      expect(h.registry.validated, isEmpty);
    },
  );

  test('restart reconciliation retains pending native stop holds', () async {
    final h = harness(usableBytes: 1000000);
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          nativeChannel,
          (call) async => [
            {
              'jobId': job.id,
              'transferId': 'owned',
              'state': 'cancelled',
              'downloadedBytes': 2,
              'stopAcknowledged': false,
            },
          ],
        );
    final manager = ModelDownloadManager(
      jobs: h.jobs,
      files: h.files,
      registry: h.registry,
      transfers: const AndroidDurableTransferAdapter(channel: nativeChannel),
    );
    final restored = await manager.restoreJobs();
    expect(restored.single.errorCode, 'native_cancellation_pending');
    await expectLater(
      manager.enqueue(model: _model(), variant: _variant()),
      throwsStateError,
    );
    await expectLater(manager.run(job), throwsStateError);
  });

  test('cancel preserves a legacy partial with unproven ownership', () async {
    final h = harness(usableBytes: 1000000);
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    final directory = await h.files.modelDirectory(job.modelId);
    final legacy = File(p.join(directory.path, 'one.gguf.part'));
    await legacy.writeAsString('personal-preserved-partial');

    await h.manager.cancel(job.id);

    expect(await legacy.exists(), isTrue);
    expect(await legacy.readAsString(), 'personal-preserved-partial');
    expect(h.jobs.values.single.state, ModelDownloadJobState.cancelled);
  });

  test(
    'active native stop failure preserves its partial and recovery hold',
    () async {
      final h = harness(usableBytes: 1000000);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final partial = await ModelDownloadStaging(
        await h.files.modelDirectory(job.modelId),
      ).partial(job.id, 'one.gguf');
      await partial.writeAsString('GG');
      final entered = Completer<void>();
      final release = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'enqueue') return <String, Object?>{};
            if (call.method == 'status') {
              if (!entered.isCompleted) entered.complete();
              await release.future;
              return {'state': 'running', 'downloadedBytes': 2};
            }
            if (call.method == 'cancel') {
              throw PlatformException(code: 'nativeUnavailable');
            }
            throw StateError('Unexpected native method');
          });
      final manager = ModelDownloadManager(
        jobs: h.jobs,
        files: h.files,
        transfers: const AndroidDurableTransferAdapter(
          channel: nativeChannel,
          pollInterval: Duration.zero,
        ),
        database: DatabaseHelper.instance,
        registry: h.registry,
      );
      final running = manager
          .run(job)
          .then<Object?>((value) => value, onError: (Object error) => error);
      await entered.future;
      final stopping = manager
          .cancel(job.id)
          .then<Object?>((_) => null, onError: (Object error) => error);
      release.complete();
      expect(await stopping, isA<NativeTransferStopUnconfirmed>());
      expect(await running, isA<NativeTransferStopUnconfirmed>());
      expect(await partial.readAsString(), 'GG');
      expect(h.jobs.values.single.state, ModelDownloadJobState.failed);
      expect(h.jobs.values.single.errorCode, 'native_cancellation_pending');
      expect(h.registry.validated, isEmpty);
    },
  );

  for (final scenario in [
    (phase: 'native pause', fail: false),
    (phase: 'pause persistence', fail: false),
    (phase: 'native pause with cancel failure', fail: true),
  ]) {
    final phase = scenario.phase;
    test(
      'cancel during $phase requires its own native acknowledgement',
      () async {
        final jobs = _PauseWriteJobs();
        final h = harness(usableBytes: 1000000, jobs: jobs);
        final job = await h.manager.enqueue(
          model: _model(),
          variant: _variant(),
        );
        final partial = await ModelDownloadStaging(
          await h.files.modelDirectory(job.modelId),
        ).partial(job.id, 'one.gguf');
        await partial.writeAsString('GG');
        final runningStatus = Completer<void>();
        final statusEntered = Completer<void>();
        final pauseIssued = Completer<void>();
        final pauseAcknowledged = Completer<void>();
        final cancelIssued = Completer<void>();
        final cancelAcknowledged = Completer<void>();
        var nativeState = 'running';
        var cancelCommands = 0;
        String? nativeTransferId;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, (call) async {
              if (call.method == 'enqueue') {
                nativeTransferId =
                    (call.arguments! as Map)['transferId'] as String;
                return {'state': 'queued'};
              }
              if (call.method == 'pause') {
                nativeState = 'paused';
                pauseIssued.complete();
                return null;
              }
              if (call.method == 'cancel') {
                expect(
                  (call.arguments! as Map)['transferId'],
                  nativeTransferId,
                );
                nativeState = 'cancelled';
                cancelCommands++;
                if (!cancelIssued.isCompleted) cancelIssued.complete();
                if (scenario.fail)
                  throw PlatformException(code: 'nativeUnavailable');
                return null;
              }
              if (call.method == 'list')
                return [
                  {'jobId': job.id, 'transferId': nativeTransferId},
                ];
              if (call.method == 'status') {
                final state = nativeState;
                if (state == 'running') {
                  statusEntered.complete();
                  await runningStatus.future;
                } else if (state == 'paused') {
                  await pauseAcknowledged.future;
                } else {
                  await cancelAcknowledged.future;
                }
                return {
                  'jobId': job.id,
                  'transferId': nativeTransferId,
                  'state': state,
                  'downloadedBytes': 2,
                  'stopAcknowledged': state != 'running',
                };
              }
              throw StateError('Unexpected native method');
            });
        final manager = ModelDownloadManager(
          jobs: jobs,
          files: h.files,
          registry: h.registry,
          transfers: const AndroidDurableTransferAdapter(
            channel: nativeChannel,
            pollInterval: Duration.zero,
          ),
        );
        final running = manager
            .run(job)
            .then<Object?>((value) => value, onError: (Object error) => error);
        await statusEntered.future;
        manager.pause(job.id);
        await pauseIssued.future;
        if (phase == 'pause persistence') {
          pauseAcknowledged.complete();
          await jobs.pausedWriteEntered.future;
        }
        var finished = false;
        final stopping = manager.cancel(job.id).then<Object?>((_) {
          finished = true;
          return null;
        }, onError: (Object error) => error);
        final repeatedStop = manager
            .cancel(job.id)
            .then<Object?>((_) => null, onError: (Object error) => error);
        if (!pauseAcknowledged.isCompleted) pauseAcknowledged.complete();
        jobs.releasePausedWrite.complete();
        try {
          expect(
            await Future.any([
              cancelIssued.future.then((_) => true),
              stopping.then((_) => false),
            ]),
            isTrue,
            reason: 'pause acknowledgement does not acknowledge cancel',
          );
          expect(finished, isFalse);
          expect(await partial.readAsString(), 'GG');
        } finally {
          cancelAcknowledged.complete();
          runningStatus.complete();
          await running;
          await stopping;
          await repeatedStop;
        }
        expect(cancelCommands, 1);
        if (scenario.fail) {
          expect(await stopping, isA<PlatformException>());
          expect(await repeatedStop, isA<PlatformException>());
          expect(await partial.readAsString(), 'GG');
          expect(jobs.values.single.state, ModelDownloadJobState.paused);
          expect(jobs.values.single.errorCode, 'native_cancellation_pending');
          await expectLater(manager.run(job), throwsStateError);
        } else {
          expect(await stopping, isNull);
          expect(await repeatedStop, isNull);
          expect(await partial.exists(), isFalse);
          expect(jobs.values.single.state, ModelDownloadJobState.cancelled);
        }
      },
    );
  }

  test(
    'restart cancellation preserves partial until native acknowledgement',
    () async {
      final h = harness(usableBytes: 1000000);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final partial = await ModelDownloadStaging(
        await h.files.modelDirectory(job.modelId),
      ).partial(job.id, 'one.gguf');
      await partial.writeAsString('owned-partial');
      final requested = Completer<void>();
      final acknowledgement = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'list')
              return [
                {
                  'jobId': job.id,
                  'transferId': 'native-owned',
                  'state': 'running',
                  'downloadedBytes': 13,
                  'stopAcknowledged': false,
                },
              ];
            if (call.method == 'cancel') {
              if (!requested.isCompleted) requested.complete();
              return null;
            }
            if (call.method == 'status') {
              await acknowledgement.future;
              return {
                'jobId': job.id,
                'transferId': 'native-owned',
                'state': 'cancelled',
                'downloadedBytes': 0,
                'stopAcknowledged': true,
              };
            }
            throw StateError('Unexpected native method');
          });
      final restarted = ModelDownloadManager(
        jobs: h.jobs,
        files: h.files,
        transfers: const AndroidDurableTransferAdapter(
          channel: nativeChannel,
          pollInterval: Duration.zero,
        ),
        registry: _Registry(),
      );
      final cancellation = restarted.cancel(job.id);
      try {
        expect(
          await Future.any([
            requested.future.then((_) => true),
            cancellation.then((_) => false),
          ]),
          isTrue,
          reason: 'must address durable native job before deleting files',
        );
        expect(await partial.readAsString(), 'owned-partial');
        expect(h.jobs.values.single.state, ModelDownloadJobState.queued);
      } finally {
        acknowledgement.complete();
        await cancellation;
      }
      expect(await partial.exists(), isFalse);
      expect(h.jobs.values.single.state, ModelDownloadJobState.cancelled);
    },
  );

  test(
    'failed native restart cancellation preserves partial and job',
    () async {
      final h = harness(usableBytes: 1000000);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final partial = await ModelDownloadStaging(
        await h.files.modelDirectory(job.modelId),
      ).partial(job.id, 'one.gguf');
      await partial.writeAsString('must-survive');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (_) async {
            throw PlatformException(code: 'nativeUnavailable');
          });
      final restarted = ModelDownloadManager(
        jobs: h.jobs,
        files: h.files,
        transfers: const AndroidDurableTransferAdapter(channel: nativeChannel),
        registry: _Registry(),
      );

      await expectLater(
        restarted.cancel(job.id),
        throwsA(isA<PlatformException>()),
      );
      expect(await partial.readAsString(), 'must-survive');
      expect(h.jobs.values.single.state, ModelDownloadJobState.queued);
      expect(h.jobs.values.single.errorCode, 'native_cancellation_pending');
      // A stale caller and another manager must not resume an uncertain writer.
      await expectLater(h.manager.run(job), throwsStateError);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            nativeChannel,
            (_) async => [
              {
                'jobId': job.id,
                'transferId': 'native-owned',
                'state': 'cancelled',
                'downloadedBytes': 13,
                'stopAcknowledged': false,
              },
            ],
          );
      final restored = await restarted.restoreJobs();
      expect(restored.single.errorCode, 'native_cancellation_pending');
      expect(restored.single.state, ModelDownloadJobState.queued);
      expect(await partial.readAsString(), 'must-survive');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            final snapshot = {
              'jobId': job.id,
              'transferId': 'native-owned',
              'state': 'cancelled',
              'downloadedBytes': 0,
              'stopAcknowledged': true,
            };
            if (call.method == 'list') return [snapshot];
            if (call.method == 'cancel') return null;
            return snapshot;
          });
      await restarted.cancel(job.id);
      expect(h.jobs.values.single.state, ModelDownloadJobState.cancelled);
      expect(h.jobs.values.single.errorCode, isNull);
      expect(await partial.exists(), isFalse);
    },
  );

  test('a new job never adopts an unidentified legacy partial', () async {
    final transfer = _Transfer(payloads: {'one.gguf': 'GGUF'});
    final h = harness(usableBytes: 1000000, transfer: transfer);
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    final directory = await h.files.modelDirectory(job.modelId);
    final legacy = File(p.join(directory.path, 'one.gguf.part'));
    await legacy.writeAsString('XX');

    final result = await h.manager.run(job);

    expect(result.state, ModelDownloadJobState.completed);
    expect(transfer.requests.first.existingBytes, 0);
    expect(await legacy.readAsString(), 'XX');
  });

  test(
    'successive jobs remain distinct when the clock does not advance',
    () async {
      final h = harness(usableBytes: 1000000);
      final first = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      await h.manager.cancel(first.id);

      final second = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );

      expect(second.id, isNot(first.id));
      expect(h.jobs.values.length, 2);
      expect(h.jobs.values.first.state, ModelDownloadJobState.cancelled);
    },
  );

  test('equivalent queued downloads reuse the persisted job', () async {
    final h = harness(usableBytes: 1000000);
    final first = await h.manager.enqueue(model: _model(), variant: _variant());
    final second = await h.manager.enqueue(
      model: _model(),
      variant: _variant(),
    );
    expect(second.id, first.id);
    expect(h.jobs.values, hasLength(1));
  });

  test('enqueue cannot bypass another job native recovery hold', () async {
    final h = harness(usableBytes: 1000000);
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    await h.jobs.write(
      job.copyWith(
        state: ModelDownloadJobState.failed,
        errorCode: ModelDownloadJob.nativeCancellationPending,
      ),
    );
    final before = await DatabaseHelper.instance.getModel(job.modelId);
    await expectLater(
      h.manager.enqueue(model: _model(), variant: _variant()),
      throwsStateError,
    );
    expect(h.jobs.values, hasLength(1));
    expect(await DatabaseHelper.instance.getModel(job.modelId), before);
    expect(h.transfer.requests, isEmpty);
  });

  test(
    'a different persisted job cannot bypass same-model recovery hold',
    () async {
      final h = harness(usableBytes: 1000000);
      final first = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      await h.jobs.write(first.copyWith(state: ModelDownloadJobState.failed));
      final second = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      await h.jobs.write(
        first.copyWith(
          state: ModelDownloadJobState.failed,
          errorCode: ModelDownloadJob.nativeCancellationPending,
        ),
      );
      await expectLater(h.manager.run(second), throwsStateError);
      expect(h.transfer.requests, isEmpty);
      expect(h.jobs.values.last.state, ModelDownloadJobState.queued);
      expect(h.jobs.values.first.errorCode, 'native_cancellation_pending');
    },
  );

  test(
    'cancelling an older job preserves the newer job registry state',
    () async {
      final h = harness(
        usableBytes: 1000000,
        transfer: _Transfer(payloads: {'one.gguf': 'BAD'}),
      );
      final first = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      expect((await h.manager.run(first)).state, ModelDownloadJobState.failed);
      final second = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      final before = await DatabaseHelper.instance.getModel(second.modelId);
      final directory = await h.files.modelDirectory(first.modelId);
      final own = await ModelDownloadStaging(
        directory,
      ).partial(first.id, 'one.gguf');
      final other = await ModelDownloadStaging(
        directory,
      ).partial(second.id, 'one.gguf');
      await other.writeAsString('newer-partial');

      await h.manager.cancel(first.id);

      expect(await own.exists(), isFalse);
      expect(await other.readAsString(), 'newer-partial');
      expect(await DatabaseHelper.instance.getModel(second.modelId), before);
      expect(h.jobs.values.last.state, ModelDownloadJobState.queued);
    },
  );

  test('cancelling a completed job cannot invalidate its model', () async {
    final h = harness(
      usableBytes: 1000000,
      transfer: _Transfer(payloads: {'one.gguf': 'GGUF'}),
    );
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    expect((await h.manager.run(job)).state, ModelDownloadJobState.completed);
    final before = await DatabaseHelper.instance.getModel(job.modelId);

    await h.manager.cancel(job.id);

    expect(h.jobs.values.single.state, ModelDownloadJobState.completed);
    expect(await DatabaseHelper.instance.getModel(job.modelId), before);
    expect(
      await File(p.join(sandbox.path, job.modelId, 'one.gguf')).readAsString(),
      'GGUF',
    );
  });

  test(
    'enqueue never resets an installed model or its shard metadata',
    () async {
      final h = harness(usableBytes: 1000000);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final row = (await DatabaseHelper.instance.getModel(job.modelId))!;
      await DatabaseHelper.instance.upsertModel({
        ...row,
        'installation_state': 'installed',
        'local_path': '/preserved/model.gguf',
      });
      final before = await DatabaseHelper.instance.getModel(job.modelId);
      final shards = await DatabaseHelper.instance.getModelFiles(job.modelId);
      await expectLater(
        h.manager.enqueue(model: _model(), variant: _variant()),
        throwsStateError,
      );
      expect(await DatabaseHelper.instance.getModel(job.modelId), before);
      expect(await DatabaseHelper.instance.getModelFiles(job.modelId), shards);
    },
  );

  test('same variant label cannot replace queued artifact identity', () async {
    final h = harness(usableBytes: 1000000);
    await h.manager.enqueue(model: _model(), variant: _variant());
    await expectLater(
      h.manager.enqueue(
        model: _model(),
        variant: _variant(hash: 'different'),
      ),
      throwsStateError,
    );
    expect(h.jobs.values, hasLength(1));
  });

  test('concurrent run callers share one transfer operation', () async {
    final barrier = Completer<void>();
    final transfer = _Transfer(
      payloads: {'one.gguf': 'GGUF'},
      barrier: barrier.future,
    );
    final h = harness(usableBytes: 1000000, transfer: transfer);
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    final first = h.manager.run(job);
    final second = h.manager.run(job);
    expect(second, same(first));
    await transfer.started.future;
    barrier.complete();
    final results = await Future.wait([first, second]);
    expect(
      results.every((job) => job.state == ModelDownloadJobState.completed),
      isTrue,
    );
    expect(transfer.requests, hasLength(1));
  });

  test('different managers cannot concurrently write the same model', () async {
    final barrier = Completer<void>();
    final transfer = _Transfer(
      payloads: {'one.gguf': 'GGUF'},
      barrier: barrier.future,
    );
    final h = harness(usableBytes: 1000000, transfer: transfer);
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    final first = h.manager.run(job);
    await transfer.started.future;
    final second = harness(usableBytes: 1000000);
    await expectLater(second.manager.run(job), throwsStateError);
    final cancelling = harness(usableBytes: 1000000, jobs: h.jobs);
    await expectLater(cancelling.manager.cancel(job.id), throwsStateError);
    barrier.complete();
    await first;
  });

  test(
    'active cancellation waits for transfer termination and job persistence',
    () async {
      final barrier = Completer<void>();
      final transfer = _Transfer(barrier: barrier.future);
      final h = harness(usableBytes: 1000000, transfer: transfer);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final running = h.manager.run(job);
      await transfer.started.future;
      var returned = false;
      final cancellation = h.manager.cancel(job.id).then((_) {
        returned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse);
      barrier.complete();
      await cancellation;
      expect((await running).state, ModelDownloadJobState.cancelled);
      expect(h.jobs.values.single.state, ModelDownloadJobState.cancelled);
    },
  );

  test(
    'expired native stop retains its SQLite hold and files after reopening',
    () async {
      final h = harness(usableBytes: 1000000);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final store = DatabaseDownloadJobStore(database: DatabaseHelper.instance);
      await store.write(job);
      final partial = await ModelDownloadStaging(
        await h.files.modelDirectory(job.modelId),
      ).partial(job.id, 'one.gguf');
      await partial.writeAsString('preserve-after-timeout');
      final entered = Completer<void>();
      final response = Completer<void>();
      late void Function() expire;
      Timer? deadline;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            if (call.method == 'list')
              return [
                {'jobId': job.id, 'transferId': 'owned'},
              ];
            if (call.method == 'cancel') return null;
            entered.complete();
            await response.future;
            return {
              'jobId': job.id,
              'transferId': 'owned',
              'state': 'cancelled',
              'stopAcknowledged': true,
            };
          });
      final manager = ModelDownloadManager(
        jobs: store,
        files: h.files,
        registry: _Registry(),
        transfers: AndroidDurableTransferAdapter(
          channel: nativeChannel,
          stopTimerFactory: (duration, callback) {
            expire = callback;
            return deadline = Timer(duration, callback);
          },
        ),
      );
      final cancellation = manager.cancel(job.id);
      final expected = expectLater(
        cancellation,
        throwsA(isA<NativeTransferStopUnconfirmed>()),
      );
      try {
        await entered.future;
        expire();
        await expected;
        expect(deadline!.isActive, isFalse);
        await DatabaseHelper.instance.close();
        final reopenedStore = DatabaseDownloadJobStore(
          database: DatabaseHelper.instance,
        );
        final persisted = (await reopenedStore.list()).single;
        expect(persisted.state, ModelDownloadJobState.queued);
        expect(persisted.errorCode, 'native_cancellation_pending');
        final restarted = ModelDownloadManager(
          jobs: reopenedStore,
          files: h.files,
          transfers: _Transfer(),
          registry: _Registry(),
        );
        await expectLater(restarted.run(job), throwsStateError);
        expect(
          (await restarted.restoreJobs()).single.errorCode,
          'native_cancellation_pending',
        );
        expect(await partial.readAsString(), 'preserve-after-timeout');
      } finally {
        if (!response.isCompleted) response.complete();
        deadline?.cancel();
        await cancellation.then<void>((_) {}, onError: (Object _) {});
      }
    },
  );

  test('database job store persists and restores typed jobs', () async {
    final h = harness(usableBytes: 1000000);
    final store = DatabaseDownloadJobStore(database: DatabaseHelper.instance);
    final queued = await h.manager.enqueue(
      model: _model(),
      variant: _variant(),
    );
    final running = queued.copyWith(
      state: ModelDownloadJobState.downloading,
      downloadedBytes: 2,
    );

    await store.write(queued);
    await store.write(running);

    final restored = await store.list();
    expect(restored, hasLength(1));
    expect(restored.single.state, ModelDownloadJobState.downloading);
    expect(restored.single.downloadedBytes, 2);
  });

  test(
    'job observers see committed progress, validation and completion',
    () async {
      final h = harness(
        usableBytes: 1000000,
        transfer: _Transfer(payloads: {'one.gguf': 'GGUF'}),
      );
      final observed = <ModelDownloadJob>[];
      void receive(ModelDownloadJob job) {
        expect(
          h.jobs.values.single,
          same(job),
          reason: 'Publish only after persistence',
        );
        observed.add(job);
      }

      h.manager.addJobListener(receive);
      final queued = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      final done = await h.manager.run(queued);
      expect(done.state, ModelDownloadJobState.completed);
      expect(observed.map((job) => job.state), [
        ModelDownloadJobState.queued,
        ModelDownloadJobState.downloading,
        ModelDownloadJobState.downloading,
        ModelDownloadJobState.validating,
        ModelDownloadJobState.completed,
      ]);
      expect(observed[2].downloadedBytes, 4);
      h.manager.removeJobListener(receive);
      final count = observed.length;
      await h.manager.cancel(done.id);
      expect(observed.length, count);
    },
  );

  test('failed job persistence never publishes an optimistic update', () async {
    final h = harness(usableBytes: 1000000, jobs: _RejectWriteJobs());
    final observed = <ModelDownloadJob>[];
    h.manager.addJobListener(observed.add);
    await expectLater(
      h.manager.enqueue(model: _model(), variant: _variant()),
      throwsStateError,
    );
    expect(observed, isEmpty);
  });

  test(
    'observer failure cannot fail a persisted transfer or starve other observers',
    () async {
      final h = harness(
        usableBytes: 1000000,
        transfer: _Transfer(payloads: {'one.gguf': 'GGUF'}),
      );
      final observed = <ModelDownloadJob>[];
      h.manager.addJobListener(
        (_) => throw StateError('fixture observer failure'),
      );
      h.manager.addJobListener(observed.add);
      final queued = await h.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      expect(
        (await h.manager.run(queued)).state,
        ModelDownloadJobState.completed,
      );
      expect(observed.last.state, ModelDownloadJobState.completed);
      expect(h.registry.validated, [queued.modelId]);
    },
  );

  test(
    'run transfers, hashes, validates and atomically completes one GGUF',
    () async {
      final transfer = _Transfer(payloads: {'one.gguf': 'GGUF'.codeUnits});
      final h = harness(usableBytes: 1000000, transfer: transfer);
      final job = await h.manager.enqueue(
        model: _model(),
        variant: _variant(hash: sha256.convert('GGUF'.codeUnits).toString()),
      );

      final result = await h.manager.run(job);

      expect(result.state, ModelDownloadJobState.completed);
      expect(result.downloadedBytes, 4);
      expect(h.registry.validated, [job.modelId]);
      final file = File(p.join(sandbox.path, job.modelId, 'one.gguf'));
      expect(await file.readAsString(), 'GGUF');
      expect(await File('${file.path}.part').exists(), isFalse);
      expect(transfer.requests.single.source.hasQuery, isFalse);
    },
  );

  test(
    'run completes a split set before activating its primary shard',
    () async {
      final transfer = _Transfer(
        payloads: {'one.gguf': 'GGUF', 'two.gguf': 'TAIL'},
      );
      final h = harness(usableBytes: 1000000, transfer: transfer);
      final job = await h.manager.enqueue(
        model: _model(),
        variant: _variant(split: true),
      );

      final result = await h.manager.run(job);

      expect(result.state, ModelDownloadJobState.completed);
      expect(transfer.requests, hasLength(2));
      expect(h.registry.validated, [job.modelId]);
      expect(
        await File(p.join(sandbox.path, job.modelId, 'two.gguf')).exists(),
        isTrue,
      );
    },
  );

  test('run restarts safely when a server ignores Range', () async {
    final transfer = _Transfer(
      payloads: {'one.gguf': 'GGUF'},
      statusCodes: [HttpStatus.ok, HttpStatus.ok],
    );
    final h = harness(usableBytes: 1000000, transfer: transfer);
    final job = await h.manager.enqueue(model: _model(), variant: _variant());
    final directory = await h.files.modelDirectory(job.modelId);
    final partial = await ModelDownloadStaging(
      directory,
    ).partial(job.id, 'one.gguf');
    await partial.writeAsString('x');

    final result = await h.manager.run(job);

    expect(result.errorCode, isNull);
    expect(result.state, ModelDownloadJobState.completed);
    expect(transfer.requests, hasLength(2));
    expect(transfer.requests.first.existingBytes, 1);
    expect(transfer.requests.last.existingBytes, 0);
  });

  test(
    'existing verified destination is reused without network transfer',
    () async {
      final transfer = _Transfer(payloads: const {});
      final h = harness(usableBytes: 1000000, transfer: transfer);
      final hash = sha256.convert('GGUF'.codeUnits).toString();
      final job = await h.manager.enqueue(
        model: _model(),
        variant: _variant(hash: hash),
      );
      final directory = await h.files.modelDirectory(job.modelId);
      await File(p.join(directory.path, 'one.gguf')).writeAsString('GGUF');

      final result = await h.manager.run(job);

      expect(result.state, ModelDownloadJobState.completed);
      expect(transfer.requests, isEmpty);
    },
  );

  test(
    'unsafe artifact names and validation failures become durable failed jobs',
    () async {
      final h = harness(usableBytes: 1000000);
      final unsafe = await h.manager.enqueue(
        model: _model(),
        variant: const GgufVariant(
          repository: 'owner/model',
          revision: _revision,
          displayName: 'unsafe',
          files: [GgufFile(name: '../escape.gguf', sizeBytes: 4)],
        ),
      );
      final unsafeResult = await h.manager.run(unsafe);
      expect(unsafeResult.state, ModelDownloadJobState.failed);
      expect(unsafeResult.errorCode, 'validation_or_transfer');

      final badTransfer = _Transfer(payloads: {'one.gguf': 'BAD'});
      final broken = harness(usableBytes: 1000000, transfer: badTransfer);
      final job = await broken.manager.enqueue(
        model: _model(),
        variant: _variant(hash: sha256.convert('GGUF'.codeUnits).toString()),
      );
      final failed = await broken.manager.run(job);
      expect(failed.state, ModelDownloadJobState.failed);
      expect(
        (await DatabaseHelper.instance.getModel(
          job.modelId,
        ))?['installation_state'],
        'validation_failed',
      );
    },
  );

  test(
    'pause and cancel preserve or remove only the active job partials',
    () async {
      final pauseTransfer = _Transfer(cancelled: true, cancelReason: 'paused');
      final paused = harness(usableBytes: 1000000, transfer: pauseTransfer);
      final pauseJob = await paused.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      final pauseResult = await paused.manager.run(pauseJob);
      expect(pauseResult.state, ModelDownloadJobState.paused);

      final cancelTransfer = _Transfer(
        cancelled: true,
        cancelReason: 'cancelled',
      );
      final cancelled = harness(usableBytes: 1000000, transfer: cancelTransfer);
      final cancelJob = await cancelled.manager.enqueue(
        model: _model(),
        variant: _variant(),
      );
      final cancelDirectory = await cancelled.files.modelDirectory(
        cancelJob.modelId,
      );
      final partial = await ModelDownloadStaging(
        cancelDirectory,
      ).partial(cancelJob.id, 'one.gguf');
      await partial.writeAsString('partial');
      final cancelResult = await cancelled.manager.run(cancelJob);
      expect(cancelResult.state, ModelDownloadJobState.cancelled);
      expect(await partial.exists(), isFalse);
    },
  );

  test(
    'idle cancellation removes only that job partial and recovery is idempotent',
    () async {
      final jobs = _Jobs();
      final h = harness(usableBytes: 1000000, jobs: jobs);
      final job = await h.manager.enqueue(model: _model(), variant: _variant());
      final directory = await h.files.modelDirectory(job.modelId);
      final partial = await ModelDownloadStaging(
        directory,
      ).partial(job.id, 'one.gguf');
      await partial.writeAsString('partial');

      await h.manager.cancel(job.id);
      final restored = await h.manager.restoreJobs();

      expect(jobs.values.last.state, ModelDownloadJobState.cancelled);
      expect(await partial.exists(), isFalse);
      expect(restored.single.state, ModelDownloadJobState.cancelled);
    },
  );

  test(
    'restore projects native states and pauses interrupted local work',
    () async {
      final jobs = _Jobs()
        ..values.addAll([
          _job('native', ModelDownloadJobState.downloading),
          _job('local', ModelDownloadJobState.validating),
          _job('done', ModelDownloadJobState.completed),
        ]);
      final transfer = _Transfer(
        reconciliations: {
          'native': const TransferReconciliation(
            state: ModelDownloadJobState.downloading,
            downloadedBytes: 3,
          ),
        },
      );
      final h = harness(usableBytes: 1000000, jobs: jobs, transfer: transfer);

      final restored = await h.manager.restoreJobs();

      expect(restored.map((job) => job.state), [
        ModelDownloadJobState.paused,
        ModelDownloadJobState.paused,
        ModelDownloadJobState.completed,
      ]);
      expect(restored.first.downloadedBytes, 3);
    },
  );
}

const _revision = '0123456789012345678901234567890123456789';

HubModelSummary _model({bool gated = false}) => HubModelSummary(
  id: 'owner/model',
  revision: _revision,
  tags: const ['gguf'],
  downloads: 1,
  gated: gated,
  parameterCount: 800000000,
);

GgufVariant _variant({bool split = false, String? hash}) => GgufVariant(
  repository: 'owner/model',
  revision: _revision,
  displayName: 'Q4',
  quantization: 'Q4_K_M',
  files: split
      ? const [
          GgufFile(
            name: 'one.gguf',
            sizeBytes: 4,
            shardIndex: 0,
            shardCount: 2,
          ),
          GgufFile(
            name: 'two.gguf',
            sizeBytes: 4,
            shardIndex: 1,
            shardCount: 2,
          ),
        ]
      : [GgufFile(name: 'one.gguf', sizeBytes: 4, sha256: hash)],
);

ModelDownloadJob _job(String id, ModelDownloadJobState state) =>
    ModelDownloadJob(
      id: id,
      modelId: 'model-$id',
      repository: 'owner/model',
      revision: _revision,
      state: state,
      downloadedBytes: 0,
      totalBytes: 4,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

final class _Harness {
  _Harness({
    required Directory root,
    int? usableBytes,
    _Transfer? transfer,
    _Jobs? jobs,
  }) : files = _Files(root, usableBytes),
       transfer = transfer ?? _Transfer(payloads: const {}),
       jobs = jobs ?? _Jobs(),
       registry = _Registry() {
    manager = ModelDownloadManager(
      jobs: this.jobs,
      files: files,
      transfers: this.transfer,
      database: DatabaseHelper.instance,
      registry: registry,
      clock: () => DateTime.utc(2026, 1, 1),
    );
  }

  final _Files files;
  final _Transfer transfer;
  final _Jobs jobs;
  final _Registry registry;
  late final ModelDownloadManager manager;
}

final class _Files implements ModelFileStore {
  const _Files(this.root, this.usable);
  final Directory root;
  final int? usable;
  @override
  Future<Directory> modelDirectory(String modelId) async {
    final directory = Directory(p.join(root.path, modelId));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<int?> usableBytes() async => usable;
}

final class _Jobs implements DownloadJobStore {
  final List<ModelDownloadJob> values = [];
  @override
  Future<List<ModelDownloadJob>> list() async => List.unmodifiable(values);
  @override
  Future<void> write(ModelDownloadJob job) async {
    final index = values.indexWhere((value) => value.id == job.id);
    if (index < 0) {
      values.add(job);
    } else {
      values[index] = job;
    }
  }
}

final class _PauseWriteJobs extends _Jobs {
  final pausedWriteEntered = Completer<void>();
  final releasePausedWrite = Completer<void>();

  @override
  Future<void> write(ModelDownloadJob job) async {
    if (job.state == ModelDownloadJobState.paused &&
        !pausedWriteEntered.isCompleted) {
      pausedWriteEntered.complete();
      await releasePausedWrite.future;
    }
    await super.write(job);
  }
}

final class _RejectWriteJobs extends _Jobs {
  @override
  Future<void> write(ModelDownloadJob job) async =>
      throw StateError('fixture persistence failure');
}

final class _Transfer implements PlatformTransferAdapter {
  _Transfer({
    Map<String, Object> payloads = const {},
    List<int> statusCodes = const [HttpStatus.ok],
    this.cancelled = false,
    this.pauseAfterWrite = false,
    this.cancelReason = 'cancelled',
    this.reconciliations = const {},
    this.barrier,
  }) : _payloads = payloads,
       _statusCodes = statusCodes;
  final Map<String, Object> _payloads;
  final List<int> _statusCodes;
  final bool cancelled;
  final bool pauseAfterWrite;
  final String cancelReason;
  final Map<String, TransferReconciliation> reconciliations;
  final Future<void>? barrier;
  final Completer<void> started = Completer<void>();
  final List<_Request> requests = [];

  @override
  Future<TransferResult> transfer({
    required String transferId,
    required String jobId,
    required String modelId,
    required String repository,
    required String revision,
    required Uri source,
    required File partial,
    required int existingBytes,
    required int expectedBytes,
    required String? expectedSha256,
    int artifactIndex = 0,
    int shardCount = 1,
    required void Function(int received, int? total) onProgress,
    required CancelToken cancellation,
  }) async {
    requests.add(_Request(source, existingBytes));
    if (!started.isCompleted) started.complete();
    if (barrier != null) await barrier;
    if (cancellation.isCancelled) throw cancellation.cancelError!;
    if (cancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: source.toString()),
        reason: cancelReason,
      );
    }
    final name = source.pathSegments.last;
    final raw = _payloads[name];
    final bytes = raw is String
        ? raw.codeUnits
        : raw as List<int>? ?? const <int>[];
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(bytes, flush: true);
    if (pauseAfterWrite) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: source.toString()),
        reason: 'paused',
      );
    }
    onProgress(bytes.length, expectedBytes);
    final status =
        _statusCodes[(requests.length - 1).clamp(0, _statusCodes.length - 1)];
    return TransferResult(statusCode: status);
  }

  @override
  Future<TransferReconciliation?> reconcile(String jobId) async =>
      reconciliations[jobId];
}

final class _Request {
  const _Request(this.source, this.existingBytes);
  final Uri source;
  final int existingBytes;
}

final class _Registry implements ModelRegistryService {
  final List<String> validated = [];
  @override
  Future<ModelDescriptor> validateDownloadedModel({
    required String modelId,
    required String primaryPath,
    ModelVerificationPhaseSink? onPhase,
  }) async {
    validated.add(modelId);
    return ModelDescriptor(
      id: modelId,
      displayName: modelId,
      source: 'fixture',
      compatibilityStatus: 'compatible',
      localPath: primaryPath,
      sha256: 'fixture',
      installationState: 'installed',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
