# Windows algorithms validation — 2026-11-04

Scope: add the existing algorithm-package, CSV and RGB-image workflow to Windows CPU. This is a testing preview, not whole-product Windows ratification.

| Check | Observed result |
|---|---|
| Native C++ engine | CSV sums and RGB means passed; path identity, missing file, pre-cancellation, hash mismatch and shape mismatch rejected |
| Two public image fixtures | Maximum absolute differences from Colab reference: 4.36557e-11 and 0; tolerance 1e-4 |
| Flutter Windows integration | One real integration case passed package import and native-channel CSV/image execution; owned test records removed afterward |
| Root regressions | 1,512 passed, randomized seed 20261104 |
| Changed Dart formatting | Passed |
| Windows release build | Passed again from checkpoint adaf31f after the integration runner |
| Whole-project analysis | Fresh Dart whole-repository analysis passed; managed Flutter analysis rerun passed with no issues in 11.0 seconds; earlier stalled run retained |
| Portable installation | Bundle passed x64/dependency/symbol/payload/unsigned checks across 17 PE files; all 42 installed files hash-matched; installed app visibly rendered the Algorithms screen |
| Hardcode register | Passed with 83 dispositions |

Runtime: Microsoft ONNX Runtime CPU 1.24.4 on Windows. Android is unchanged. Official archive/header hashes are in windows/onnxruntime/dependency.lock.json. Native DLLs and upstream notices ship with the complete application; no Python installation is required.

Local raw evidence is under D:/VITALIS/artifacts/custom-tasks/windows-native-20261104. Test sources are windows/tests/onnx_task_engine_test.cpp and integration_test/windows_algorithms_test.dart. The portable bundle verifier checks x64 dependencies and OrtGetApiBase, rejects model payloads, and requires the additional MSVCP140_1 dependency discovered in the actual ONNX DLL import table.

Three actual ONNX Loop executions were cancelled after their native run options were attached and a further 20 ms elapsed. All returned cancelled, cleared native run-option ownership, and joined within the same whole-millisecond interval as the cancellation request (reported 0 ms; this is timer granularity, not zero physical latency). An immediate CSV request then succeeded. The subprocess had a 30-second external test timeout.

Limitations: broader UI cancellation stress, every possible exported operator/model, broader Windows product acceptance and performance ratification are not established by these checks. The two classifier samples demonstrate execution parity, not medical accuracy.

The local installation is `%LOCALAPPDATA%/Programs/VITALIS/1.0.1-algorithms-adaf31f`. Desktop and Start menu shortcuts point to it. The previous installation was preserved. Raw installation identity and package inspection remain local; saved user data was not cleared. UI rendering establishes launch readiness, not exhaustive Windows acceptance.

Cancellation test fixtures are generated separately with `python tool/custom_tasks/export_cancellation_fixture.py <fixture-directory>` after the normal reference fixture exporter. The intentionally long, low-memory Loop fixture is for controlled cancellation tests only; never run it interactively without native cancellation. The standalone CMake test enforces a 30-second timeout.

The standalone MSVC CMake build and CTest suite passed (1/1 suite, 0.43 seconds total). That suite includes the three cancellation cycles, immediate CSV recovery and the RGB reference check. This is one suite containing multiple assertions, not an inflated count of separate tests.
