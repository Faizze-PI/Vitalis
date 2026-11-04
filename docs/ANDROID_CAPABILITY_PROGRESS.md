# Android capability implementation

Updated 4 November 2026. Status applies to the expanded attachment/vision/tool/ONNX
programme, not to the already implemented text-chat application.

Working-first update: the user prioritized local files and custom algorithms.
The local workspace now has import/storage, text previews and removal implemented
with focused tests and OPPO verification. Conversation TXT/CSV attachments now
persist in schema 9; exact TXT retrieval, restart persistence, deletion guards
and unsupported-image rejection passed on build `f47d2be`. CSV arithmetic failed
(6 instead of 5), and preparation Stop was fixed and phone-retested on `c5ad968` (timing remains
unmeasured). A numeric ONNX/CSV reference graph passed on the development
host and on the OPPO through the actual import/Run screens. CSV and image outputs
match their references. Four JVM checks and four native phone tests pass; files
survive explicit force-stop/relaunch, and wrong-input recovery passes. See
[the file/task slice](features/local-files-and-custom-tasks.md).

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
| 1. Backend compatibility | In progress | ONNX CSV/image and pretrained MobileNetV2 execution proved on API-36 arm64 phone. Native cancellation to worker termination measured 12.056 ms in one bounded Loop test. GGUF vision encoding and tools round trip remain unproven. |
| 2. Capability/storage contracts | Partial | Additive schema 9 chat-file references; existing table/workspace fingerprints preserved across upgrade. Multimodal capabilities remain pending. |
| 3. File attachments | Text path phone-tested | TXT grounding, persistent TXT/CSV chat associations, attached-file deletion guard and unsupported-image rejection pass. CSV arithmetic failed; image previews/decoders remain pending. |
| 4. Complete model bundles | Not started | Candidate base/projector pair is hash-pinned for probes; app imports still support text GGUF only. |
| 5. Vision inference | Not started | A compiled library is not image inference. |
| 6. PDF/OCR/citations | Not started | Requires bounded extraction and qualified offline OCR. |
| 7. Controlled local tools | Explicit CSV tool phone-tested | Column count/sum/min/max/mean, invalid-column retry and header validation pass. Automatic model schema/call/result round trip remains pending; generic vendored executor stays disabled. |
| 8. Colab ONNX imports | Working local prototype | Task JSON binds model hash and preprocessing. CSV/image references and real pretrained MobileNetV2 run through phone UI. First 64 MobileNet scores numerically compared; accuracy and additional Colab exports still need qualification. |
| 9. Video frames | Not started | External-FFmpeg mtmd video helper remains disabled. |
| 10. Combined safety/recovery | Partial | Shared leases, late-result rejection, wrong-input recovery, native Loop cancellation and subsequent CSV inference pass. UI Stop timing, active-task safety/lifecycle and GGUF/ONNX switching need physical tests. |
| 11. Expanded Android qualification | Prototype scope tested | Root 1,488 pass at CSV checkpoint; clean analysis; historical JVM 4 pass and native phone 4 pass; CSV/image/pretrained UI runs pass. Full API-28/emulator/release/performance qualification remains incomplete. |

Probe instructions and candidate locks are in `tool/backend_probes`. Binaries and
large fixtures remain outside Git. ONNX 1.31.1 is now an Android dependency;
its telemetry initializer is removed from the merged debug manifest and runtime
telemetry is explicitly disabled. Keep CPU default, local inference, protected
data, Provider, API 28/arm64 and the existing signing boundaries. No fine-tuning,
arbitrary imported code, desktop rollout or publication is part of this stage.

Model-dependent requirement: vision/tools must be derived from the selected
verified bundle and runtime. LFM3-Omni-2B currently requires a newer native backend
than the locked b10727; see [capability requirements](features/model-dependent-capabilities.md).
Image-preview build f018cec: full root 1,492 passed; PNG preview physically
verified on OPPO. JPEG decoding is host-tested, not yet physically verified.

Algorithm retest at e89a501: CSV/image references and repeated image execution
pass; MobileNet first64 agrees within 7.704e-6. A stale-result display bug was
fixed and physically retested. Root 1,493 pass and analysis clean. Newer backend
upgrade is deferred by the user; existing ONNX execution is independent of it.

Simplified algorithm packages: transactional ZIP store foundation implemented
and tested (1,504 root pass; 11 focused; analysis clean). Package picker/library,
native runner integration and phone validation remain pending. The installed
APK still uses the separate-file custom-task flow.
