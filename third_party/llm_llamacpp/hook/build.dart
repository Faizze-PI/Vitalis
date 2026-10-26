// Copyright 2024 The dart-llm Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Native Assets build hook for llm_llamacpp.
///
/// Every platform builds the same hash-locked llama.cpp source archive.
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import 'native_provenance.dart';

/// CodeAsset adds the package prefix; names must remain package-relative.
const String _llamaAssetName = 'llama.dart'; // hardcode: HC-069

CodeAsset nativeLibraryAsset(File library) {
  final name = library.uri.pathSegments.last;
  return CodeAsset(
    package: 'llm_llamacpp',
    name: name == 'llama.dll' || name == 'libllama.so'
        ? _llamaAssetName
        : 'native/$name',
    linkMode: DynamicLoadingBundled(),
    file: library.uri,
  );
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    final logger = Logger('')
      ..level = Level.ALL
      // ignore: avoid_print
      ..onRecord.listen((record) => print(record.message));

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    logger.info('Building llm_llamacpp for $targetOS-$targetArch');

    if (targetOS == OS.android) {
      await _buildAndroidCodeAssets(input, output, logger);
      return;
    }

    if (targetOS != OS.windows && targetOS != OS.linux) {
      logger.warning('Unsupported OS: $targetOS');
      return;
    }
    await _buildDesktopCodeAssets(input, output, logger);
  });
}

Future<void> _buildDesktopCodeAssets(
  BuildInput input,
  BuildOutputBuilder output,
  Logger logger,
) async {
  final targetOS = input.config.code.targetOS;
  final architecture = input.config.code.targetArchitecture;
  if (architecture != Architecture.x64) {
    throw StateError('VITALIS desktop currently supports x64 only');
  }
  final lockFile = File.fromUri(
    input.packageRoot.resolve('native/llama_cpp.lock.json'),
  );
  if (!lockFile.existsSync()) {
    throw StateError('Missing native source lock: ${lockFile.path}');
  }
  final lock =
      jsonDecode(await lockFile.readAsString()) as Map<String, Object?>;
  final cache = _nativeCache(input, lock)..createSync(recursive: true);
  final source = await _obtainLockedSource(lock, cache, logger);
  final bridge = await _installRuntimeBridge(input, source);
  final enableVulkan = input.userDefines['enable_vulkan'] == true;
  final buildDir = Directory.fromUri(
    cache.uri.resolve(
      '${targetOS.name}-x64-${enableVulkan ? 'vulkan' : 'cpu'}/',
    ),
  )..createSync(recursive: true);
  await _runChecked('cmake', [
    '-S',
    source.path,
    '-B',
    buildDir.path,
    '-DCMAKE_BUILD_TYPE=Release',
    ...nativeProvenanceArguments(lock),
    '-DBUILD_SHARED_LIBS=ON',
    '-DGGML_NATIVE=OFF',
    '-DGGML_OPENMP=OFF',
    '-DGGML_BACKEND_DL=ON',
    '-DGGML_VULKAN=${enableVulkan ? 'ON' : 'OFF'}',
    '-DLLAMA_STANDALONE=OFF',
    '-DLLAMA_BUILD_COMMON=OFF',
    '-DLLAMA_BUILD_APP=OFF',
    '-DLLAMA_BUILD_MTMD=OFF',
    '-DLLAMA_BUILD_TESTS=OFF',
    '-DLLAMA_BUILD_EXAMPLES=OFF',
    '-DLLAMA_BUILD_SERVER=OFF',
    '-DLLAMA_BUILD_TOOLS=OFF',
    '-DLLAMA_CURL=OFF',
  ], logger);
  await _runChecked('cmake', [
    '--build',
    buildDir.path,
    '--config',
    'Release',
    '--parallel',
    '${Platform.numberOfProcessors.clamp(1, 8)}',
  ], logger);
  final names = targetOS == OS.windows
      ? <String>['llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu.dll']
      : <String>[
          'libllama.so',
          'libggml.so',
          'libggml-base.so',
          'libggml-cpu.so',
        ];
  if (enableVulkan) {
    names.add(targetOS == OS.windows ? 'ggml-vulkan.dll' : 'libggml-vulkan.so');
  }
  final libraries = names.map((name) => _findBuiltLibrary(buildDir, name));
  for (final library in libraries) {
    output.assets.code.add(nativeLibraryAsset(library));
  }
  output.dependencies.add(lockFile.uri);
  output.dependencies.add(bridge.uri);
  output.dependencies.addAll([
    input.packageRoot.resolve('native/vitalis_chat_template.cpp'),
    input.packageRoot.resolve('native/vitalis_chat_template.h'),
  ]);
}

