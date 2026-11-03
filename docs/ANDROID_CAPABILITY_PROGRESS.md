# Android capability implementation

Updated 3 November 2026. Status applies to the expanded attachment/vision/tool/ONNX
programme, not to the already implemented text-chat application.

Foundation correction `1cb3d25`: acknowledged Stop preserves admitted partial text
through the existing response-save path; follow-up admission waits for pending
persistence; conversation changes clear the old context warning. The reproductions
failed before the changes. Verification: 50 focused tests, 246 provider-suite tests
(before the final two negative edge cases), and 1,423 full root tests with seed
20261103 passed. Focused analysis and formatting passed. A new-build phone retest
is still required; the phone results from the preceding build do not close these
two defects physically.

| Step | State | Evidence / next required result |
|---|---|---|
| 1. Backend compatibility | In progress | Locked mtmd compiled for API 28/arm64, exported image-processing symbols inspected. ONNX AAR/Java/minSdk/native dependencies inspected. Actual image encoding, tools round trip, ONNX execution and cancellation remain unproven. |
| 2. Capability/storage contracts | Not started | Depends on backend proof; preserve the existing version-8 database. |
| 3. File attachments | Not started | Existing attached notes are not file attachments. |
| 4. Complete model bundles | Not started | Candidate base/projector pair is hash-pinned for probes; app imports still support text GGUF only. |
| 5. Vision inference | Not started | A compiled library is not image inference. |
| 6. PDF/OCR/citations | Not started | Requires bounded extraction and qualified offline OCR. |
| 7. Controlled local tools | Not started | Generic vendored executor is not enabled as a product capability. |
| 8. Colab ONNX imports | Not started | Requires explicit task manifests and reference-result comparisons. |
| 9. Video frames | Not started | External-FFmpeg mtmd video helper remains disabled. |
| 10. Combined safety/recovery | Not started | Existing text-runtime tests cannot prove multimodal cancellation. |
| 11. Expanded Android qualification | Not started | Existing text-app results do not qualify unimplemented capabilities. |

Probe instructions and candidate locks are in `tool/backend_probes`. Binaries and
large fixtures remain outside Git. ONNX 1.31.1 contributes a telemetry initializer;
it has not been added to the application. Remove that initializer and disable and
verify telemetry before integration. Keep CPU default, local inference, protected
data, Provider, API 28/arm64 and the existing signing boundaries. No fine-tuning,
arbitrary imported code, desktop rollout or publication is part of this stage.
