# Selected performance and resilience programme

The user reduced the programme on 5 November 2026 to **eight suites, 280 target cases**: four completed suites retain their 50 cases each, and four additional suites have 20 cases each. The four excluded suites are not required, not scheduled, and never labelled passed. Earlier attempts remain historical evidence.

## Selected suites

| Order | Suite | Cases | Actual scope |
|---|---|---:|---|
| 1 | Latency | 50 retained | Profile-APK navigation until accessible destination content; original timings and request logs retained |
| 2 | Throughput | 50 retained | Real hash-verified Qwen CPU generations on the hosted Linux runner; native token counts and generation time, not Android model speed |
| 3 | Stress | 50 retained | Production database helper with 100-2,000 messages and concurrent history reads |
| 4 | Spike | 50 retained | Bursts of production model-file reservation attempts; correct busy rejection and subsequent recovery |
| 5 | Endurance | 20 | Paced profile-APK cycles, at least 12 seconds each: a bounded four-minute diagnostic soak, PSS snapshots and cooldown; not multi-hour endurance |
| 6 | Startup | 20 | Ten stopped-process starts and ten background resumes; Android launch time separately from accessible Flutter readiness |
| 7 | Resources | 20 | Complete process-memory/CPU snapshots during UI activity; container battery/thermal values do not establish physical energy or temperature behaviour |
| 8 | Recovery | 20 | Short/long background, explicit force-stop/relaunch, portrait/landscape and preserved saved-content visibility; force-stop is not ordinary process death |

## Explicitly excluded

Smoothness, volume, concurrency and cross-build regression are excluded at the user's request. Their previous definitions remain disabled in the catalogue for traceability. The executive workbook includes an **EXCLUDED SUITES** sheet and the JSON uses `USER_EXCLUDED`. Exclusion is not a pass, a failure, or proof that a capability is unsupported.

The workflow has no host-late or regression workload jobs. Its Android execution list contains only the four selected additional suites. The original five-suite/300-case programme is independent and keeps its original thresholds.

## Reusing completed results

`completed_run` imports the first four reports only after checking their successful GitHub jobs, matching run/source identity, passing unique case IDs, complete JSON/Excel row counts, unchanged product/native/build sources and relevant workload policies. Original report files keep their original source and run IDs. A separate provenance record says they were retained, not re-executed. This prevents wasting another 200 tests.

## Build and device identity

APK preparation verifies source equivalence, package identity and matching debug/profile certificates. The owned CI Android instance initializes the database with the debug APK, seeds 100 disposable saved chats without inventing model validation, then upgrades in place to the matching **profile APK**. Measurements use the profile APK.

Native ARM Android API 35 uses the pinned container, localhost-only ADB and an unrooted shell. Fixture writes require GitHub Actions, the localhost serial, Redroid hardware and the current run's Docker ownership label. Personal handsets and user data are not involved. An existing verified `performance-profile-pair` may be reused without another build.

## Results and policies

`catalogue.json` is the authority for enabled suites and minimum counts; `policy.json` defines bounded workloads. Diagnostic CI budgets are 5 seconds for destination readiness and 15 seconds for launch readiness, not production UX service-level objectives.

Every selected suite retains source/build identity, actual outcomes, measured samples, raw logs and Excel/CSV/HTML/JSON reports. Driver HTTP timings/counts are separate from UI timing. Native helper emission is not called visible TTFT. Missing evidence is BLOCKED, with no successful execution claimed.

Download **VITALIS-Performance-Resilience-Excel-Bundle** from the final job for the executive workbook, eight suite workbooks, explicit exclusions and raw evidence. Reports remain downloadable on HOLD or failure. A selected-programme pass does not establish physical-phone, API-28, thermal, production-speed, long-duration leak-free or complete-security qualification.
