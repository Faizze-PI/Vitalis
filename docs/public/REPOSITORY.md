# Repository operations

Repository activity should reflect real work. Test results belong to a source commit and workflow run; issue closure requires evidence. Preview downloads remain separate from qualification.

## Open acceptance work

- [Fresh root and vendored risk coverage](https://github.com/Faizze-PI/Vitalis/issues/1).
- [API-28 and API-34+ arm64 instrumentation](https://github.com/Faizze-PI/Vitalis/issues/2).
- [Durable-transfer and installation-recovery acceptance](https://github.com/Faizze-PI/Vitalis/issues/3).
- [Android CPU and Windows preview acceptance](https://github.com/Faizze-PI/Vitalis/issues/4).

These are genuine outstanding gates. No historical tickets were created and closed to inflate activity.

## Actions

Active workflow files are being prepared on the repository-foundation branch. Upload currently requires GitHub CLI's additional `workflow` authorization. Local workflow contract validation passed, including 16 rejected invalid configurations; this is not a hosted CI pass.

`Checks` is intended for pull requests and main pushes. `Full qualification` remains manual and requires compatible arm64 emulator infrastructure. Do not substitute the smaller checks workflow for full ratification. Artifacts are verification outputs, never automatically published releases.

## Wiki

Reviewed Wiki source is maintained under `docs/wiki`. GitHub's separate Wiki repository has not yet been initialized; prepared Markdown is not a published Wiki. Once its initial Home page exists, sync the reviewed pages through the Wiki Git repository and verify rendered links.

## Security and maintenance

Private vulnerability reporting and Dependabot alerts are enabled. Secret scanning and push protection were already enabled and remain so. Dependency update proposals require review; no automatic merge or publication is configured. Toolchain/native locks must not be upgraded merely to silence an alert.

Issues and pull requests use evidence-focused templates. Branch protection should require the observed aggregate check only after its first real passing run. Avoid a mandatory external review rule that would prevent a sole maintainer from merging.

GitHub Projects requires separate account authorization if the current token cannot manage projects. Insights should reflect actual contributions. No synthetic commits, reviews, stars, security findings or agent sessions are created to populate tabs.
