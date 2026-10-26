import 'dart:async';
import 'dart:collection';

/// Collects tokens into a queue and emits them at a 50ms cadence,
/// producing a human-readable typing effect regardless of inference speed.
/// Implements an atomic-close guard to prevent post-disposal enqueues.
class BufferedStreamTransformer extends StreamTransformerBase<String, String> {
  final Duration _interval;

  const BufferedStreamTransformer([
    this._interval = const Duration(milliseconds: 50),
  ]);

  @override
  Stream<String> bind(Stream<String> stream) {
    final controller = StreamController<String>();
    final queue = Queue<String>();
    Timer? timer;
    var done = false;
    var closed = false;

    void safeAdd(String token) {
      if (!closed) {
        queue.add(token);
      }
    }

    void safeClose() {
      if (closed) return;
      closed = true;
      timer?.cancel();
      timer = null;
      controller.close();
    }

    void flush() {
      timer?.cancel();
      timer = null;
      while (queue.isNotEmpty && !closed) {
        controller.add(queue.removeFirst());
      }
      if (done) {
        safeClose();
      }
    }

    void emitTick() {
      if (queue.isNotEmpty && !closed) {
        controller.add(queue.removeFirst());
      }
      if (queue.isEmpty && done) {
        flush();
      }
    }

    stream.listen(
      (token) {
        safeAdd(token);
        if (timer == null && !closed) {
          timer = Timer.periodic(_interval, (_) => emitTick());
        }
      },
      onDone: () {
        done = true;
        if (queue.isEmpty) {
          safeClose();
        } else {
          timer?.cancel();
          if (!closed) {
            timer = Timer(_interval, flush);
          }
        }
      },
      onError: (error, stack) {
        timer?.cancel();
        if (!closed) {
          controller.addError(error, stack);
          safeClose();
        }
      },
      cancelOnError: false,
    );

    return controller.stream;
  }
}
