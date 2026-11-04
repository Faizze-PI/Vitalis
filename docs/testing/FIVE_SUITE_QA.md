# Five-suite behaviour and security programme

The workflow `.github/workflows/behaviour-qa.yml` tests the unchanged application. It creates separate Appium, Selenium/API, BAS, DAST and load jobs, then publishes a combined artifact. Each suite needs at least 300 executed checks and zero failures/skips before its own verdict can pass. A missing report, incomplete run or failed upstream job holds the combined verdict.

| Suite | Actual coverage | Important scope boundary |
|---|---|---|
| Appium | 300 combinations: 12 destination transitions, five font scales, five orientation/lifecycle conditions; accessible destination-content assertions | Saved-history / unavailable-model navigation compatibility, not every feature or native-model accuracy |
| Selenium/API | Six schema contracts for each of 50 actual public GGUF search records; direct status/content-type check; browser network evidence | 300 schema checks, two read-only public requests, not 300 independent network requests |
| BAS | Named adversarial, failure, lifecycle and preservation regressions from real VITALIS source tests; full root evidence retained | Application-level defensive simulations, not enterprise endpoint-agent BAS or a penetration-testing certificate |
| DAST | 300 running-APK external-intent fuzz scenarios: ten schemes, ten payload classes, three actions; private-service and file-isolation probes | Ingress non-crashing and isolation checks do not establish absence of all vulnerabilities |
| Load | 300 actual sequential UI action samples, success/failure counts, median/P95, screenshots/hierarchy, attributable crash buffer and captured app-log lines | Not concurrent users, model TTFT/throughput or target-phone performance |

## Reports

Reference files were downloaded from VITALIS run 41431985346 and Project-Ai-style run 41314622380. The retained workbook inventory is local under `D:/VITALIS/artifacts/qa-reference-20261104`. The reference layout contains SUMMARY, TEST RESULTS, module breakdowns and an executive summary. The new workbooks preserve those useful elements and include source, run URL, objective, prerequisites, steps, expected/actual result, status, timing, priority, evidence and scope. Failure severity requires triage and is not automatically labelled critical.

Every job uploads Excel, CSV, HTML, JSON and available raw evidence. The final **VITALIS-Test-Execution-Reports-Bundle** contains FINAL_TEST_SUMMARY.xlsx plus all individual artifacts. The established VITALIS core-300 catalogue is also executed/mapped by the BAS/root job; it is separate from the new per-suite counts.

## Android execution

The mobile jobs run the unchanged arm64 APK on native ARM Android API 35 using the pinned container described below. The earlier API-30 x86 translation attempt failed before Flutter rendered and is retained only as failed infrastructure evidence. No x86 production build or personal-phone change is introduced.

Appium listens only on localhost, without relaxed-security flags. All attack/fuzz/load traffic targets the disposable emulator or isolated fixtures. Hugging Face receives only bounded anonymous read-only checks, never attack or load traffic.

Official references: [Appium UiAutomator2](https://appium.github.io/appium-uiautomator2-driver/), [Selenium WebDriver](https://www.selenium.dev/documentation/webdriver/), [Android ARM emulator support](https://android-developers.googleblog.com/2020/03/run-arm-apps-on-android-emulator.html).

Status: implementation under test. No new workflow PASS is claimed until actual hosted execution and downloaded artifacts have been inspected.

## Disposable data prerequisites

Appium first checks that a fresh installation displays model setup. Navigation/load cases then use one saved-history fixture in the app-created database, with no model records or invented model validation. Fixture writes require GitHub Actions plus either a verified emulator identity or localhost native Android with the current run's Docker ownership label; the stopped database is checked, seeded, checkpointed and hash-verified before app restart. This exercises the supported saved-history / unavailable-model state. No personal handset or user database is touched.

Host execution explicitly includes both `test` and `test_benchmarks`; the latter contains three established core-300 cases. Failed completeness must preserve all completed case rows. Setup fallback writes a failure report only when no report already exists. The final bundle uses a non-hidden artifact directory so GitHub uploads failing as well as passing workbooks.

## Native ARM execution environment
The API-30 x86 translator crashed before Flutter rendered (SIGILL in libndk_translation). It is not accepted as application evidence. Mobile suites now use an immutable Redroid Android API-35 arm64 container on hosted ARM Linux. Startup was directly verified in run 41851996521. This is container-based functional evidence, not API-28 support, physical performance or security certification. ADB is localhost-only and unrooted (UID 2000). Host execution tools are Ubuntu ARM packages recorded in native-host-tools.log; the SDK-layout directory does not claim their version is Android build-tools 35. The APK retains its separately verified build provenance. Saved-history seeding requires the current run's Docker ownership label and refuses personal devices. Full suite results remain pending until this environment executes all cases.

Mobile reports also summarize actual local Appium HTTP request/response counts, HTTP error responses and median/P95 driver response duration from the retained appium.log. These are driver-transport measurements, separate from UI action timing, test failures, Hugging Face traffic and native-model performance. Expected element-lookup retries can return HTTP 404; they are counted rather than hidden.
