# Windows CPU preview

The official Flutter x64 runner retains Provider, the model registry, GGUF validation, native runtime and database schema. Native Assets compiles the existing locked llama.cpp source. CPU is the only packaged inference backend.

Windows initializes sqflite_common_ffi inside the observable startup database task. New databases, imported models, default downloads and logs use application support. Android locations are retained. Windows memory, low-memory, power and disk readings use SDK APIs; thermal and performance-core classification remain unknown and tuning stays conservative. Downloads use the shared foreground transfer adapter and recover persisted partial work at restart; Android background-service guarantees do not apply.

JNI arrives only through the Android path_provider adapter. Windows uses the Win32 implementation. Windows CMake therefore disables discovery of the unused JNI bridge, retaining the Android-tested lockfile instead of shipping a Java dependency. The bundle verifier rejects dartjni.dll, jvm.dll and unresolved non-system dependencies. An earlier targeted JNI upgrade was superseded after the bundle audit exposed its JVM dependency. Packaging follows the completed CMake install manifest to exclude stale output files without deleting them.

The release folder must be packaged in full with SQLite, C++ runtime dependencies and licences using tool/package_windows_preview.ps1 after source checkpointing. A portable ZIP is a testing preview, not formal Windows ratification. Actual UI and native inference acceptance remains in progress. Linux and Vulkan are deferred.

## Retained checks

- Root analysis passed; 1,402 root tests passed with seed 20261028.
- Hardcode verifier passed with 76 registered dispositions; its scope is not a whole-project proof.
- The immutable bundled-model registry/ownership gate passed on Windows, including competing-owner rejection and acknowledged shutdown.
- Release build passed; inspected application/native DLLs are x64 and the main EXE is positively unsigned.
- Actual Windows UI opened the library, imported and probed the model, retained its model/chat across restart, and completed a local greeting. The source fixes for import progress and first-chat navigation are regression-tested; packaged-app retesting is next.

Formal Windows CPU ratification, broad transfer fault/integration acceptance and performance comparisons remain incomplete. The Android 1.0.1 APK is delivered separately; Windows changes do not retroactively qualify that APK.

## Local algorithms (2026-11-04)

The Windows adapter now implements the same `vitalis/custom_tasks` contract as Android. The existing Files and algorithms screens import algorithm ZIPs and run concrete float32 CSV or RGB image inputs. CPU ONNX Runtime 1.24.4 is bundled from a SHA-256-locked official Microsoft distribution; end users do not need Python. Matching C++ headers and third-party notices are locked and packaged.

The native test passed CSV sums, RGB preprocessing, invalid hash/shape rejection, pre-cancellation, and two-image Colab reference parity. A real Flutter Windows integration test passed package import plus CSV and image execution over the native channel. These scoped results do not qualify every ONNX model, medical accuracy, or the entire Windows product. See [ONNX explanation](onnx-algorithms-explained.md).

For a repeatable application-channel test, generate fixtures with `tool/custom_tasks/export_reference_tasks.py`, then use the managed launcher to run `flutter test integration_test/windows_algorithms_test.dart -d windows --dart-define=VITALIS_TASK_FIXTURES=<absolute-fixture-directory>`. The test creates and removes only its own package/input records. Tests require fixtures; no fixture-related skip is allowed.
