import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/inference_output_timing.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';

void main() {
  test(
    'sample and buffered emission retain separate first offsets and identity',
    () {
      var clock = 100;
      final recorder = InferenceOutputTimingRecorder(42, () => clock);
      final initial = recorder.snapshot;
      expect(initial.firstSampledTokenMicros, isNull);
      expect(initial.firstEmittedTextMicros, isNull);
      recorder.sampled();
      clock = 200;
      recorder.sampled();
      expect(recorder.snapshot.firstSampledTokenMicros, 100);
      expect(recorder.snapshot.firstEmittedTextMicros, isNull);
      clock = 300;
      recorder.emitted();
      clock = 400;
      recorder.emitted();
      expect(recorder.snapshot.firstEmittedTextMicros, 300);
      expect(recorder.snapshot.requestId, 42);
      expect(
        initial.firstSampledTokenMicros,
        isNull,
        reason: 'Snapshots are immutable',
      );
    },
  );
  test(
    'cancel acknowledgement preserves timing and a new request starts empty',
    () {
      const timing = InferenceOutputTiming(
        requestId: 42,
        firstSampledTokenMicros: 0,
      );
      final cancelled = InferenceCancelled(
        acknowledgementMicros: 5,
        outputTiming: timing,
      );
      expect(cancelled.withAcknowledgement(7).outputTiming, same(timing));
      final next = InferenceOutputTimingRecorder(43, () => 0);
      expect(next.snapshot.firstSampledTokenMicros, isNull);
      expect(next.snapshot.firstEmittedTextMicros, isNull);
      next.sampled();
      expect(next.snapshot.firstSampledTokenMicros, 0);
    },
  );
}
