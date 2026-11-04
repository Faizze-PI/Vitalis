# Windows algorithms validation — 2026-11-04

Scope: add the existing algorithm-package, CSV and RGB-image workflow to Windows CPU. This is a testing preview, not whole-product Windows ratification.

| Check | Observed result |
|---|---|
| Native C++ engine | CSV sums and RGB means passed; path identity, missing file, pre-cancellation, hash mismatch and shape mismatch rejected |
| Two public image fixtures | Maximum absolute differences from Colab reference: 4.36557e-11 and 0; tolerance 1e-4 |
| Flutter Windows integration | One real integration case passed package import and native-channel CSV/image execution; owned test records removed afterward |
| Root regressions | 1,512 passed, randomized seed 20261104 |
| Changed Dart formatting | Passed |
| Windows release build | Passed after correcting the ONNX install destination; repeat packaging build required after the integration runner |
| Whole-project analysis | Inconclusive: analyzer did not finish; only the audit-owned language server was stopped, and failed output retained |
| Portable installation | Pending package inspection and launch; recorded separately in local installation evidence |

Runtime: Microsoft ONNX Runtime CPU 1.24.4 on Windows. Android is unchanged. Official archive/header hashes are in windows/onnxruntime/dependency.lock.json. Native DLLs and upstream notices ship with the complete application; no Python installation is required.

Local raw evidence is under D:/VITALIS/artifacts/custom-tasks/windows-native-20261104. Test sources are windows/tests/onnx_task_engine_test.cpp and integration_test/windows_algorithms_test.dart. The portable bundle verifier checks x64 dependencies and OrtGetApiBase, rejects model payloads, and requires the additional MSVCP140_1 dependency discovered in the actual ONNX DLL import table.

Limitations: active-decode cancellation stress, every possible exported operator/model, broader Windows product acceptance and performance ratification are not established by these checks. The two classifier samples demonstrate execution parity, not medical accuracy.
