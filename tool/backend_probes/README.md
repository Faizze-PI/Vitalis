# Android backend feasibility probes

These probes do not enable new app capabilities. The production Native Assets
hook remains text-only until actual image encoding, inference, cancellation and
ownership tests pass. Dependencies here are candidates, not a supported-model list.

## Vision compilation

From the repository root, with the pinned NDK and CMake/Ninja available:

```powershell
./tool/backend_probes/run_mtmd_android.ps1 -AndroidSdk C:/Android/Sdk `
  -OutputDirectory D:/VITALIS/.cache/backend-probes/mtmd-new-run -Parallelism 4
```

Use a fresh output directory. The script verifies the existing source archive
against the native lock, extracts an independent source tree, and builds mtmd for
the ABI/API/NDK in the existing toolchain policy. It disables subprocesses, the
external-FFmpeg video helper, Vulkan, servers and examples. Result status is
`ANDROID_COMPILE_ONLY`; a successful build does not prove image inference.

Initial compile: locked b10727 produced AArch64 `libmtmd.so`, including
`mtmd_init_from_file`, `mtmd_tokenize`, `mtmd_encode` and `mtmd_helper_eval_chunks`.
Next: JNI/FFI probe, paired projector/base validation, real-image reference results,
and acknowledged projector-loading/encoder cancellation on Android.

## ONNX candidate

The locked candidate declares minSdk 24, includes arm64 libraries, and exposes
Java `RunOptions.setTerminate`. Its AAR also contributes a telemetry ContentProvider
and network permissions. Before any integration, remove its telemetry initializer,
disable environment telemetry, and test that no telemetry runs. Neither API-floor
declaration nor a Java signature proves Android execution or timely cancellation.

API-36 arm64 prototype execution now passes CSV/image references, pretrained
MobileNetV2 numerical comparison and native cancellation/recovery. See
`docs/features/onnx-prototype-validation.md`. API-28 execution, expanded lifecycle
and full release gates remain pending. No in-app training, Python execution or
model-supplied custom-op binaries are authorized.

## Tool calling

The vendored generic tool API is not proof of support: the persistent helper does
not currently receive tool schemas or preserve tool-call identity in its message
projection. Its generic executor also logs arguments/results. Do not enable it.
The explicit local CSV statistics tool is implemented and phone-tested, with no
model execution. It does not establish automatic tool calling.
Next: model-template schema/result round-trip tests, request-scoped typed parsing,
and a real model calling one explicitly registered local calculation tool. Do not
execute arbitrary model-provided function names or code.

Official references: [llama.cpp mtmd](https://github.com/ggml-org/llama.cpp/tree/ab0b3bd3c846839e9014c03b071f0f550a57ca84/tools/mtmd),
[ONNX mobile](https://onnxruntime.ai/docs/get-started/with-mobile.html),
[Java termination API](https://onnxruntime.ai/docs/api/java/ai/onnxruntime/OrtSession.RunOptions.html).
