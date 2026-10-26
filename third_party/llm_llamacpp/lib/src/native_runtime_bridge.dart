import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';

/// Native-only bridge for process-global lifecycle and worker-thread callbacks.
///
/// Callback functions installed in llama.cpp must never be Dart callbacks:
/// llama.cpp may invoke them from a worker thread that is not entered into the
/// isolate which created the callback.
final class NativeRuntimeBridge {
  NativeRuntimeBridge(ffi.DynamicLibrary library)
    : _acquireModelFileRead = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>)
          >('vitalis_model_file_read_acquire'),
      _acquireModelFileMutation = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>)
          >('vitalis_model_file_mutation_acquire'),
      _acquireModelRead = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()
          >('vitalis_model_read_acquire'),
      _acquireModelMutation = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()
          >('vitalis_model_mutation_acquire'),
      _releaseModelAccess = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('vitalis_model_access_release'),
      _silenceLogs = library
          .lookupFunction<ffi.Void Function(), void Function()>(
            'vitalis_llama_silence_logs',
          ),
      _beginBackendInitialization = library
          .lookupFunction<ffi.Int32 Function(), int Function()>(
            'vitalis_backend_begin_initialization',
          ),
      _finishBackendInitialization = library
          .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>(
            'vitalis_backend_finish_initialization',
          ),
      _isBackendInitialized = library
          .lookupFunction<ffi.Int32 Function(), int Function()>(
            'vitalis_backend_is_initialized',
          ),
      _createCancelToken = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()
          >('vitalis_cancel_token_create'),
      _modelLoadCancelCallback = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()
          >('vitalis_model_load_cancel_callback'),
      _requestCancel = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('vitalis_cancel_token_request'),
      _retainCancelToken = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('vitalis_cancel_token_retain'),
      _isCancelRequested = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('vitalis_cancel_token_is_requested'),
      _isCancelAcknowledged = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('vitalis_cancel_token_is_acknowledged'),
      _destroyCancelToken = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('vitalis_cancel_token_destroy'),
      _setContextCancelToken = library
          .lookupFunction<
            ffi.Void Function(
              ffi.Pointer<llama_context>,
              ffi.Pointer<ffi.Void>,
            ),
            void Function(ffi.Pointer<llama_context>, ffi.Pointer<ffi.Void>)
          >('vitalis_context_set_cancel_token'),
      _clearContextCancelToken = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<llama_context>),
            void Function(ffi.Pointer<llama_context>)
          >('vitalis_context_clear_cancel_token');

  final void Function() _silenceLogs;
  final ffi.Pointer<ffi.Void> Function() _acquireModelRead;
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>) _acquireModelFileRead;
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>)
  _acquireModelFileMutation;
  final ffi.Pointer<ffi.Void> Function() _acquireModelMutation;
  final void Function(ffi.Pointer<ffi.Void>) _releaseModelAccess;

  static String modelFileIdentity(String path) {
    var identity = p.normalize(p.absolute(path));
    try {
      identity = File(identity).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Never treat an unresolved existing file/link as unrelated. A missing
      // target uses its resolved parent so aliases still share one identity.
      if (File(identity).existsSync() || Link(identity).existsSync()) rethrow;
      identity = p.join(
        File(identity).parent.resolveSymbolicLinksSync(),
        p.basename(identity),
      );
    }
    return Platform.isWindows ? identity.toLowerCase() : identity;
  }

  ffi.Pointer<ffi.Void> _acquireFile(
    String path,
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>) acquire,
  ) {
    final pointer = modelFileIdentity(path).toNativeUtf8();
    try {
      return acquire(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  ffi.Pointer<ffi.Void> acquireModelRead({String? modelPath}) =>
      modelPath == null
      ? _acquireModelRead()
      : _acquireFile(modelPath, _acquireModelFileRead);
  ffi.Pointer<ffi.Void> acquireModelMutation({String? modelPath}) =>
      modelPath == null
      ? _acquireModelMutation()
      : _acquireFile(modelPath, _acquireModelFileMutation);
  void releaseModelAccess(ffi.Pointer<ffi.Void> lease) =>
      _releaseModelAccess(lease);
  final int Function() _beginBackendInitialization;
  final void Function(int) _finishBackendInitialization;
  final int Function() _isBackendInitialized;
  final ffi.Pointer<ffi.Void> Function() _createCancelToken;
  final ffi.Pointer<ffi.Void> Function() _modelLoadCancelCallback;
  final void Function(ffi.Pointer<ffi.Void>) _requestCancel;
  final void Function(ffi.Pointer<ffi.Void>) _retainCancelToken;
  final int Function(ffi.Pointer<ffi.Void>) _isCancelRequested;
  final int Function(ffi.Pointer<ffi.Void>) _isCancelAcknowledged;
  final void Function(ffi.Pointer<ffi.Void>) _destroyCancelToken;
  final void Function(ffi.Pointer<llama_context>, ffi.Pointer<ffi.Void>)
  _setContextCancelToken;
  final void Function(ffi.Pointer<llama_context>) _clearContextCancelToken;

  void silenceLogs() => _silenceLogs();

  bool beginBackendInitialization() => _beginBackendInitialization() != 0;

  void finishBackendInitialization({required bool success}) =>
      _finishBackendInitialization(success ? 1 : 0);

  bool get isBackendInitialized => _isBackendInitialized() != 0;

  ffi.Pointer<ffi.Void> createCancelToken() => _createCancelToken();

  llama_progress_callback get modelLoadCancelCallback =>
      _modelLoadCancelCallback()
          .cast<ffi.NativeFunction<llama_progress_callbackFunction>>();

  void requestCancel(ffi.Pointer<ffi.Void> token) => _requestCancel(token);

  void retainCancelToken(ffi.Pointer<ffi.Void> token) =>
      _retainCancelToken(token);

  bool isCancelRequested(ffi.Pointer<ffi.Void> token) =>
      _isCancelRequested(token) != 0;

  bool isCancelAcknowledged(ffi.Pointer<ffi.Void> token) =>
      _isCancelAcknowledged(token) != 0;

  void destroyCancelToken(ffi.Pointer<ffi.Void> token) =>
      _destroyCancelToken(token);

  void setContextCancelToken(
    ffi.Pointer<llama_context> context,
    ffi.Pointer<ffi.Void> token,
  ) => _setContextCancelToken(context, token);

  void clearContextCancelToken(ffi.Pointer<llama_context> context) =>
      _clearContextCancelToken(context);
}
