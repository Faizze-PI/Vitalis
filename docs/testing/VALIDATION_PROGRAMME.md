# VITALIS validation programme

This adapts a web/backend/mobile testing checklist to VITALIS: an offline Flutter
conversation app with Android and Windows previews, local SQLite storage,
llama.cpp inference and public Hugging Face model downloads.

## What applies

| Test area | VITALIS execution |
| --- | --- |
| Functional and UI | Chat, notes, personas, themes, settings, history, export, recovery and accessible controls through existing Flutter tests. |
| Persistence | CRUD, cursor pagination, historical schema upgrades, transaction rollback and installation projection. |
| Model library | Search states, bounded GGUF metadata, immutable artifacts, validation, activation and unavailable models. |
| Downloads | Range/ignored Range, retry, hashes, partial ownership and cancellation; Android scheduler behavior additionally needs instrumentation. |
| Native runtime | Real-model load/reuse, admission, cancellation, disposal, template, cache and recovery tests with the immutable verified fixture. |
| Safety and privacy | Unknown telemetry, safety decisions, redacted errors/logs, URL policy and scoped secret/dependency scans. |
| Load and endurance | Bounded host storage operations; separate physical single-user inference workload and resource measurements. |
| Compatibility | Android API-28 arm64, API-34+ UIDT and Windows x64 require their own evidence. |
| Build and regression | Source-linked Actions tests, architecture/dependency inspection and package checks. |

Selenium web tests and 100-user backend k6 traffic are not applicable: VITALIS has
no web frontend or inference server. Do not send load-test traffic to Hugging Face.
Use the existing Flutter integration tests and Android UiAutomator before adding
an unrelated Appium/WebDriver framework.

## Reporting rules

- Count actual test cases and preserve setup failures. Do not manufacture a target
  such as 1,100 tests through repeated assertions.
- Record monotonic timings. A runner duration of 0 ms is valid at its resolution.
  Never insert random durations or sleeps to improve the report.
- Report actual security findings and severity. Do not prescribe a score, finding
  count or absence of critical vulnerabilities before scanning.
- Distinguish test execution time, storage latency, inference TTFT and UI timing.
  Coverage/debug timings are not production performance evidence.
- Keep host, emulator, phone, source inspection and GitHub results separate.
  Never combine repeat runs or operating-system suites into a unique-case total.
- Generate reports even when tests fail, retain the original failure and leave
  unavailable measurements blank or explicitly blocked.

## Ordered execution

1. Record source/working changes, toolchain, test seed and fixture hashes.
2. Pass the required hosted Actions checks on the candidate and merged `main`.
3. Run host feature, migration, download-fault, privacy and safety suites. Export
   machine events for case names, outcomes and measured runner durations.
4. Run the opt-in storage benchmark below on disposable host fixtures.
5. Run the immutable-model native suite and the separate native fault suite.
   Collect vendored lifecycle coverage explicitly.
6. Run API-28 and API-34+ arm64 instrumentation on compatible infrastructure.
7. With an authorized phone, capture build/certificate/data identity and exercise
   real feature flows using disposable chats, notes, personas and models.
8. Run ten normal fixed inference requests plus separate cancellation/recovery
   cases. Capture visible/native timings, PSS, battery, thermal state and logs.
9. Review failures, add regressions, rebuild and repeat dependent checks. Ratify
   only when the defined gates pass; a report file is not a passing gate.

## Reproduction on the pinned host

Select the repository's documented Flutter/JDK/SDK and workspace-local caches
before invoking the managed launcher. Preserve each run in a new evidence path.

```powershell
./tool/run_gate.ps1 test --no-pub --machine --concurrency=1 --test-randomize-ordering-seed=20261027
./tool/run_gate.ps1 test test_benchmarks/host_storage_benchmark_test.dart --no-pub --machine --concurrency=1
```

The benchmark is outside `test/` so ordinary unit runs do not acquire a mandatory
60-second workload. It measures 100 sequential CRUD cycles, 100 concurrent reads
and 60 seconds of bounded paced reads. All records are disposable. Set
`VITALIS_VALIDATION_METRICS` to a fresh JSONL output path to retain numeric samples.
It emits operation count, errors, elapsed time, rate, minimum, mean, median, P95
and maximum. Pacing is excluded from per-read latency. These are host storage
measurements, not 100 app users or phone/model performance.

## Download reports from GitHub Actions

The required `Checks` workflow runs this programme in its Windows host job.
Open the completed Actions run and download **VITALIS-Excel-test-report-Windows**
from **Artifacts**. Its ZIP contains the Excel workbook, case CSV, HTML report,
JSON result, raw machine events and storage measurements. Retention is 30 days.
Reports are generated after failed tests too; a failed or incomplete report keeps
the required job failing. No reporting step changes a failure into a pass.

The report generator has negative tests for missing/duplicate events, invalid
metrics, fixture failures, skips and CSV formula injection. Its report-only
dependency is version- and SHA-256-pinned in `tool/reporting/requirements.txt`.

## Physical acceptance still required

- Correct themes, persona/note persistence, settings, full export and model flows
  on the installed build, not merely in simulated widget tests.
- Visible stop and native acknowledgement within two seconds, immediate recovery,
  no attributable crash/ANR/corruption/duplicate completion/stuck runtime.
- No throughput regression, no more than 15% post-cooldown PSS growth, and at least
  30% warm-TTFT improvement only against a valid comparable legacy baseline.
- Preserve user data and certificate checks. Never exhaust storage/memory, provoke
  overheating, uninstall or clear personal data as a test shortcut.

If no phone or compatible arm64 runner is available, those checks remain blocked.
Public reports must exclude personal captures, model paths and credentials.
