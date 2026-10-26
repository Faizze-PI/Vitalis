import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../third_party/llm_llamacpp/hook/build.dart' as hook;

void main() {
  test('primary asset resolves the generated binding canonical ID', () {
    expect(
      hook.nativeLibraryAsset(File('libllama.so')).id,
      'package:llm_llamacpp/llama.dart',
    );
  });

  test('backend assets have exactly one package prefix', () {
    expect(
      hook.nativeLibraryAsset(File('libggml-cpu.so')).id,
      'package:llm_llamacpp/native/libggml-cpu.so',
    );
  });
}
