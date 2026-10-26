class ContextPlanResult {
  ContextPlanResult({
    required this.context,
    required this.promptTokens,
    required this.contextSize,
    this.droppedMessageCount = 0,
    this.droppedNoteCount = 0,
    this.reservedOutputTokens = 0,
  }) : usageRatio = contextSize > 0
           ? (promptTokens / contextSize).clamp(0.0, 1.0)
           : 0.0;

  final List<Map<String, String>> context;
  final int promptTokens;
  final int contextSize;
  final int droppedMessageCount;
  final int droppedNoteCount;
  final int reservedOutputTokens;
  final double usageRatio;

  bool get wasTruncated => droppedMessageCount > 0 || droppedNoteCount > 0;
}
