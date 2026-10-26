/// Immutable authority for the model offered during first-run setup.
abstract final class BundledModelManifest {
  static const String id = 'qwen3.5-0.8b-q4-k-m'; // hardcode: HC-025
  static const String displayName = 'Qwen3.5 0.8B Q4_K_M'; // hardcode: HC-025
  static const String publisher = 'unsloth'; // hardcode: HC-025
  static const String repository = '$publisher/Qwen3.5-0.8B-GGUF';
  static const String revision =
      '6ab461498e2023f6e3c1baea90a8f0fe38ab64d0'; // hardcode: HC-025
  static const String fileName = 'Qwen3.5-0.8B-Q4_K_M.gguf'; // hardcode: HC-025
  static const String sha256 =
      'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517'; // hardcode: HC-025
  static const int byteSize = 532517120; // hardcode: HC-025
  static const int parameterCount = 800000000; // hardcode: HC-025
  static const String quantization = 'Q4_K_M'; // hardcode: HC-025
  static const String source = 'bundled_download'; // hardcode: HC-025

  static const String downloadUrl =
      'https://huggingface.co/$repository/resolve/$revision/$fileName';

  static void validate() {
    assert(downloadUrl.startsWith('https://huggingface.co/'));
    assert(RegExp(r'^[0-9a-f]{40}$').hasMatch(revision));
    assert(RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256));
  }
}
