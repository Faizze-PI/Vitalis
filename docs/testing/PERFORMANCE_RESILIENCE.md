# Ordered performance and resilience tests

This is a separate GitHub Actions programme from the five 300-case suites. Its catalogue defines **50 cases per suite, 600 declared cases total**. Repeated measurements are labelled samples, not unique application features. No app functionality is changed.

## Execution order and evidence

| Order | Suite | Actual workload and scope |
|---|---|---|
| 1 | Latency | 50 profile-APK navigation samples, measured until destination content is accessible; median/P95/P99 derivable from raw samples |
| 2 | Throughput | 50 real hash-verified Qwen CPU generations on the hosted Linux runner; native token counts and generation time, not Android model speed |
| 3 | Stress | 50 combinations of 100-2,000 stored messages and concurrent history reads through the production database helper |
| 4 | Spike | 50 bursts of 2-51 simultaneous production model-file reservation attempts; busy rejection and subsequent recovery; no external API load |
| 5 | Endurance | 50 paced profile-APK cycles, at least 12 seconds each: a bounded ten-minute soak with PSS samples and cooldown, not multi-hour endurance |
| 6 | Startup | 25 stopped-process starts and 25 background resumes; Android launch timing separately from accessible Flutter readiness |
| 7 | Smoothness | 50 scroll journeys; retained Android window frame statistics. Missing samples are BLOCKED. These do not replace Flutter engine build/raster traces |
| 8 | Resources | 50 complete process-memory/CPU snapshots during UI activity. Container battery/thermal data cannot establish physical battery or temperature behaviour |
| 9 | Recovery | 50 lifecycle cases: short/long background, explicit force-stop/relaunch, portrait and landscape; preserved saved-content visibility. Force-stop is labelled separately from ordinary process death |
| 10 | Volume | 50 cases with 100-10,000 messages, multilingual payloads, complete export and contiguous pagination via production database methods |
| 11 | Concurrency | 50 real-model ownership cases: competing prepare/cancel/unload rejection, alternating cancellation/completion races and continued reuse |
| 12 | Regression | 50 paired latency comparisons against an explicitly supplied earlier matching performance run; missing or incompatible baseline means 50 BLOCKED comparisons |

Dependencies serialize these groups in the stated order. A failed suite does not suppress safe independent later fixtures. Shared groups run their suites serially. User data and personal devices are never involved.

## Android identity and build mode

Default APK source is the retained `android-verification-apks` artifact from run 41849803536. Preparation verifies its source against all application/build/dependency files, checks package identity, and requires matching debug/profile certificates. The temporary CI Android instance first initializes its database with the debug APK, seeds 100 explicitly disposable saved chats without inventing model validation, then upgrades in place to the matching **profile APK**. Every measurement uses that profile APK.

Native ARM Android API 35 uses the pinned container and localhost-only, unrooted ADB. Fixture writes require GitHub Actions, the localhost serial, Redroid hardware, and the current run's Docker ownership label. No personal handset can pass this guard.

## Policies and verdicts

`tool/perf/policy.json` is the workload authority. Initial CI diagnostic budgets are 5 seconds for destination readiness and 15 seconds for launch readiness. They are deliberately documented CI limits, not production UX service-level objectives. Stress and volume are bounded, isolated datasets; no deliberate physical overheating or disk exhaustion occurs.

All suites retain source/build identity, actual case outcomes, measured samples, raw logs and Excel/CSV/HTML/JSON reports. Appium transport timings and request counts are labelled separately from UI timings. Native helper emission timing is not called visible TTFT. Real-model tests require the publisher-known SHA-256 fixture and fail rather than skip when unavailable.

A missing measurement is **BLOCKED**, with zero successful execution claimed. The original 300-case suites keep their 300 minimum; only this catalogue requests 50. Report-integrity checks reject inconsistent case counts and malformed results. The combined workbook remains downloadable on HOLD or failure.

Passes establish only the listed assertion/measurement scope. There is no physical-phone, production-speed, thermal, API-28, long-duration leak-free, or complete-security ratification from this programme.

## Baseline and downloads

Run **Performance and resilience - 50 cases per suite** from Actions. Optional `baseline_run` must reference an earlier run containing the same named latency workload, profile build mode, Android/container/device configuration and complete passing samples. No previous debug or unrelated 300-action result is silently reused as a comparable baseline.

Download **VITALIS-Performance-Resilience-Excel-Bundle** from the final job for the executive workbook, twelve suite workbooks, and raw evidence. Host/component and Android measurements remain distinguishable. A missing baseline holds the overall programme even if all runnable suites pass.
