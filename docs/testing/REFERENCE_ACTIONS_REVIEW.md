# Actions reference review and implementation order

Reviewed 2026-10-29. Reference source: `krishnalsk/Project-Ai-style` at
`4d3bf72a40414049b2eb9159ba25e462a734edaa`, Enterprise run 40541418763
and Security run 40541418704. This is a read-only review, not execution of its code.

## Evidence reviewed

Downloaded all five Enterprise artifacts and both Security artifacts. The Enterprise
bundle contains ten files; eight individual suite files are byte-identical copies
of files inside that bundle. Security adds four files: XLSX, HTML, scan log, SARIF.
All 478 source blobs matched the immutable Git tree. The five Enterprise workbooks
contain 57 sheets. Compared every one of 1,425 detail rows and its category copy
against JSON (2,850 rows, 17 columns). Category copies are not additional tests.
The master workbook's eleven rows summarize the detailed suite workbooks.

Raw review receipts remain local under
`evidence/reference-review/project-ai-style-20261028` in the project workspace;
they are not VITALIS test results and are not published as such.

## Findings

| Reference feature | Verified behavior | VITALIS disposition |
|---|---|---|
| Suite Excel, category tabs, master summary | Useful presentation and downloadable artifacts | Adopt presentation with actual runner-derived results |
| 355 Selenium cases | Three browser navigations; reported totals read from committed JSON | Do not equate inventory rows with executed scenarios |
| 370 Appium cases | Python reads stored statuses; no Appium session or JVM invocation in that job | Use actual Flutter/instrumentation/JVM results |
| 350 load cases | Reads stored statuses; printed P95 is literal 380 ms | Do not copy web-load claims into offline inference metrics |
| 350 DAST cases | Reads stored statuses; no ZAP invocation in that job | Require actual applicable security checks |
| Catalogue generator | Assigns Passed and random durations before execution | Never generate successful observations from plans |
| Bundle generator | Copies committed reports and hardcodes 1,425 passes/readiness | Derive totals; missing evidence blocks acceptance |
| Separate security workflow | Gitleaks reports no findings; Semgrep reports one blocking finding, suppressed by `|| true` | Preserve scanner failure and triage; never force green |
| Separate Android helper | Explicit simulated execution and dummy SVG evidence | Never count generated artwork as device evidence |
| Git exit 128 warnings | Checkout cleanup encounters a gitlink missing its submodule URL | Fix source configuration; distinguish cleanup from application failure |

Primary source locations: `.github/workflows/deploy.yml`,
`.github/workflows/security-review.yml`, `tests/appium/test_appium.py`,
`tests/selenium/test_selenium.py`, `tests/load/test_cases/test_load_runner.py`,
`tests/dast/test_cases/test_dast_runner.py`, and
`style-ai-web/testing-automation/{generate_all_inventories.py,bundle_reports.py,appium-runner.js}`.

The Security workbook contains another 300 stored Passed rows. Its scan log does
not establish 300 individual executed probes. Its SARIF reports no Gitleaks findings;
the separate Semgrep finding requires triage, not an assumption of exploitability.

## Ordered VITALIS work and current state

1. Preserve real failures. Full qualification 40639470545 recorded a Flutter tester
   segmentation faults in `model_download_test.dart` and
   `model_startup_inspector_test.dart`, then
   cancellation. Its root gate is FAILED, not a slow successful run. Root cause is
   unconfirmed. Added a manual diagnostic workflow comparing this fixture with and
   without coverage, preserving exact source, machine output and coverage separately.
   Diagnostic 40749024699 passed both isolated configurations. This does not close
   the full-suite crash. The next diagnostic runs all root/benchmark tests with
   fixed seed 20261029 and process concurrency 1 versus 4, retaining coverage and
   raw measurements. Its bounded diagnostic window is not a qualification pass.
2. Diagnose and correct that failure with a regression. Do not skip the fixture,
   lower coverage, or substitute a narrow diagnostic for full qualification.
3. Keep cross-host coverage union at the same commit. Linux cannot exercise the
   Windows storage branch. PR15 adds actual Windows coverage and exact-source checks;
   the required Checks workflow passed at 8f4df0c. Full qualification is still held.
4. Keep downloadable full-suite and 300-core Excel, HTML, JSON and CSV artifacts.
   Already implemented in PR15. Cancelled runs must report blocked/incomplete evidence.
   The cancelled 8f4df0c run retained 230 passing completed assertions but failed
   runner and missing-measurement checks. A reporter regression now verifies that
   HTML exposes execution problems explicitly, including escaped diagnostics;
   Actions summaries also display those problems. All 22 reporter tests pass.
5. Add consolidated per-suite reporting only from executed native, JVM,
   instrumentation, coverage and artifact-inspection outputs. Planned cases remain
   separate from observed results; preserve failed and unavailable suites.
6. Complete release/build inspection and API28/API34+ arm64 instrumentation. No
   compatible self-hosted runner is registered; record that infrastructure hold.
7. Only then perform certificate-preserving phone validation. No physical or
   comparative performance PASS is established by these Actions results.

No production code, personal phone data, signing material or historical F6 evidence
is changed by this review. Android CPU remains HOLD.
