import 'dart:async';
import 'dart:io';

import '../test/support/stress_workload.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final owner = StressWorkload();
  final gate = Completer<void>();
  final running = owner.run(() => gate.future);
  var cleanupFinished = false;
  final cleanup = owner.settle().then((error) {
    check(error == null, 'Successful workload reported failure');
    cleanupFinished = true;
  });
  try {
    await Future<void>.delayed(Duration.zero);
    check(!cleanupFinished, 'Cleanup overtook active database work');
    var rejected = false;
    try {
      owner.run(() async {});
    } on StateError {
      rejected = true;
    }
    check(rejected, 'Competing workload replaced its owner');
  } finally {
    gate.complete();
    await running;
    await cleanup;
  }
  check(cleanupFinished, 'Cleanup failed to acknowledge completion');
  await owner.run(() async {});
  check(await owner.settle() == null, 'Sequential workload failed');

  final failure = StateError('fixture failure');
  final failed = owner.run(() async => throw failure);
  final observed = failed.then<Object?>((_) => null, onError: (Object e) => e);
  check(
    identical(await owner.settle(), failure),
    'Failure was lost during drain',
  );
  check(identical(await observed, failure), 'Original test lost its failure');
  check(
    await owner.settle() == null,
    'Settled workload retained stale ownership',
  );
  stdout.writeln(
    'Stress workload: cleanup waits, contention rejects, failure retained.',
  );
}
