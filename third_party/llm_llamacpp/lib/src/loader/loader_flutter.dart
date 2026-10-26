import 'dart:ffi';
import 'dart:io';

import 'package:llm_llamacpp/src/native_log.dart';

/// Load the llama.cpp library for Flutter applications.
///
/// Flutter's plugin system handles the native library loading automatically
/// when using an FFI plugin structure. The library is bundled with the app
/// and accessible via the standard plugin mechanism.
DynamicLibrary loadLibrary() {
  if (Platform.isAndroid) {
    // Android: Pre-load ggml dependencies before loading libllama.so
    // These libraries must be loaded in dependency order
    _loadAndroidDependencies();
    try {
      final lib = DynamicLibrary.open('libllama.so');
      // ignore: avoid_print
      NativeLog.debug('[llm_llamacpp] Successfully loaded libllama.so');
      return lib;
    } catch (e) {
      // ignore: avoid_print
      NativeLog.debug('[llm_llamacpp] ERROR loading libllama.so: $e');
      rethrow;
    }
  } else if (Platform.isIOS) {
    // iOS: Framework is linked statically or via xcframework
    return DynamicLibrary.process();
  } else if (Platform.isMacOS) {
    // macOS: Flutter bundles every code asset as its own framework, stripping
    // the `lib` prefix and the `.dylib` extension, so `libllama.dylib` is
    // installed as `llama.framework/llama` with the install name
    // `@rpath/llama.framework/llama`. There is no `libllama.dylib` in the app
    // bundle to open by that name.
    //
    // The ggml libraries are bundled the same way, and Flutter rewrites
    // libllama's references to point at them, so dyld pulls them in on its own
    // and nothing needs pre-loading here (unlike Android, which loads its CPU
    // backends dynamically).
    return _openFirst([
      '@rpath/llama.framework/llama',
      // Non-Flutter embeddings put the plain dylib on the loader path.
      'libllama.dylib',
    ]);
  } else if (Platform.isWindows) {
    // Windows: DLL is bundled with the app
    return DynamicLibrary.open('llama.dll');
  } else if (Platform.isLinux) {
    // Linux: Shared library is bundled with the app
    return DynamicLibrary.open('libllama.so');
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

/// Opens the first library that loads, reporting every failure if none do.
DynamicLibrary _openFirst(List<String> candidates) {
  final failures = <String>[];
  for (final candidate in candidates) {
    try {
      return DynamicLibrary.open(candidate);
    } catch (e) {
      failures.add('  $candidate: $e');
    }
  }
  throw StateError(
    'Failed to load the llama.cpp library. Tried:\n${failures.join('\n')}',
  );
}

/// Pre-load ggml dependency libraries on Android.
///
/// On Android, shared libraries must be loaded in dependency order.
/// libllama.so depends on libggml.so which depends on libggml-base.so.
///
/// CPU Hardware Acceleration:
/// The libraries are built with GGML_BACKEND_DL=ON and
/// GGML_CPU_ALL_VARIANTS=OFF. The generic libggml-cpu.so is discovered and
/// registered by [BackendInitializer] after libllama is loaded.
///
/// Load order:
/// 1. libggml-base.so (base GGML library)
/// 2. libggml.so (GGML coordinator)
void _loadAndroidDependencies() {
  // Load base library first
  try {
    DynamicLibrary.open('libggml-base.so');
    // ignore: avoid_print
    NativeLog.debug('[llm_llamacpp] Loaded dependency: libggml-base.so');
  } catch (e) {
    // ignore: avoid_print
    NativeLog.debug('[llm_llamacpp] Failed to load libggml-base.so: $e');
  }

  // Load the GGML coordinator library
  try {
    DynamicLibrary.open('libggml.so');
    // ignore: avoid_print
    NativeLog.debug('[llm_llamacpp] Loaded dependency: libggml.so');
  } catch (e) {
    // ignore: avoid_print
    NativeLog.debug('[llm_llamacpp] Failed to load libggml.so: $e');
  }
}