Future<void> _buildAndroidCodeAssets(
  BuildInput input,
  BuildOutputBuilder output,
  Logger logger,
) async {
  final architecture = input.config.code.targetArchitecture;
  if (architecture != Architecture.arm64) {
    logger.warning(
      'Skipping unsupported Android architecture $architecture; '
      'VITALIS packages arm64 only.',
    );
    return;
  }

  final packageRoot = input.packageRoot;
  final lockFile = File.fromUri(
    packageRoot.resolve('native/llama_cpp.lock.json'),
  );
  if (!lockFile.existsSync()) {
    throw StateError('Missing native source lock: ${lockFile.path}');
  }
  final lock =
      jsonDecode(await lockFile.readAsString()) as Map<String, Object?>;
  final expectedNdk = lock['androidNdk']! as String;
  final api = lock['androidApi']! as int;
  if (api != input.config.code.android.targetNdkApi) {
    throw StateError(
      'Android API drift: native lock requires $api, build requested '
      '${input.config.code.android.targetNdkApi}',
    );
  }

  final suppliedNdkRoot = _androidNdkRoot(input);
  final ndkRoot =
      suppliedNdkRoot.uri.pathSegments.where((part) => part.isNotEmpty).last ==
          expectedNdk
      ? suppliedNdkRoot
      : Directory('${suppliedNdkRoot.parent.path}/$expectedNdk');
  if (!File(
    '${ndkRoot.path}/build/cmake/android.toolchain.cmake',
  ).existsSync()) {
    throw StateError(
      'Android NDK drift: native lock requires $expectedNdk, found '
      '${suppliedNdkRoot.path}, and the pinned side-by-side NDK is missing',
    );
  }

  final cache = _nativeCache(input, lock)..createSync(recursive: true);
  final source = await _obtainLockedSource(lock, cache, logger);
  final bridge = await _installRuntimeBridge(input, source);
  // This user-define is part of the hook input/cache key. Runtime capability
  // probing and the self-test keep CPU as the default when it is enabled.
  final enableVulkan = input.userDefines['enable_vulkan'] == true;
  final buildDir = Directory.fromUri(
    cache.uri.resolve(
      enableVulkan ? 'android-arm64-vulkan/' : 'android-arm64-cpu/',
    ),
  )..createSync(recursive: true);
  final shaderHost = Platform.isWindows
      ? 'windows-x86_64'
      : Platform.isMacOS
      ? 'darwin-x86_64'
      : 'linux-x86_64';
  final glslc = File(
    '${ndkRoot.path}/shader-tools/$shaderHost/${Platform.isWindows ? 'glslc.exe' : 'glslc'}',
  );
  if (enableVulkan && !glslc.existsSync()) {
    throw StateError(
      'Pinned NDK is missing Vulkan shader compiler: ${glslc.path}',
    );
  }

  final arguments = <String>[
    '-S',
    source.path,
    '-B',
    buildDir.path,
    '-G',
    'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    ...nativeProvenanceArguments(lock),
    ...androidSourcePathArguments(source.path),
    '-DCMAKE_TOOLCHAIN_FILE=${ndkRoot.path}/build/cmake/android.toolchain.cmake',
    '-DANDROID_ABI=arm64-v8a',
    '-DANDROID_PLATFORM=android-$api',
    '-DANDROID_STL=c++_static',
    '-DBUILD_SHARED_LIBS=ON',
    '-DGGML_NATIVE=OFF',
    '-DGGML_OPENMP=OFF',
    '-DGGML_BACKEND_DL=ON',
    '-DGGML_VULKAN=${enableVulkan ? 'ON' : 'OFF'}',
    if (enableVulkan) '-DVulkan_GLSLC_EXECUTABLE=${glslc.path}',
    '-DLLAMA_STANDALONE=OFF',
    '-DLLAMA_BUILD_COMMON=OFF',
    '-DLLAMA_BUILD_APP=OFF',
    '-DLLAMA_BUILD_MTMD=OFF',
    '-DLLAMA_BUILD_TESTS=OFF',
    '-DLLAMA_BUILD_EXAMPLES=OFF',
    '-DLLAMA_BUILD_SERVER=OFF',
    '-DLLAMA_BUILD_TOOLS=OFF',
    '-DLLAMA_CURL=OFF',
  ];
  await _runChecked('cmake', arguments, logger);
  await _runChecked('cmake', [
    '--build',
    buildDir.path,
    '--config',
    'Release',
    '--parallel',
    '${Platform.numberOfProcessors.clamp(1, 8)}',
  ], logger);

  const required = <String>[
    'libllama.so',
    'libggml.so',
    'libggml-base.so',
    'libggml-cpu.so',
  ];
  final libraries = <File>[];
  for (final name in required) {
    libraries.add(_findBuiltLibrary(buildDir, name));
  }
  if (enableVulkan) {
    libraries.add(_findBuiltLibrary(buildDir, 'libggml-vulkan.so'));
  }

  for (final library in libraries) {
    output.assets.code.add(nativeLibraryAsset(library));
  }
  output.dependencies.add(lockFile.uri);
  output.dependencies.add(bridge.uri);
  output.dependencies.addAll([
    input.packageRoot.resolve('native/vitalis_chat_template.cpp'),
    input.packageRoot.resolve('native/vitalis_chat_template.h'),
  ]);
  logger.info(
    'Registered Android native assets: '
    '${libraries.map((file) => file.uri.pathSegments.last).join(', ')}',
  );
}

