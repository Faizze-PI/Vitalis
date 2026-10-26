import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/model_download_job.dart';
import 'package:vitalis_app/services/model_download_manager.dart';
import 'package:vitalis_app/services/native_transfer_stop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vitalis/model_transfers');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final stalledMethod in ['enqueue', 'status']) {
    for (final reason in ['cancelled', 'paused']) {
      test(
        'active $reason interrupts stalled $stalledMethod without late progress',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final stopIssued = Completer<void>();
          var stalled = false;
          final progress = <int>[];
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
                if (call.method == stalledMethod && !stalled) {
                  stalled = true;
                  entered.complete();
                  await release.future;
                  return {'state': 'running', 'downloadedBytes': 123};
                }
                if (call.method == 'enqueue') return {'state': 'queued'};
                if (call.method ==
                    (reason == 'cancelled' ? 'cancel' : 'pause')) {
                  stopIssued.complete();
                  return null;
                }
                if (call.method == 'status')
                  return {
                    'jobId': 'job-a',
                    'transferId': 'transfer-a',
                    'state': reason,
                    'downloadedBytes': 2,
                    'stopAcknowledged': true,
                  };
                throw StateError('Unexpected control method');
              });
          final token = CancelToken();
          final operation =
              const AndroidDurableTransferAdapter(
                    channel: channel,
                    pollInterval: Duration.zero,
                  )
                  .transfer(
                    transferId: 'transfer-a',
                    jobId: 'job-a',
                    modelId: 'model-a',
                    repository: 'publisher/model',
                    revision: '0123456789012345678901234567890123456789',
                    source: Uri.parse(
                      'https://huggingface.co/publisher/model/resolve/0123456789012345678901234567890123456789/model.gguf',
                    ),
                    partial: File('model.gguf.part'),
                    existingBytes: 0,
                    expectedBytes: 1024,
                    expectedSha256: null,
                    onProgress: (bytes, _) => progress.add(bytes),
                    cancellation: token,
                  )
                  .then<Object?>(
                    (value) => value,
                    onError: (Object error) => error,
                  );
          await entered.future;
          token.cancel(reason);
          bool interrupted;
          try {
            interrupted = await Future.any([
              stopIssued.future.then((_) => true),
              Future<bool>(() => false),
            ]);
          } finally {
            release.complete();
          }
          final outcome = await operation;
          expect(
            interrupted,
            isTrue,
            reason: 'stop cannot depend on the stalled request returning',
          );
          expect(
            outcome,
            isA<DioException>().having(
              (error) => error.error,
              'acknowledged reason',
              reason,
            ),
          );
          expect(
            progress,
            isEmpty,
            reason: 'late status must not publish cancelled progress',
          );
        },
      );
    }
  }

  test(
    'acknowledgement at the elapsed deadline cannot report success',
    () async {
      var elapsed = Duration.zero;
      final timers = <_ControlledTimer>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'list')
              return [
                {'jobId': 'job-a', 'transferId': 'owned'},
              ];
            if (call.method == 'cancel') return null;
            elapsed = const Duration(seconds: 5);
            return {
              'jobId': 'job-a',
              'transferId': 'owned',
              'state': 'cancelled',
              'stopAcknowledged': true,
            };
          });
      final adapter = AndroidDurableTransferAdapter(
        channel: channel,
        stopAcknowledgementTimeout: const Duration(seconds: 5),
        monotonicNow: () => elapsed,
        stopTimerFactory: (duration, callback) {
          final timer = _ControlledTimer(duration, callback);
          timers.add(timer);
          return timer;
        },
      );
      await expectLater(
        adapter.cancelJob('job-a'),
        throwsA(
          isA<NativeTransferStopUnconfirmed>().having(
            (error) => error.reason,
            'deadline reason',
            NativeStopFailure.deadline,
          ),
        ),
      );
      expect(timers.every((timer) => !timer.isActive), isTrue);
    },
  );

  test(
    'active stop deadline rejects a stalled acknowledgement and late output',
    () async {
      final ordinaryStatus = Completer<void>();
      final acknowledgement = Completer<void>();
      final statusEntered = Completer<void>();
      final stopStatusEntered = Completer<void>();
      final timers = <_ControlledTimer>[];
      var stopped = false;
      final progress = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'enqueue') return {'state': 'queued'};
            if (call.method == 'cancel') {
              stopped = true;
              return null;
            }
            if (!stopped) {
              statusEntered.complete();
              await ordinaryStatus.future;
            } else {
              stopStatusEntered.complete();
              await acknowledgement.future;
            }
            return {
              'jobId': 'job-a',
              'transferId': 'transfer-a',
              'state': 'cancelled',
              'stopAcknowledged': true,
              'downloadedBytes': 2,
            };
          });
      final token = CancelToken();
      final operation =
          AndroidDurableTransferAdapter(
                channel: channel,
                stopTimerFactory: (duration, callback) {
                  final timer = _ControlledTimer(duration, callback);
                  timers.add(timer);
                  return timer;
                },
              )
              .transfer(
                transferId: 'transfer-a',
                jobId: 'job-a',
                modelId: 'model-a',
                repository: 'publisher/model',
                revision: '0123456789012345678901234567890123456789',
                source: Uri.parse(
                  'https://huggingface.co/publisher/model/resolve/0123456789012345678901234567890123456789/model.gguf',
                ),
                partial: File('model.gguf.part'),
                existingBytes: 0,
                expectedBytes: 1024,
                expectedSha256: null,
                onProgress: (bytes, _) => progress.add(bytes),
                cancellation: token,
              )
              .then<Object?>(
                (value) => value,
                onError: (Object error) => error,
              );
      await statusEntered.future;
      token.cancel('cancelled');
      await stopStatusEntered.future;
      try {
        timers.single.fire();
        expect(
          await operation,
          isA<NativeTransferStopUnconfirmed>().having(
            (error) => error.reason,
            'reason',
            NativeStopFailure.deadline,
          ),
        );
        expect(timers.every((timer) => !timer.isActive), isTrue);
      } finally {
        ordinaryStatus.complete();
        acknowledgement.complete();
        await operation;
      }
      expect(progress, isEmpty);
    },
  );

  test('stop expiry cancels the outstanding polling timer', () async {
    final timers = <_ControlledTimer>[];
    final pollCreated = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'list')
            return [
              {'jobId': 'job-a', 'transferId': 'owned'},
            ];
          if (call.method == 'cancel') return null;
          return {
            'jobId': 'job-a',
            'transferId': 'owned',
            'state': 'cancelled',
            'stopAcknowledged': false,
          };
        });
    Object? failure;
    final operation = runZoned(
      () =>
          const AndroidDurableTransferAdapter(
                channel: channel,
                pollInterval: Duration(milliseconds: 10),
              )
              .cancelJob('job-a')
              .then<void>(
                (_) {},
                onError: (Object error) {
                  failure = error;
                },
              ),
      zoneSpecification: ZoneSpecification(
        createTimer: (_, _, _, duration, callback) {
          final timer = _ControlledTimer(duration, callback);
          timers.add(timer);
          if (duration == const Duration(milliseconds: 10))
            pollCreated.complete();
          return timer;
        },
      ),
    );
    try {
      expect(
        await Future.any([
          pollCreated.future.then((_) => true),
          operation.then((_) => false),
        ]),
        isTrue,
      );
      timers.first.fire();
      await operation;
      expect(failure, isA<NativeTransferStopUnconfirmed>());
      expect(timers.where((timer) => timer.isActive), isEmpty);
    } finally {
      for (final timer in timers) {
        timer.cancel();
      }
    }
  });

  for (final stalledMethod in ['list', 'cancel', 'status']) {
    test(
      'stop deadline covers stalled native $stalledMethod and rejects late success',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final timers = <_ControlledTimer>[];
        final calls = <String>[];
        final acknowledgement = {
          'jobId': 'job-a',
          'transferId': 'owned',
          'state': 'cancelled',
          'stopAcknowledged': true,
        };
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call.method);
              if (call.method == stalledMethod) {
                entered.complete();
                await release.future;
              }
              if (call.method == 'list') return [acknowledgement];
              if (call.method == 'cancel') return null;
              return acknowledgement;
            });
        Object? failure;
        final operation = runZoned(
          () => const AndroidDurableTransferAdapter(channel: channel)
              .cancelJob('job-a')
              .then<void>(
                (_) {},
                onError: (Object error) {
                  failure = error;
                },
              ),
          zoneSpecification: ZoneSpecification(
            createTimer: (_, _, _, duration, callback) {
              final timer = _ControlledTimer(duration, callback);
              timers.add(timer);
              return timer;
            },
          ),
        );
        await entered.future;
        try {
          expect(
            timers.where((timer) => timer.isActive),
            isNotEmpty,
            reason: 'every native control await needs a bounded deadline',
          );
          timers.firstWhere((timer) => timer.isActive).fire();
          await operation;
          expect(
            failure,
            isA<StateError>().having(
              (error) => error.message,
              'typed stop outcome',
              'nativeTransferStopUnconfirmed',
            ),
          );
          final countAtExpiry = calls.length;
          release.complete();
          // Drain the completed channel response; no next native action may run.
          for (var index = 0; index < 8; index++) {
            await Future<void>.value();
          }
          expect(calls, hasLength(countAtExpiry));
        } finally {
          if (!release.isCompleted) release.complete();
          for (final timer in timers) {
            timer.cancel();
          }
          await operation;
        }
      },
    );
  }

  test('terminal native failure ends stop wait without another poll', () async {
    var polls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'list')
            return [
              {'jobId': 'job-a', 'transferId': 'owned'},
            ];
          if (call.method == 'cancel') return null;
          if (++polls > 1) throw PlatformException(code: 'unexpected_repoll');
          return {
            'jobId': 'job-a',
            'transferId': 'owned',
            'state': 'failed',
            'stopAcknowledged': false,
            'failureCode': 'hash_mismatch',
          };
        });
    await expectLater(
      const AndroidDurableTransferAdapter(
        channel: channel,
        pollInterval: Duration.zero,
      ).cancelJob('job-a'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'typed stop outcome',
          'nativeTransferStopUnconfirmed',
        ),
      ),
    );
    expect(polls, 1);
  });

  test(
    'malformed inventory cannot stand for absence of native writers',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => ['malformed manifest'],
          );
      await expectLater(
        const AndroidDurableTransferAdapter(
          channel: channel,
        ).cancelJob('job-a'),
        throwsStateError,
      );
    },
  );

  test(
    'restart control stops every owned shard before polling acknowledgements',
    () async {
      final calls = <String>[];
      var firstPolls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final identity = (call.arguments as Map?)?['transferId'];
            calls.add('${call.method}:${identity ?? ''}');
            if (call.method == 'list')
              return [
                {'jobId': 'job-a', 'transferId': 'first', 'state': 'queued'},
                {'jobId': 'job-b', 'transferId': 'foreign', 'state': 'running'},
                {'jobId': 'job-a', 'transferId': 'second', 'state': 'running'},
              ];
            if (call.method == 'cancel') return null;
            if (identity == 'first') firstPolls++;
            return {
              'jobId': 'job-a',
              'transferId': identity,
              'state': 'cancelled',
              'stopAcknowledged': identity != 'first' || firstPolls > 1,
            };
          });
      await const AndroidDurableTransferAdapter(
        channel: channel,
        pollInterval: Duration.zero,
      ).cancelJob('job-a');
      expect(calls, [
        'list:',
        'cancel:first',
        'cancel:second',
        'status:first',
        'status:first',
        'status:second',
      ]);
    },
  );

  for (final wrong in [
    null,
    {
      'jobId': 'foreign',
      'transferId': 'owned',
      'state': 'cancelled',
      'stopAcknowledged': true,
    },
  ]) {
    test(
      'restart control rejects an absent or foreign acknowledgement: $wrong',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'list')
                return [
                  {'jobId': 'job-a', 'transferId': 'owned'},
                ];
              if (call.method == 'cancel') return null;
              return wrong;
            });
        await expectLater(
          const AndroidDurableTransferAdapter(
            channel: channel,
          ).cancelJob('job-a'),
          throwsStateError,
        );
      },
    );
  }

  test(
    'restart control rejects duplicate native identities before sending stop',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return [
              {'jobId': 'job-a', 'transferId': 'duplicate'},
              {'jobId': 'job-a', 'transferId': 'duplicate'},
            ];
          });
      await expectLater(
        const AndroidDurableTransferAdapter(
          channel: channel,
        ).cancelJob('job-a'),
        throwsStateError,
      );
      expect(calls, ['list']);
    },
  );

  test('enqueues immutable transfer and reports native completion', () async {
    final expectedHash = List.filled(64, 'a').join();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'enqueue')
            return <String, Object?>{'state': 'queued'};
          if (call.method == 'status') {
            return <String, Object?>{
              'state': 'downloaded',
              'downloadedBytes': 1024,
            };
          }
          return null;
        });
    const adapter = AndroidDurableTransferAdapter(
      channel: channel,
      pollInterval: Duration.zero,
    );
    var progress = 0;
    final result = await adapter.transfer(
      transferId: 'transfer-a',
      jobId: 'job-a',
      modelId: 'model-a',
      repository: 'publisher/model',
      revision: '0123456789012345678901234567890123456789',
      source: Uri.parse(
        'https://huggingface.co/publisher/model/resolve/'
        '0123456789012345678901234567890123456789/model.gguf',
      ),
      partial: File('model.gguf.part'),
      existingBytes: 0,
      expectedBytes: 1024,
      expectedSha256: expectedHash,
      onProgress: (received, _) => progress = received,
      cancellation: CancelToken(),
    );

    expect(result.statusCode, HttpStatus.ok);
    expect(progress, 1024);
    expect(calls.map((call) => call.method), ['enqueue', 'status']);
    final request = calls.first.arguments! as Map<Object?, Object?>;
    expect(request['jobId'], 'job-a');
    expect(request['expectedSha256'], expectedHash);
    expect(request['sourceUrl'], isNot(contains('?')));
    expect(request['finalPath'], 'model.gguf');
    expect(request['artifactIndex'], 0);
    expect(request['shardCount'], 1);
  });

  test('projects paused native state as acknowledged cancellation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enqueue')
            return <String, Object?>{'state': 'queued'};
          return <String, Object?>{
            'state': 'paused',
            'downloadedBytes': 10,
            'stopAcknowledged': true,
          };
        });
    const adapter = AndroidDurableTransferAdapter(
      channel: channel,
      pollInterval: Duration.zero,
    );

    expect(
      () => adapter.transfer(
        transferId: 'transfer-a',
        jobId: 'job-a',
        modelId: 'model-a',
        repository: 'publisher/model',
        revision: '0123456789012345678901234567890123456789',
        source: Uri.parse(
          'https://huggingface.co/publisher/model/resolve/'
          '0123456789012345678901234567890123456789/model.gguf',
        ),
        partial: File('model.gguf.part'),
        existingBytes: 10,
        expectedBytes: 1024,
        expectedSha256: null,
        onProgress: (_, _) {},
        cancellation: CancelToken(),
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('preserves notification cancellation as a cancelled reason', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enqueue') {
            return <String, Object?>{'state': 'queued'};
          }
          return <String, Object?>{
            'state': 'cancelled',
            'downloadedBytes': 0,
            'stopAcknowledged': true,
          };
        });
    const adapter = AndroidDurableTransferAdapter(
      channel: channel,
      pollInterval: Duration.zero,
    );

    await expectLater(
      adapter.transfer(
        transferId: 'transfer-a',
        jobId: 'job-a',
        modelId: 'model-a',
        repository: 'publisher/model',
        revision: '0123456789012345678901234567890123456789',
        source: Uri.parse(
          'https://huggingface.co/publisher/model/resolve/'
          '0123456789012345678901234567890123456789/model.gguf',
        ),
        partial: File('model.gguf.part'),
        existingBytes: 0,
        expectedBytes: 1024,
        expectedSha256: null,
        onProgress: (_, _) {},
        cancellation: CancelToken(),
      ),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'native cancellation reason',
          'cancelled',
        ),
      ),
    );
  });

  test(
    'waits for native acknowledgement after requesting cancellation',
    () async {
      final cancellation = CancelToken()..cancel('cancelled');
      var statusCalls = 0;
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'enqueue') {
              return <String, Object?>{'state': 'queued'};
            }
            if (call.method == 'cancel') return null;
            statusCalls++;
            return <String, Object?>{
              'jobId': 'job-a',
              'transferId': 'transfer-a',
              'state': 'cancelled',
              'downloadedBytes': statusCalls == 1 ? 20 : 0,
              'stopAcknowledged': statusCalls > 1,
            };
          });
      const adapter = AndroidDurableTransferAdapter(
        channel: channel,
        pollInterval: Duration.zero,
      );

      await expectLater(
        adapter.transfer(
          transferId: 'transfer-a',
          jobId: 'job-a',
          modelId: 'model-a',
          repository: 'publisher/model',
          revision: '0123456789012345678901234567890123456789',
          source: Uri.parse(
            'https://huggingface.co/publisher/model/resolve/'
            '0123456789012345678901234567890123456789/model.gguf',
          ),
          partial: File('model.gguf.part'),
          existingBytes: 20,
          expectedBytes: 1024,
          expectedSha256: null,
          onProgress: (_, _) {},
          cancellation: cancellation,
        ),
        throwsA(isA<DioException>()),
      );

      expect(statusCalls, 2);
      expect(methods.where((method) => method == 'cancel'), hasLength(1));
    },
  );

  test('reconciles process-independent manifest progress by job', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <Object?>[
            <String, Object?>{
              'jobId': 'job-a',
              'state': 'downloaded',
              'downloadedBytes': 700,
            },
            <String, Object?>{
              'jobId': 'job-a',
              'state': 'paused',
              'downloadedBytes': 300,
              'stopReason': 'user_paused',
            },
            <String, Object?>{
              'jobId': 'job-b',
              'state': 'failed',
              'downloadedBytes': 5,
            },
          ],
        );
    const adapter = AndroidDurableTransferAdapter(channel: channel);

    final result = await adapter.reconcile('job-a');

    expect(result, isNotNull);
    expect(result!.state, ModelDownloadJobState.paused);
    expect(result.downloadedBytes, 1000);
    expect(result.stopReason, 'user_paused');
  });

  test('projects a complete downloaded shard set into validation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <Object?>[
            <String, Object?>{
              'jobId': 'job-a',
              'state': 'downloaded',
              'downloadedBytes': 600,
            },
            <String, Object?>{
              'jobId': 'job-a',
              'state': 'downloaded',
              'downloadedBytes': 400,
            },
          ],
        );
    const adapter = AndroidDurableTransferAdapter(channel: channel);

    final result = await adapter.reconcile('job-a');

    expect(result, isNotNull);
    expect(result!.state, ModelDownloadJobState.validating);
    expect(result.downloadedBytes, 1000);
  });

  test('fails safely when the native manifest is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enqueue')
            return <String, Object?>{'state': 'queued'};
          return null;
        });
    const adapter = AndroidDurableTransferAdapter(
      channel: channel,
      pollInterval: Duration.zero,
    );

    await expectLater(
      adapter.transfer(
        transferId: 'missing',
        jobId: 'job-a',
        modelId: 'model-a',
        repository: 'publisher/model',
        revision: '0123456789012345678901234567890123456789',
        source: Uri.parse(
          'https://huggingface.co/publisher/model/resolve/'
          '0123456789012345678901234567890123456789/model.gguf',
        ),
        partial: File('model.gguf.part'),
        existingBytes: 0,
        expectedBytes: 1,
        expectedSha256: null,
        onProgress: (_, _) {},
        cancellation: CancelToken(),
      ),
      throwsStateError,
    );
  });

  test('projects a native failure with its diagnostic code', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enqueue')
            return <String, Object?>{'state': 'queued'};
          return <String, Object?>{
            'state': 'failed',
            'failureCode': 'hash_mismatch',
          };
        });
    const adapter = AndroidDurableTransferAdapter(
      channel: channel,
      pollInterval: Duration.zero,
    );

    await expectLater(
      adapter.transfer(
        transferId: 'failed',
        jobId: 'job-a',
        modelId: 'model-a',
        repository: 'publisher/model',
        revision: '0123456789012345678901234567890123456789',
        source: Uri.parse(
          'https://huggingface.co/publisher/model/resolve/'
          '0123456789012345678901234567890123456789/model.gguf',
        ),
        partial: File('model.gguf.part'),
        existingBytes: 0,
        expectedBytes: 1,
        expectedSha256: null,
        onProgress: (_, _) {},
        cancellation: CancelToken(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('hash_mismatch'),
        ),
      ),
    );
  });
}

final class _ControlledTimer implements Timer {
  _ControlledTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() {
    _active = false;
  }
}
