# llm_llamacpp — VITALIS runtime fork

This vendored package is the platform-neutral llama.cpp text-inference adapter
used by VITALIS. It is not a general model downloader or a standalone product.
VITALIS owns model discovery, immutable revision resolution, GGUF validation,
downloads, installation, compatibility checks, and per-chat selection.

## Supported scope

- Local GGUF text generation through a persistent llama.cpp model/context.
- Native tokenizer and rendered chat-template budgeting.
- Request-scoped token, completion, cancellation, error, and metric events.
- Acknowledged native cancellation using llama.cpp's abort callback.
- Exact prompt-prefix/KV-cache reuse with rollback to a committed boundary.
- CPU on every supported production platform.
- Dynamically packaged Vulkan only when the platform branch enables it; CPU
  remains the automatic default and a failed Vulkan self-test falls back to a
  new CPU context.
- Android arm64, Windows x64, and Linux x64 build-hook targets. A target is not
  considered supported by VITALIS until its independent platform gate passes.

## Explicitly unsupported

- Image, audio, vision, or other multimodal input.
- Ollama-directory discovery or arbitrary host-directory scanning.
- Safetensors conversion, Python discovery, or prebuilt native downloads.
- Cloud inference or a network fallback.
- Unbounded GPU offload such as a fixed `nGpuLayers = 99` policy.

The runtime rejects messages containing images. GGUF metadata that mentions a
vision architecture does not make that model compatible with VITALIS.

## Native source authority

`native/llama_cpp.lock.json` is the only native dependency authority. The
Native Assets hook verifies the complete llama.cpp commit and archive SHA-256,
then builds the required llama/ggml libraries locally. Headers, bindings, and
binaries are checked together so an ABI drift fails the build.

Android builds use the pinned NDK and API from that lock. Desktop builds use
the same source lock; they never fetch an arbitrary DLL or shared object.

## Runtime use

VITALIS normally constructs `LlamaCppChatRepository.withModelPath` through its
`InferenceRuntime` adapter and supplies a validated runtime profile. Callers
must not infer tuning values from filenames or use the constructor defaults as
device recommendations.

Important operations exposed by the fork include:

- `prepare()` / persistent model initialization;
- `countChatTokens()` using the loaded tokenizer and template;
- `streamChatWithGenerationOptions()` with typed request events;
- `cancelActiveInference()` with native acknowledgement;
- `unloadPersistentModel()` and `dispose()`.

Normal logs redact prompt and model-path content. Applications should provide a
structured logger and keep verbose native logging disabled in release builds.

## Validation

The declared native product gate is:

```powershell
$env:VITALIS_TEST_MODEL = '<verified bundled GGUF path>'
dart test test/vitalis_text_runtime_gate_test.dart
```

The model must match the immutable bundled manifest. The gate has no skips and
proves real tokenization, visible generation with authoritative metrics, and
acknowledged cancellation followed by immediate recovery. See `test/README.md`
for the complete requirements.

Generic upstream examples and experimental integration fixtures are not
VITALIS release evidence. Platform ratification additionally requires packaged
binary inspection and physical runtime evidence.
