import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/response_frame_timing.dart';

void main() {
  test(
    'only a response frame after received text records submission latency',
    () {
      var clock = 100;
      final tracker = ResponseFrameTimingTracker(() => clock);
      expect(tracker.snapshot, isNull);
      tracker.begin();
      final identity = tracker.identity!;
      expect(tracker.recordFrame(identity), isFalse);
      clock = 140;
      tracker.receivedText();
      clock = 150;
      tracker.receivedText();
      final before = tracker.snapshot!;
      expect(before.firstReceivedTextMicros, 40);
      expect(before.firstRenderedFrameMicros, isNull);
      clock = 170;
      expect(tracker.recordFrame(Object()), isFalse);
      expect(tracker.recordFrame(identity), isTrue);
      clock = 190;
      expect(tracker.recordFrame(identity), isFalse);
      tracker.bindNativeRequest(0);
      expect(tracker.snapshot!.nativeRequestId, 0);
      expect(tracker.snapshot!.firstRenderedFrameMicros, 70);
      expect(before.firstRenderedFrameMicros, isNull);
    },
  );
  test('cancelled and replaced responses reject stale frame callbacks', () {
    var clock = 0;
    final tracker = ResponseFrameTimingTracker(() => clock);
    tracker.begin();
    final old = tracker.identity!;
    tracker.receivedText();
    tracker.bindNativeRequest(99);
    tracker.invalidate();
    clock = 5;
    expect(tracker.recordFrame(old), isFalse);
    tracker.receivedText();
    tracker.begin();
    final current = tracker.identity!;
    expect(identical(old, current), isFalse);
    expect(tracker.snapshot!.firstReceivedTextMicros, isNull);
    expect(tracker.snapshot!.nativeRequestId, isNull);
    clock = 7;
    tracker.receivedText();
    expect(tracker.recordFrame(old), isFalse);
    expect(tracker.recordFrame(current), isTrue);
    expect(tracker.snapshot!.firstRenderedFrameMicros, 2);
  });
  test('backward clock cannot invent a rendered frame', () {
    var clock = 10;
    final tracker = ResponseFrameTimingTracker(() => clock)..begin();
    clock = 20;
    tracker.receivedText();
    clock = 15;
    expect(tracker.recordFrame(tracker.identity!), isFalse);
    expect(tracker.snapshot!.firstRenderedFrameMicros, isNull);
  });
}
