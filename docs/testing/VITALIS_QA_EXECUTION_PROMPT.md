# VITALIS QA and downloadable reporting prompt

Act as a Flutter, Android, native-runtime and GitHub Actions QA engineer.
Inspect the current checkout and workflow before making changes. Preserve
Provider, offline inference, personal data, production behavior and source history.
Do not redesign the application or introduce web/backend infrastructure.

## Programme and report format

Maintain exactly 300 distinct core case identities in
`tool/reporting/core_300_cases.json`. These are a curated cross-feature view,
not a replacement for the larger existing test suite. Never pad counts with
duplicate tests or count loading/setup events as product test cases.

Use SUMMARY and TEST RESULTS worksheets with ID, category, name, objective,
preconditions, steps, expected/actual results, status, priority, severity,
duration, evidence, remarks, automation status and source file. The linked source
test owns its detailed fixtures, actions and assertions. Do not invent manual
actions for automated tests. Triage failure severity when a defect is observed.

Cover startup/recovery, chat UI, notes, personas, settings, history/export,
database integrity, model registry/library, download ownership/recovery,
context planning, runtime recovery, device safety, input and privacy boundaries.
Use Flutter's actual test runner, Java/JVM and Android instrumentation where
appropriate. Do not label host widget tests Appium/phone E2E tests.

## Execution and evidence

Run existing policy, root, native and build checks without weakening them.
The Windows validation step executes the complete adapted programme from
`validation_cases.json`. Parse its real machine events and measured storage
records. Match the 300 core cases by exact source path and test name.
Missing completion means BLOCKED; failed/skipped cases remain FAIL/SKIP.
Missing fixtures fail their native gate. No hardcoded success summaries,
random timings, canned vulnerability scores or suppressed failure exits.

Retain the full-suite workbook alongside the 300-case workbook, raw runner log,
JSON, CSV, HTML and measured performance data. Upload them to the run artifact
`VITALIS-Excel-test-report-Windows` with 30-day retention. Preserve failed-run
evidence too. Derive summaries from results; include source commit and run URL.

Host SQLite measurements are not phone latency, model throughput or concurrent
app users. There is no production web service to attack with Selenium, ZAP or
100-user k6 traffic. Run HTTP faults against controlled test adapters/servers.
Do not load-test Hugging Face or unrelated systems.

## Qualification boundaries

Retain separate gates for API-28 and API-34+ arm64 instrumentation, real-model
native inference, packaging/release inspection and physical Android acceptance.
Unavailable infrastructure is BLOCKED, not PASS. GitHub Pages may host only
redacted public reports if separately configured; never deploy the mobile app
or private device evidence there. Do not infer Android ratification from CI.

On failure: retain reproduction, classify product/test/environment cause,
add regression, correct the smallest owning component and rerun affected gates.
Report actual counts, failures, holds and artifact links concisely.