Future<File> _installRuntimeBridge(BuildInput input, Directory source) async {
  final bridge = File.fromUri(
    input.packageRoot.resolve('native/vitalis_runtime_bridge.cpp'),
  );
  if (!bridge.existsSync()) {
    throw StateError('Missing VITALIS native runtime bridge: ${bridge.path}');
  }
  final destination = File.fromUri(
    source.uri.resolve('src/vitalis_runtime_bridge.cpp'),
  );
  final contents = await bridge.readAsBytes();
  if (!destination.existsSync() ||
      !(await destination.readAsBytes()).elementsEqual(contents)) {
    await destination.writeAsBytes(contents, flush: true);
  }

  final cmake = File.fromUri(source.uri.resolve('src/CMakeLists.txt'));
  const registration =
      '\n# VITALIS audited native callback/lifecycle bridge.\n'
      'target_sources(llama PRIVATE vitalis_runtime_bridge.cpp)\n';
  final cmakeContents = await cmake.readAsString();
  if (!cmakeContents.contains('vitalis_runtime_bridge.cpp')) {
    await cmake.writeAsString('$cmakeContents$registration', flush: true);
  }
  for (final name in ['vitalis_chat_template.cpp', 'vitalis_chat_template.h']) {
    final inputFile = File.fromUri(input.packageRoot.resolve('native/$name'));
    final target = File.fromUri(source.uri.resolve('src/$name'));
    final bytes = await inputFile.readAsBytes();
    if (!target.existsSync() ||
        !(await target.readAsBytes()).elementsEqual(bytes)) {
      await target.writeAsBytes(bytes, flush: true);
    }
  }
  final current = await cmake.readAsString();
  // Replace only this owned suffix so an interrupted integration is repairable.
  const marker = '# VITALIS configured templates'; // hardcode: HC-068
  final base = current.contains(marker)
      ? current.substring(0, current.indexOf(marker))
      : current;
  final configured = '''${base.trimRight()}
# VITALIS configured templates use the same locked upstream Jinja engine.
target_sources(llama PRIVATE vitalis_chat_template.cpp
  ../common/jinja/lexer.cpp ../common/jinja/parser.cpp
  ../common/jinja/runtime.cpp ../common/jinja/value.cpp
  ../common/jinja/string.cpp ../common/json.cpp ../common/unicode.cpp)
target_include_directories(llama BEFORE PRIVATE ../common ../vendor)
''';
  if (configured != current) await cmake.writeAsString(configured, flush: true);
  return bridge;
}

