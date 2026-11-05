# Selected performance and resilience programme

The user reduced the programme on 5 November 2026 to **nine suites, 300 target cases**: four completed suites retain their 50 cases each, and five additional suites have 20 cases each. The three excluded suites are not required, not scheduled, and never labelled passed. Earlier attempts remain historical evidence.

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
| 9 | Volume | 20 | Production SQLite pagination and complete export with 100-10,000 multilingual messages; elapsed time includes dataset preparation and validation |

## Explicitly excluded

Smoothness, concurrency and cross-build regression are excluded at the user's request. Their previous definitions remain disabled in the catalogue for traceability. The executive workbook includes an **EXCLUDED SUITES** sheet and the JSON uses `USER_EXCLUDED`. Exclusion is not a pass, a failure, or proof that a capability is unsupported.

The workflow has no concurrency or regression workload jobs. Its volume job runs only the 20 production-storage cases and does not download an inference model. Its Android execution list contains only the four selected additional suites. The original five-suite programme is independent: each suite retains its minimum of 300 cases.

## Reusing completed results

`completed_run` imports the first four reports only after checking their successful GitHub jobs, matching run/source identity, passing unique case IDs, complete JSON/Excel row counts, unchanged product/native/build sources and relevant workload policies. Original report files keep their original source and run IDs. A separate provenance record says they were retained, not re-executed. This prevents wasting another 200 tests.

## Build and device identity

APK preparation verifies source equivalence, package identity and matching debug/profile certificates. The owned CI Android instance initializes the database with the debug APK, seeds 100 disposable saved chats without inventing model validation, then upgrades in place to the matching **profile APK**. Measurements use the profile APK.

Native ARM Android API 35 uses the pinned container, localhost-only ADB and an unrooted shell. Fixture writes require GitHub Actions, the localhost serial, Redroid hardware and the current run's Docker ownership label. Personal handsets and user data are not involved. An existing verified `performance-profile-pair` may be reused without another build.

## Results and policies

`catalogue.json` is the authority for enabled suites and minimum counts; `policy.json` defines bounded workloads. Diagnostic CI budgets are 5 seconds for destination readiness and 15 seconds for launch readiness, not production UX service-level objectives.

Every selected suite retains source/build identity, actual outcomes, measured samples, raw logs and Excel/CSV/HTML/JSON reports. Driver HTTP timings/counts are separate from UI timing. Native helper emission is not called visible TTFT. Missing evidence is BLOCKED, with no successful execution claimed.

Download **VITALIS-300-Case-Excel-Reports** from the volume-completion job for the final executive workbook, nine suite workbooks, explicit exclusions and raw evidence. The earlier **VITALIS-Performance-Resilience-Excel-Bundle** is the historical eight-suite snapshot. Reports remain downloadable on HOLD or failure. A selected-programme pass does not establish physical-phone, API-28, thermal, production-speed, long-duration leak-free or complete-security qualification.

## Final completion without restarting the active tests

The user added the 20-case volume suite to make exactly 300 target cases, and requested no further suites. `volume-completion.yml` lets the existing eight-suite run finish, executes only volume, then verifies and imports the eight original reports unchanged. It validates source equivalence, unique/passing counts, the prior reuse-provenance chain, and matching Excel rows. The final **VITALIS-300-Case-Excel-Reports** artifact contains the nine-suite executive workbook plus original raw evidence. The nested earlier summary is a historical eight-suite snapshot; the top-level summary is authoritative for the final 300-case programme.


## Complete consolidated download

[Download all test reports and the final assessment](https://github.com/Faizze-PI/Vitalis/actions/runs/41982786541/artifacts/13395115193) from the [successful packaging-only run](https://github.com/Faizze-PI/Vitalis/actions/runs/41982786541).

The artifact **VITALIS-All-Test-Reports-and-Final-Assessment** contains:

- `FINAL_ASSESSMENT.csv`, `.xlsx` and `.json`.
- `01_Behaviour_API_Security`: the original Selenium, Appium, BAS, DAST and load reports, unchanged.
- `02_Performance_300`: the final nine-suite, 300-case programme, unchanged.
- `TUNING_REGRESSION_SUBSET.csv`: 38 passing regression cases already included within BAS; these are not device-tuning benchmarks.
- `SHA256_INVENTORY.json`: hashes for the packaged files.

The total is **2,401 passing case records across 14 named suites**: 2,101 from the original programme plus 300 additional performance cases. Supporting root-test output, catalogues and the tuning subset are not counted again. Original source commits and execution run URLs remain in each report. The final assessment explicitly lists the three user-excluded suites and the unexecuted device-tuning benchmark.

Consolidation runs no application tests. This artifact was uploaded on 5 November 2026 with 30-day retention; download it before expiry. Its scoped passing results do not ratify the complete application or physical-phone performance.
