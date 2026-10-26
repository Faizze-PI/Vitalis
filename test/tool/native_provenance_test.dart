import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../third_party/llm_llamacpp/hook/native_provenance.dart';

void main() {
  test('Android C and C++ diagnostics do not embed the build checkout', () {
    final arguments = androidSourcePathArguments(r'D:\build space\llama');
    expect(arguments, [
      '-DCMAKE_C_FLAGS=-ffile-prefix-map="D:/build space/llama"=llama.cpp',
      '-DCMAKE_CXX_FLAGS=-ffile-prefix-map="D:/build space/llama"=llama.cpp',
    ]);
  });

  test(
    'native configure cannot inherit the surrounding app revision',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'vitalis_native_provenance_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final lock =
          jsonDecode(
                File(
                  'third_party/llm_llamacpp/native/llama_cpp.lock.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      // Characterizes the locked upstream's separate llama and GGML discovery.
      await File('${temporary.path}/CMakeLists.txt').writeAsString(r'''
cmake_minimum_required(VERSION 3.14)
project(provenance NONE)
set(BUILD_COMMIT "surrounding-app")
set(BUILD_NUMBER 999)
if(NOT DEFINED LLAMA_BUILD_COMMIT)
  set(LLAMA_BUILD_COMMIT ${BUILD_COMMIT})
endif()
if(NOT DEFINED LLAMA_BUILD_NUMBER)
  set(LLAMA_BUILD_NUMBER ${BUILD_NUMBER})
endif()
set(GGML_BUILD_COMMIT ${LLAMA_BUILD_COMMIT})
find_program(GIT_EXE NAMES git git.exe NO_CMAKE_FIND_ROOT_PATH)
if(GIT_EXE)
  execute_process(COMMAND ${GIT_EXE} rev-parse --short HEAD
    WORKING_DIRECTORY "${VITALIS_APP_ROOT}"
    OUTPUT_VARIABLE GGML_BUILD_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()
file(WRITE "${CMAKE_BINARY_DIR}/identity.txt"
  "${LLAMA_BUILD_COMMIT}\n${GGML_BUILD_COMMIT}\n${LLAMA_BUILD_NUMBER}\n")
''');
      final result = await Process.run('cmake', [
        // This compiler-free fixture must not probe installed Visual Studios.
        '-G',
        'Ninja',
        '-S',
        temporary.path,
        '-B',
        '${temporary.path}/build',
        '-DVITALIS_APP_ROOT=${Directory.current.path.replaceAll(r'\', '/')}',
        ...nativeProvenanceArguments(lock),
      ], runInShell: Platform.isWindows);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(await File('${temporary.path}/build/identity.txt').readAsLines(), [
        'ab0b3bd3c846839e9014c03b071f0f550a57ca84',
        'ab0b3bd3c846839e9014c03b071f0f550a57ca84',
        '10727',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