extension on List<int> {
  bool elementsEqual(List<int> other) {
    if (length != other.length) return false;
    for (var index = 0; index < length; index++) {
      if (this[index] != other[index]) return false;
    }
    return true;
  }
}

Directory _nativeCache(BuildInput input, Map<String, Object?> lock) {
  final packageDirectory = Directory.fromUri(input.packageRoot);
  final consumingProject = packageDirectory.parent.parent;
  return Directory(
    '${consumingProject.path}/.native-build/llama-${lock['commit']}',
  );
}

Directory _androidNdkRoot(BuildInput input) {
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    throw StateError('Flutter did not provide an Android C toolchain');
  }
  var directory = File.fromUri(compiler).parent;
  for (var level = 0; level < 10; level++) {
    final toolchain = File(
      '${directory.path}/build/cmake/android.toolchain.cmake',
    );
    if (toolchain.existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Unable to locate Android NDK from $compiler');
}

Future<Directory> _obtainLockedSource(
  Map<String, Object?> lock,
  Directory cache,
  Logger logger,
) async {
  final commit = lock['commit']! as String;
  final source = Directory.fromUri(cache.uri.resolve('llama.cpp-$commit/'));
  if (File.fromUri(source.uri.resolve('CMakeLists.txt')).existsSync()) {
    return source;
  }

  final archive = File.fromUri(cache.uri.resolve('source.tar.gz'));
  if (!archive.existsSync()) {
    logger.info('Downloading locked llama.cpp source $commit');
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse(lock['archiveUrl']! as String),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Source download returned ${response.statusCode}');
      }
      final sink = archive.openWrite();
      await response.pipe(sink);
    } finally {
      client.close(force: true);
    }
  }
  final digest = await sha256.bind(archive.openRead()).first;
  final expected = (lock['archiveSha256']! as String).toLowerCase();
  if (digest.toString() != expected) {
    archive.deleteSync();
    throw StateError(
      'llama.cpp source hash mismatch: expected $expected, got $digest',
    );
  }

  final extractRoot = Directory.fromUri(cache.uri.resolve('source/'));
  if (extractRoot.existsSync()) extractRoot.deleteSync(recursive: true);
  extractRoot.createSync(recursive: true);
  await _runChecked('tar', [
    '-xzf',
    archive.path,
    '-C',
    extractRoot.path,
  ], logger);
  final extracted = extractRoot.listSync().whereType<Directory>().single;
  extracted.renameSync(source.path);
  return source;
}

Future<void> _runChecked(
  String executable,
  List<String> arguments,
  Logger logger,
) async {
  logger.info('$executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

File _findBuiltLibrary(Directory buildDir, String name) {
  final matches = buildDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.uri.pathSegments.last == name)
      .toList();
  if (matches.isEmpty) {
    throw StateError('Native build did not produce $name');
  }
  matches.sort((left, right) => left.path.length.compareTo(right.path.length));
  return matches.first;
}
