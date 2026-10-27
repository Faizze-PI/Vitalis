# Repository operations

Repository activity should reflect real work. Test results belong to a source commit and workflow run; issue closure requires evidence. Preview downloads remain separate from qualification.

## Open acceptance work

- [Fresh root and vendored risk coverage](https://github.com/Faizze-PI/Vitalis/issues/1).
- [API-28 and API-34+ arm64 instrumentation](https://github.com/Faizze-PI/Vitalis/issues/2).
- [Durable-transfer and installation-recovery acceptance](https://github.com/Faizze-PI/Vitalis/issues/3).
- [Android CPU and Windows preview acceptance](https://github.com/Faizze-PI/Vitalis/issues/4).

These are genuine outstanding gates. No historical tickets were created and closed to inflate activity.

## Actions

Active workflow files are uploaded through [PR #5](https://github.com/Faizze-PI/Vitalis/pull/5). The [first hosted run](https://github.com/Faizze-PI/Vitalis/actions/runs/40425938582) started against workflow commit `be341d6`. That run failed because the hosted SDK command-line tools were not on PATH. The follow-up selects sdkmanager explicitly from ANDROID_HOME; consult the latest run for its outcome. Local workflow contract validation passed, including 16 rejected invalid configurations; this is not a hosted CI pass.

`Checks` is intended for pull requests and main pushes. `Full qualification` remains manual and requires compatible arm64 emulator infrastructure. Do not substitute the smaller checks workflow for full ratification. Artifacts are verification outputs, never automatically published releases.

## Wiki

Reviewed Wiki source is maintained under `docs/wiki` and published to the [GitHub Wiki](https://github.com/Faizze-PI/Vitalis/wiki). The first documentation sync is Wiki commit `577f68d`. Review and update both copies together.

## Security and maintenance

Private vulnerability reporting and Dependabot alerts are enabled. Secret scanning and push protection were already enabled and remain so. Dependency update proposals require review; no automatic merge or publication is configured. Toolchain/native locks must not be upgraded merely to silence an alert.

Issues and pull requests use evidence-focused templates. Branch protection should require the observed aggregate check only after its first real passing run. Avoid a mandatory external review rule that would prevent a sole maintainer from merging.

GitHub Projects requires separate account authorization if the current token cannot manage projects. Insights should reflect actual contributions. No synthetic commits, reviews, stars, security findings or agent sessions are created to populate tabs.
