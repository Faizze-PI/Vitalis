import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';

void main() {
  RuntimeProgress event({
    int request = 7,
    RuntimeProgressPhase phase = RuntimeProgressPhase.promptEvaluating,
    int units = 128,
    int elapsed = 100,
  }) => RuntimeProgress(
    requestId: request,
    phase: phase,
    completedUnits: units,
    elapsedMicroseconds: elapsed,
  );

  test('native progress rejects invalid identity units and clock', () {
    final tracker = RuntimeProgressTracker();
    expect(tracker.accept(event(request: -1)), isFalse);
    expect(tracker.accept(event(units: -1)), isFalse);
    expect(tracker.accept(event(elapsed: -1)), isFalse);
    expect(tracker.accept(event()), isTrue);
    expect(tracker.accept(event(request: 8, units: 256)), isFalse);
    expect(tracker.accept(event(units: 256, elapsed: 99)), isFalse);
    expect(
      tracker.accept(event(phase: RuntimeProgressPhase.contextCreating)),
      isFalse,
    );
    expect(tracker.accept(event(elapsed: 200)), isFalse);
    expect(tracker.accept(event(units: 127, elapsed: 200)), isFalse);
    expect(tracker.accept(event(units: 256, elapsed: 200)), isTrue);
    expect(
      tracker.accept(
        event(
          phase: RuntimeProgressPhase.tokenDecoding,
          units: 1,
          elapsed: 201,
        ),
      ),
      isTrue,
    );
    expect(
      tracker.accept(
        event(
          phase: RuntimeProgressPhase.tokenDecoding,
          units: 2,
          elapsed: 201,
        ),
      ),
      isTrue,
    );
  });

  test('progress chunks carry no response content or token metrics', () {
    final progress = event();
    final chunk = LlamaCppProgressChunk(progress);
    expect(chunk.progress, same(progress));
    expect(chunk.message, isNull);
    expect(chunk.evalCount, isNull);
    expect(chunk.done, isNull);
  });
}
