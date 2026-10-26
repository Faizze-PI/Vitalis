import 'package:flutter_test/flutter_test.dart';

import '../tool/verify_native_asset_manifest.dart';

void main() {
  Map<String, Object?> fixture() => {
    'format-version': [1, 0, 0],
    'native-assets': {
      'android_arm64': {
        'package:llm_llamacpp/llama.dart': ['absolute', 'libllama.so'],
        'package:llm_llamacpp/native/libggml.so': ['absolute', 'libggml.so'],
        'package:llm_llamacpp/native/libggml-base.so': [
          'absolute',
          'libggml-base.so',
        ],
        'package:llm_llamacpp/native/libggml-cpu.so': [
          'absolute',
          'libggml-cpu.so',
        ],
      },
    },
  };

  test('accepts canonical packaged binding and backend mappings', () {
    verifyNativeAssetManifest(fixture());
  });

  test('rejects doubled IDs even if the canonical mapping also exists', () {
    final data = fixture();
    final assets = ((data['native-assets'] as Map)['android_arm64'] as Map);
    assets['package:llm_llamacpp/package:llm_llamacpp/llama.dart'] = [
      'absolute',
      'libllama.so',
    ];
    expect(() => verifyNativeAssetManifest(data), throwsFormatException);
  });

  test('rejects absent primary binding', () {
    final data = fixture();
    ((data['native-assets'] as Map)['android_arm64'] as Map).remove(
      'package:llm_llamacpp/llama.dart',
    );
    expect(() => verifyNativeAssetManifest(data), throwsFormatException);
  });

  test('rejects wrong library and non-bundled resolution', () {
    for (final value in [
      ['absolute', 'libwrong.so'],
      ['process'],
      ['absolute', '../libllama.so'],
    ]) {
      final data = fixture();
      ((data['native-assets'] as Map)['android_arm64']
              as Map)['package:llm_llamacpp/llama.dart'] =
          value;
      expect(() => verifyNativeAssetManifest(data), throwsFormatException);
    }
  });

  test('rejects missing backend and unsupported schema', () {
    final data = fixture();
    ((data['native-assets'] as Map)['android_arm64'] as Map).remove(
      'package:llm_llamacpp/native/libggml-cpu.so',
    );
    expect(() => verifyNativeAssetManifest(data), throwsFormatException);
    expect(() => verifyNativeAssetManifest({}), throwsFormatException);
    expect(() => verifyNativeAssetManifest(null), throwsFormatException);
  });
}
