// Copyright 2024 The dart-llm Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

List<String> androidSourcePathArguments(String sourceRoot) {
  // Keep __FILE__ diagnostics and DWARF independent of the checkout location.
  final mapping = // hardcode: HC-071
      '-ffile-prefix-map="${sourceRoot.replaceAll(r'\', '/')}"=llama.cpp';
  return ['-DCMAKE_C_FLAGS=$mapping', '-DCMAKE_CXX_FLAGS=$mapping'];
}

List<String> nativeProvenanceArguments(Map<String, Object?> lock) => [
  '-DLLAMA_BUILD_COMMIT=${lock['commit']! as String}',
  '-DLLAMA_BUILD_NUMBER=${(lock['tag']! as String).substring(1)}',
  // Extracted upstream sources must not discover the consuming app's Git repo.
  '-DGIT_EXE=',
  '-DGIT_EXECUTABLE=',
];
