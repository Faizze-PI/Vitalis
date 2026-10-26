class AppConstants {
  static const String appName = 'Vitalis'; // hardcode: HC-044
  static const String databaseName = 'vitalis.db'; // hardcode: HC-044
  static const int databaseVersion = 8; // hardcode: HC-044
  static const int maxStoredTextBytes = 1024 * 1024;
  static const int maxChatTitleLength = 256; // hardcode: HC-021
  static const int maxPersonaNameLength = 256; // hardcode: HC-021
  static const int maxPersonaSystemPromptLength = maxStoredTextBytes;
  static const int maxNoteTitleLength = 256; // hardcode: HC-021
  static const int maxNoteContentLength = maxStoredTextBytes;
  static const int defaultContextSize = 8192; // hardcode: HC-005
  static const int minimumContextSize = 2048; // hardcode: HC-005
  static const int nativeMaximumContextSize = 131072; // hardcode: HC-005
  static const int conservativeUnknownContextSize = 4096; // hardcode: HC-005
  static const double contextMemoryBudgetFraction = 0.20; // hardcode: HC-005
  static const int conservativeKvBytesPerToken = 64 * 1024;
  static const int defaultBatchSize = 256; // hardcode: HC-006
  static const int minimumBatchSize = 32; // hardcode: HC-006
  static const int nativeMaximumBatchSize = 2048; // hardcode: HC-006
  static const int defaultReservedOutputTokens = 768; // hardcode: HC-004
  static const Duration requestTimeout = Duration(seconds: 60);
}
