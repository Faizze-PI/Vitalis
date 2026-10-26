import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/native_runtime_bridge.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/exceptions.dart';

/// Represents a loaded llama.cpp model.
///
/// Models are loaded from GGUF files and can be used with multiple contexts.
class LlamaCppModel {
  LlamaCppModel._({
    required this.path,
    required ffi.Pointer<llama_model> modelPtr,
    required LlamaBindings bindings,
    required NativeRuntimeBridge bridge,
    required ffi.Pointer<ffi.Void> accessLease,
  }) : _modelPtr = modelPtr,
       _bindings = bindings,
       _bridge = bridge,
       _accessLease = accessLease;

  /// The path to the GGUF model file.
  final String path;

  final ffi.Pointer<llama_model> _modelPtr;
  final LlamaBindings _bindings;
  final NativeRuntimeBridge _bridge;
  final ffi.Pointer<ffi.Void> _accessLease;

  bool _disposed = false;

  /// Returns the internal model pointer.
  ///
  /// This should only be used by internal code.
  ffi.Pointer<llama_model> get pointer {
    _checkNotDisposed();
    return _modelPtr;
  }

  /// Gets the vocabulary from the model.
  ffi.Pointer<llama_vocab> get vocab {
    _checkNotDisposed();
    return _bindings.llama_model_get_vocab(_modelPtr);
  }

  /// Gets the vocabulary size.
  int get vocabSize {
    _checkNotDisposed();
    return _bindings.llama_vocab_n_tokens(vocab);
  }

  /// Gets the training context size.
  int get contextSizeTrain {
    _checkNotDisposed();
    return _bindings.llama_model_n_ctx_train(_modelPtr);
  }

  /// Gets the embedding dimension.
  int get embeddingSize {
    _checkNotDisposed();
    return _bindings.llama_model_n_embd(_modelPtr);
  }

  /// Gets the beginning-of-sequence token.
  int get bosToken {
    _checkNotDisposed();
    return _bindings.llama_vocab_bos(vocab);
  }

  /// Gets the end-of-sequence token.
  int get eosToken {
    _checkNotDisposed();
    return _bindings.llama_vocab_eos(vocab);
  }

  /// Gets the newline token.
  int get nlToken {
    _checkNotDisposed();
    return _bindings.llama_vocab_nl(vocab);
  }

  /// Gets the padding token.
  int get padToken {
    _checkNotDisposed();
    return _bindings.llama_vocab_pad(vocab);
  }

  /// Checks if a token is an end-of-generation token.
  bool isEogToken(int token) {
    _checkNotDisposed();
    return _bindings.llama_vocab_is_eog(vocab, token);
  }

  /// Checks if a token is a control token.
  bool isControlToken(int token) {
    _checkNotDisposed();
    return _bindings.llama_vocab_is_control(vocab, token);
  }

  /// Releases the model resources.
  void dispose() {
    if (!_disposed) {
      _bindings.llama_free_model(_modelPtr);
      _disposed = true;
      _bridge.releaseModelAccess(_accessLease);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('Model has been disposed');
    }
  }

  /// Loads a model from a GGUF file.
  static LlamaCppModel load(
    String path,
    LlamaBindings bindings, {
    int nGpuLayers = 0,
    bool useMemoryMap = true,
    bool useMemoryLock = false,
    bool vocabOnly = false,
  }) {
    // 1. Check file exists
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception('Model file not found: $path');
    }

    // 2. Check file size
    final size = file.lengthSync();
    if (size == 0) {
      throw Exception('Model file is empty: $path');
    }

    final params = bindings.llama_model_default_params();
    params.n_gpu_layers = nGpuLayers;
    if (useMemoryMap && !bindings.llama_supports_mmap()) {
      throw UnsupportedError('Native backend does not support memory mapping');
    }
    if (useMemoryLock && !bindings.llama_supports_mlock()) {
      throw UnsupportedError('Native backend does not support memory locking');
    }
    // b10727 represents these options with one load-mode enum, not booleans.
    params.load_mode = useMemoryMap
        ? (useMemoryLock
              ? llama_load_mode.LLAMA_LOAD_MODE_MMAP_MLOCK
              : llama_load_mode.LLAMA_LOAD_MODE_MMAP)
        : (useMemoryLock
              ? llama_load_mode.LLAMA_LOAD_MODE_MLOCK
              : llama_load_mode.LLAMA_LOAD_MODE_NONE);
    params.vocab_only = vocabOnly;

    final bridge = NativeRuntimeBridge(loadLlamaLibrary());
    final lease = bridge.acquireModelRead(modelPath: path);
    ffi.Pointer<Utf8> pathPtr = ffi.nullptr;
    var retained = false;
    try {
      if (lease.address == 0) throw InferenceRuntimeBusy();
      pathPtr = path.toNativeUtf8();
      final modelPtr = bindings.llama_load_model_from_file(
        pathPtr.cast(),
        params,
      );

      if (modelPtr.address == 0) {
        throw Exception(
          'Failed to load model (size: $size bytes). '
          'Native diagnostics are redacted.',
        );
      }

      retained = true;
      return LlamaCppModel._(
        path: path,
        modelPtr: modelPtr,
        bindings: bindings,
        bridge: bridge,
        accessLease: lease,
      );
    } finally {
      if (pathPtr.address != 0) calloc.free(pathPtr);
      if (!retained && lease.address != 0) bridge.releaseModelAccess(lease);
    }
  }
}

/// Options for model loading.
class ModelLoadOptions {
  const ModelLoadOptions({
    this.nGpuLayers = 0,
    this.useMemoryMap = true,
    this.useMemoryLock = false,
    this.vocabOnly = false,
  });

  /// Number of layers to offload to GPU.
  final int nGpuLayers;

  /// Whether to use memory-mapped files.
  final bool useMemoryMap;

  /// Whether to lock model in memory.
  final bool useMemoryLock;

  /// Whether to load only vocabulary (for tokenization).
  final bool vocabOnly;
}
