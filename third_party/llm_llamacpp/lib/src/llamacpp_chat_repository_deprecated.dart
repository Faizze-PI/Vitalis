part of 'llamacpp_chat_repository.dart';

void _initializeBackendImpl(LlamaCppChatRepository repo) {
  final runtime = PersistentInferenceIsolate.instance;
  if (!runtime.canAccess(repo._runtimeOwner)) throw InferenceRuntimeBusy();
  final snapshot = runtime.operationSnapshot;
  if (snapshot.requiresRecovery) throw InferenceRecoveryRequired();
  if (snapshot.hasNativeWork || snapshot.initializationPending) {
    throw InferenceRuntimeBusy();
  }
  if (repo._backendInitialized) return;

  final result = BackendInitializer.initializeBackend();
  repo._bindings = result.$2;
  repo._backendInitialized = true;
}

Future<void> _loadModelImpl(
  LlamaCppChatRepository repo,
  String modelPath, {
  ModelLoadOptions options = const ModelLoadOptions(),
}) async {
  _initializeBackendImpl(repo);

  if (repo._model != null && repo._ownsModel) {
    repo._model!.dispose();
    repo._model = null;
  }

  repo._model = LlamaCppModel.load(
    modelPath,
    repo._bindings!,
    nGpuLayers: options.nGpuLayers,
    useMemoryMap: options.useMemoryMap,
    useMemoryLock: options.useMemoryLock,
    vocabOnly: options.vocabOnly,
  );
}

void _unloadModelImpl(LlamaCppChatRepository repo) {
  if (repo._model != null && repo._ownsModel) {
    repo._model!.dispose();
    repo._model = null;
  }
}
