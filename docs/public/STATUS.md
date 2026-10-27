# Preview status

## Verified host evidence — 28 October 2026

At source `cf3635008773a5a14d0a4d8daf7106349c733a87`, all five required
[Checks jobs passed](https://github.com/Faizze-PI/Vitalis/actions/runs/40578324390):

| Check | Observed result |
|---|---|
| Root tests, Linux | 1,391 passed; seed `20261027` |
| Root tests, Windows | 1,403 passed; seed `20261027` |
| Immutable-model text runtime | 4 passed |
| Real-model registry/ownership | 1 passed |
| Adapted validation programme | 574 passed, zero failed/skipped |
| Core report | 300 distinct cases selected from those 574 |
| Builds | Android arm64 debug/profile and inspected Windows portable package passed |

Download the [Excel report bundle](https://github.com/Faizze-PI/Vitalis/actions/runs/40578324390/artifacts/12768657498)
from that run. It includes both workbooks, JSON, CSV, HTML and raw measurements;
artifact retention is 30 days. The two workbooks were checked against their JSON
results, including every result row, duration and source identity. Platform runs
overlap, and the 300 core cases are a subset: these counts are not additive.
See the [validation programme](../testing/VALIDATION_PROGRAMME.md) and
[VITALIS QA prompt](../testing/VITALIS_QA_EXECUTION_PROMPT.md).

Separately, at checkpoint `3f0736634c34ac828510aedb754c82708400bbc3`, the complete
partitioned root coverage, 82 normal native tests and nine isolated cleanup-fault
tests pass all 72 designated risk-file thresholds. Overall line coverage across
the 167 measured production sources is 77.47%; that is distinct from the
per-file 80%/90% requirements. No branch-coverage percentage is claimed. The app,
vendored runtime, native tests and coverage verifier are unchanged at `cf363500`.
This source-equivalence check is not a fresh full-suite execution at that newer
commit. The single-invocation Windows collector failure remains unexplained;
[coverage qualification remains open](https://github.com/Faizze-PI/Vitalis/issues/1).

## Android 1.0.1

- Refreshed identity and conversation-focused navigation.
- Separate app and per-chat settings, with validated numeric controls.
- Arm64 profile APK built with non-production debug signing.
- Retained scoped OPPO checks: in-place installation succeeded and nine checked database tables matched before/after. Chat settings and the numeric editor opened; cancelling that editor preserved the setting. These are historical observations, not a fresh phone acceptance run.

These are scoped checks, not production ratification. Clean-build/release,
support-floor and UIDT arm64 instrumentation, durable-transfer, performance and
complete physical acceptance gates remain open. Neither a green hosted workflow
nor a built instrumentation APK substitutes for on-device execution.
Observed build-tool warnings and their review status are tracked in the
[warning register](../testing/BUILD_WARNINGS.md).

## Windows 1.0.1 preview

The official Flutter x64 runner uses the existing CPU Native Assets backend.
Current scoped host test/build results are listed above. Retained desktop checks
also include importing and validating Qwen, saved chat/model state across restart,
and a local greeting. Import progress and first-chat navigation have focused
regressions. The complete portable folder includes SQLite and C++ runtime
dependencies. The preview ZIP passed dependency/symbol/payload checks, loaded its
DLLs with Java removed from the test environment, and opened saved chats outside
the development repository. The Android-only JNI bridge is excluded; users do not
need Java.

This is a testing preview, not formal platform ratification. Full desktop transfer fault/integration coverage, performance characterization and cross-machine testing remain open. Windows 11 was exercised; other supported Windows configurations remain unverified. Android-specific background download guarantees do not apply to desktop foreground transfers.

Linux and Vulkan remain deferred.
