abstract final class DiagnosticsPolicy {
  static const int retentionDays = 7; // hardcode: HC-014
  static const int maximumFileBytes = 2 * 1024 * 1024;
  static const int maximumInMemoryLines = 200; // hardcode: HC-014
  static const int pruneEveryWrites = 10; // hardcode: HC-014
}
