import 'package:llm_core/llm_core.dart' show LLMChunk;

/// Completed native work, not a timer heartbeat or a visible-output metric.
enum RuntimeProgressPhase {
  backendInitializing,
  modelLoading,
  contextCreating,
  promptEvaluating,
  tokenDecoding,
  requestCleanup,
}

class RuntimeProgress {
  const RuntimeProgress({
    required this.requestId,
    required this.phase,
    required this.completedUnits,
    required this.elapsedMicroseconds,
  });
  final int requestId;
  final RuntimeProgressPhase phase;
  final int completedUnits;
  final int elapsedMicroseconds;
}

/// An in-band typed control event with no assistant content.
class LlamaCppProgressChunk extends LLMChunk {
  LlamaCppProgressChunk(this.progress)
    : super(model: null, createdAt: DateTime.now(), message: null);
  final RuntimeProgress progress;
}

/// Reject stale requests, reversed phases/time and repeated work counters.
class RuntimeProgressTracker {
  RuntimeProgress? _last;
  bool accept(RuntimeProgress progress) {
    if (progress.requestId < 0 ||
        progress.completedUnits < 0 ||
        progress.elapsedMicroseconds < 0)
      return false;
    final last = _last;
    if (last != null &&
        (progress.requestId != last.requestId ||
            progress.elapsedMicroseconds < last.elapsedMicroseconds ||
            progress.phase.index < last.phase.index ||
            (progress.phase == last.phase &&
                progress.completedUnits <= last.completedUnits))) {
      return false;
    }
    _last = progress;
    return true;
  }
}
