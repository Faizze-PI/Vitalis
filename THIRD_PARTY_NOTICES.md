# Third-party notices

The top-level Apache-2.0 licence applies to original VITALIS application work. It does not relicense separately licensed dependencies or model weights.

| Component | Location / authority | Terms |
|---|---|---|
| Modified llm_llamacpp package | `third_party/llm_llamacpp` | MIT; retain its complete `LICENSE` and source notices |
| llama.cpp / GGML / template engine | Hash-locked revision in `third_party/llm_llamacpp/native/llama_cpp.lock.json` | Retain upstream licences and the vendored package's native notices |
| JSON for Modern C++ | Identified in the vendored native notices | MIT; retain Niels Lohmann attribution |
| Flutter, Dart and Pub dependencies | `pubspec.lock` and vendored `pubspec.lock` | Each dependency's own licence; preserve generated dependency notices when distributing a binary |
| Gradle wrapper | `android/gradle/wrapper` and wrapper sources/distribution | Upstream Gradle terms and notices |
| GGUF model weights | Downloaded separately, not included | Each publisher's model licence and access conditions |

VITALIS modifications include persistent runtime ownership/cancellation, native bridge and Native Assets packaging, template/context handling, local model validation and Android integration. Existing upstream notices remain in place.

Before distributing application binaries, verify the generated dependency notices and licences for the exact locked build. This source preview is not a complete binary-distribution compliance certificate.

Windows preview packages also include the SQLite runtime supplied by the locked sqflite_common_ffi package (SQLite public-domain terms and the package licence) and Microsoft Visual C++ redistributable DLLs from the installed build tools (Microsoft redistribution terms). Generated Flutter dependency notices and native upstream licences accompany the portable package.

Algorithm package import uses archive 4.6.0 (MIT; Brendan Duncan attribution)
and its locked posix dependency. Preserve their generated Flutter licence notices
with distributed builds; model-package weights retain their own publisher terms.

Windows algorithm execution includes Microsoft's ONNX Runtime 1.24.4 CPU DLLs (MIT). The official distribution and matching headers are SHA-256 locked in windows/onnxruntime/dependency.lock.json. Its LICENSE and ThirdPartyNotices.txt are included under licenses/onnxruntime in the portable bundle. No Python runtime or model weights are bundled.
