import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/native_transfer_stop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vitalis/stop_policy_tests');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'recovery completion after the shared deadline cannot finish Stop',
    () async {
      var elapsed = Duration.zero;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        if (call.method == 'list')
          return [
            {'jobId': 'job', 'transferId': 'owned'},
          ];
        if (call.method == 'cancel') return null;
        if (call.method == 'recoverStop') elapsed = const Duration(seconds: 4);
        return {
          'jobId': 'job',
          'transferId': 'owned',
          'state': 'cancelled',
          'stopAcknowledged': call.method == 'recoverStop',
          'recoveryRequired': true,
        };
      });
      await expectLater(
        NativeTransferStopController(
          channel: channel,
          timeout: const Duration(seconds: 3),
          monotonicNow: () => elapsed,
        ).cancelJob('job'),
        throwsA(
          isA<NativeTransferStopUnconfirmed>().having(
            (error) => error.reason,
            'shared recovery deadline',
            NativeStopFailure.deadline,
          ),
        ),
      );
      expect(methods, ['list', 'cancel', 'status', 'recoverStop']);
    },
  );

  for (final invalid in [
    (
      job: 'foreign',
      transfer: 'owned',
      state: 'cancelled',
      ack: true,
      reason: NativeStopFailure.identity,
    ),
    (
      job: 'job',
      transfer: 'foreign',
      state: 'cancelled',
      ack: true,
      reason: NativeStopFailure.identity,
    ),
    (
      job: 'job',
      transfer: 'owned',
      state: 'cancelled',
      ack: false,
      reason: NativeStopFailure.pending,
    ),
    (
      job: 'job',
      transfer: 'owned',
      state: 'paused',
      ack: true,
      reason: NativeStopFailure.pending,
    ),
  ]) {
    test(
      'recovery rejects unconfirmed or foreign response: $invalid',
      () async {
        var recoveryCalls = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'list')
            return [
              {'jobId': 'job', 'transferId': 'owned'},
            ];
          if (call.method == 'cancel') return null;
          if (call.method == 'recoverStop') {
            recoveryCalls++;
            return {
              'jobId': invalid.job,
              'transferId': invalid.transfer,
              'state': invalid.state,
              'stopAcknowledged': invalid.ack,
            };
          }
          return {
            'jobId': 'job',
            'transferId': 'owned',
            'state': 'cancelled',
            'stopAcknowledged': false,
            'recoveryRequired': true,
          };
        });
        await expectLater(
          const NativeTransferStopController(channel: channel).cancelJob('job'),
          throwsA(
            isA<NativeTransferStopUnconfirmed>().having(
              (error) => error.reason,
              'recovery rejection',
              invalid.reason,
            ),
          ),
        );
        expect(recoveryCalls, 1);
      },
    );
  }

  test(
    'explicit cancellation recovers advertised quarantine before completion',
    () async {
      final methods = <String>[];
      var recovered = false;
      var elapsed = Duration.zero;
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        if (call.method == 'list') {
          return [
            {'jobId': 'job', 'transferId': 'owned'},
          ];
        }
        if (call.method == 'cancel') return null;
        if (call.method == 'status') elapsed += const Duration(seconds: 2);
        if (call.method == 'recoverStop') {
          expect(call.arguments, {'jobId': 'job', 'transferId': 'owned'});
          recovered = true;
        }
        return {
          'jobId': 'job',
          'transferId': 'owned',
          'state': 'cancelled',
          'stopAcknowledged': recovered,
          'recoveryRequired': !recovered,
        };
      });
      await NativeTransferStopController(
        channel: channel,
        timeout: const Duration(seconds: 5),
        pollInterval: Duration.zero,
        monotonicNow: () => elapsed,
      ).cancelJob('job');
      expect(methods, ['list', 'cancel', 'status', 'recoverStop', 'status']);
    },
  );

  test(
    'one elapsed budget spans inventory, stop command and acknowledgement',
    () async {
      var elapsed = Duration.zero;
      var timers = 0;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        elapsed += const Duration(seconds: 2);
        if (call.method == 'list')
          return [
            {'jobId': 'job', 'transferId': 'owned'},
          ];
        if (call.method == 'cancel') return null;
        return {
          'jobId': 'job',
          'transferId': 'owned',
          'state': 'cancelled',
          'stopAcknowledged': true,
        };
      });
      final controller = NativeTransferStopController(
        channel: channel,
        timeout: const Duration(seconds: 5),
        monotonicNow: () => elapsed,
        timerFactory: (duration, callback) {
          timers++;
          return Timer(duration, callback);
        },
      );
      await expectLater(
        controller.cancelJob('job'),
        throwsA(
          isA<NativeTransferStopUnconfirmed>().having(
            (error) => error.reason,
            'shared deadline',
            NativeStopFailure.deadline,
          ),
        ),
      );
      expect(methods, ['list', 'cancel', 'status']);
      expect(timers, 1);
    },
  );

  test('elapsed budget prevents even the first native action', () async {
    var reads = 0;
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return [];
    });
    final controller = NativeTransferStopController(
      channel: channel,
      timeout: const Duration(seconds: 1),
      monotonicNow: () =>
          reads++ == 0 ? Duration.zero : const Duration(seconds: 1),
    );
    await expectLater(
      controller.cancelJob('job'),
      throwsA(
        isA<NativeTransferStopUnconfirmed>().having(
          (error) => error.reason,
          'deadline reason',
          NativeStopFailure.deadline,
        ),
      ),
    );
    expect(calls, 0);
  });

  for (final policy in [
    (timeout: Duration.zero, poll: Duration.zero),
    (
      timeout: const Duration(seconds: 1),
      poll: const Duration(milliseconds: -1),
    ),
  ]) {
    test('invalid waiting policy starts no native work: $policy', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return [];
      });
      await expectLater(
        NativeTransferStopController(
          channel: channel,
          timeout: policy.timeout,
          pollInterval: policy.poll,
        ).cancelJob('job'),
        throwsArgumentError,
      );
      expect(calls, 0);
    });
  }

  for (final inventory in [
    null,
    [
      {'transferId': 'missing-job'},
    ],
  ]) {
    test('unidentified inventory fails closed: $inventory', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => inventory);
      await expectLater(
        const NativeTransferStopController(channel: channel).cancelJob('job'),
        throwsA(
          isA<NativeTransferStopUnconfirmed>().having(
            (error) => error.reason,
            'inventory reason',
            NativeStopFailure.inventory,
          ),
        ),
      );
    });
  }

  test('missing transfer identity fails before any stop command', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return [
        {'jobId': 'job'},
      ];
    });
    await expectLater(
      const NativeTransferStopController(channel: channel).cancelJob('job'),
      throwsA(
        isA<NativeTransferStopUnconfirmed>().having(
          (error) => error.reason,
          'identity reason',
          NativeStopFailure.identity,
        ),
      ),
    );
    expect(methods, ['list']);
  });

  test(
    'no matching native job finishes without cancelling a foreign job',
    () async {
      final methods = <String>[];
      Timer? deadline;
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return [
          {'jobId': 'other', 'transferId': 'foreign'},
        ];
      });
      await NativeTransferStopController(
        channel: channel,
        timerFactory: (duration, callback) =>
            deadline = Timer(duration, callback),
      ).cancelJob('job');
      expect(methods, ['list']);
      expect(deadline!.isActive, isFalse);
    },
  );

  test(
    'late native error is observed without reopening an expired operation',
    () async {
      final entered = Completer<void>();
      final response = Completer<void>();
      Timer? deadline;
      late void Function() expire;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        entered.complete();
        await response.future;
        return [];
      });
      final operation = NativeTransferStopController(
        channel: channel,
        timerFactory: (duration, callback) {
          expire = callback;
          return deadline = Timer(duration, callback);
        },
      ).cancelJob('job');
      final expected = expectLater(
        operation,
        throwsA(isA<NativeTransferStopUnconfirmed>()),
      );
      try {
        await entered.future;
        expire();
        await expected;
        response.completeError(PlatformException(code: 'late-native-error'));
        for (var index = 0; index < 8; index++) {
          await Future<void>.value();
        }
        expect(methods, ['list']);
        expect(deadline!.isActive, isFalse);
      } finally {
        if (!response.isCompleted) response.complete();
        deadline?.cancel();
      }
    },
  );

  test(
    'error arriving at the elapsed limit remains a deadline failure',
    () async {
      var elapsed = Duration.zero;
      messenger.setMockMethodCallHandler(channel, (_) async {
        elapsed = const Duration(seconds: 5);
        throw PlatformException(code: 'late-native-error');
      });
      await expectLater(
        NativeTransferStopController(
          channel: channel,
          timeout: const Duration(seconds: 5),
          monotonicNow: () => elapsed,
        ).cancelJob('job'),
        throwsA(
          isA<NativeTransferStopUnconfirmed>().having(
            (error) => error.reason,
            'deadline reason',
            NativeStopFailure.deadline,
          ),
        ),
      );
    },
  );
}
