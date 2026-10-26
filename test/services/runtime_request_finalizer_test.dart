import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/runtime_request_finalizer.dart';

void main() {
  test('unstarted retry and duplicate registration are rejected', () {
    final finalizer = RuntimeRequestFinalizer(publish: (_) {});
    expect(finalizer.retry, throwsStateError);
    finalizer.add(RuntimeCleanupStep.cache, () {});
    expect(
      () => finalizer.add(RuntimeCleanupStep.cache, () {}),
      throwsStateError,
    );
    finalizer.finish(Object());
    expect(
      () => finalizer.add(RuntimeCleanupStep.sampler, () {}),
      throwsStateError,
    );
    expect(finalizer.pendingStepCount, 0);
  });

  test('publication failure retries without repeating released resources', () {
    var reject = true;
    var released = 0;
    final published = <Object>[];
    final original = Object();
    final finalizer = RuntimeRequestFinalizer(
      publish: (terminal) {
        if (reject) throw StateError('injected publication failure');
        published.add(terminal);
      },
    );
    finalizer.add(RuntimeCleanupStep.cancellation, () => released++);
    expect(finalizer.finish(original), RuntimeCleanupOutcome.recoveryRequired);
    expect(finalizer.pendingStepCount, 0);
    expect(finalizer.isConfirmed, isFalse);
    reject = false;
    expect(finalizer.retry(), RuntimeCleanupOutcome.confirmed);
    expect(finalizer.isConfirmed, isTrue);
    expect(released, 1);
    expect(published.single, same(original));
  });

  test('reentrant cleanup cannot publish or release resources twice', () {
    var released = 0;
    var published = 0;
    late RuntimeRequestFinalizer finalizer;
    finalizer = RuntimeRequestFinalizer(publish: (_) => published++);
    finalizer.add(RuntimeCleanupStep.cache, () {
      expect(finalizer.retry(), RuntimeCleanupOutcome.recoveryRequired);
      released++;
    });
    expect(finalizer.finish(Object()), RuntimeCleanupOutcome.confirmed);
    expect(released, 1);
    expect(published, 1);
  });

  for (final failingStep in RuntimeCleanupStep.values) {
    test('retains failed ${failingStep.name} and later steps for recovery', () {
      var blocked = true;
      final released = <RuntimeCleanupStep>[];
      final published = <Object>[];
      final finalizer = RuntimeRequestFinalizer(publish: published.add);
      for (final step in RuntimeCleanupStep.values) {
        finalizer.add(step, () {
          if (step == failingStep && blocked) throw StateError('injected');
          released.add(step);
        });
      }
      final terminal = Object();
      expect(
        finalizer.finish(terminal),
        RuntimeCleanupOutcome.recoveryRequired,
      );
      expect(finalizer.failedStep, failingStep);
      expect(published, isEmpty);
      expect(released, RuntimeCleanupStep.values.take(failingStep.index));
      blocked = false;
      expect(finalizer.retry(), RuntimeCleanupOutcome.confirmed);
      expect(finalizer.failedStep, isNull);
      expect(released, RuntimeCleanupStep.values);
      expect(published, [same(terminal)]);
    });
  }
  test('terminal publication follows every successful cleanup step', () {
    final events = <String>[];
    final finalizer = RuntimeRequestFinalizer(
      publish: (_) => events.add('terminal'),
    );
    for (final step in RuntimeCleanupStep.values) {
      finalizer.add(step, () => events.add(step.name));
    }
    expect(finalizer.finish(Object()), RuntimeCleanupOutcome.confirmed);
    expect(events, [
      ...RuntimeCleanupStep.values.map((step) => step.name),
      'terminal',
    ]);
  });

  test(
    'failed cleanup retains unpublished outcome and remaining resources',
    () {
      final events = <String>[];
      final original = Object();
      final published = <Object>[];
      var blocked = true;
      final finalizer = RuntimeRequestFinalizer(publish: published.add);
      finalizer.add(RuntimeCleanupStep.sampler, () => events.add('sampler'));
      finalizer.add(RuntimeCleanupStep.cache, () {
        if (blocked) throw StateError('injected cleanup failure');
        events.add('cache');
      });
      finalizer.add(
        RuntimeCleanupStep.cancellation,
        () => events.add('cancellation'),
      );
      expect(
        finalizer.finish(original),
        RuntimeCleanupOutcome.recoveryRequired,
      );
      expect(published, isEmpty);
      expect(finalizer.isConfirmed, isFalse);
      expect(finalizer.pendingStepCount, 2);
      expect(finalizer.failedStep, RuntimeCleanupStep.cache);
      blocked = false;
      expect(finalizer.finish(Object()), RuntimeCleanupOutcome.confirmed);
      expect(published, [same(original)]);
      expect(events, ['sampler', 'cache', 'cancellation']);
      expect(finalizer.finish(Object()), RuntimeCleanupOutcome.confirmed);
      expect(published, hasLength(1));
    },
  );
}
