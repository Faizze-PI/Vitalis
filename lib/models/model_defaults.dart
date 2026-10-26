/// Single authority for new-chat inference defaults and database migrations.
abstract final class ModelDefaults {
  static const double temperature = 0.7; // hardcode: HC-004
  static const int topK = 40; // hardcode: HC-004
  static const double topP = 0.9; // hardcode: HC-004
  static const int maximumOutputTokens = 2048; // hardcode: HC-004
  static const String systemPrompt =
      'You are a helpful assistant.'; // hardcode: HC-004
}
