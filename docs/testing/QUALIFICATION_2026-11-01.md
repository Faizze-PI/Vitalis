# Qualification checkpoint — 1 November 2026

Tested source: `412cb82533dddfc02d8bd1dad1711d5990237f79`.

[Full qualification run 40865519244](https://github.com/Faizze-PI/Vitalis/actions/runs/40865519244)
completed successfully. Its ten jobs passed. Downloaded results were checked
against the source identity and actual case outcomes.

| Evidence | Verified outcome |
|---|---|
| Root suite and host benchmark | 1,394 passed; zero failures or skips |
| Native runtime report | 91 passed; zero failures or skips |
| Android JVM XML | 155 passed; zero failures, errors or skips |
| API-28 ARM64 instrumentation | Seven passed; zero failures, errors or skips |
| API-35 ARM64 instrumentation | Seven passed; zero failures, errors or skips |
| Configured Dart risk gates | Passed for 65-file and expanded 72-file scopes |
| Android transfer coverage | Passed for 18 required sources |
| Android builds and lint | Workflow debug/profile and release gates passed |
| Unsigned release inspection | APK/AAB checks passed in the release job |
| Independent ELF inspection | Dependency closure checked for all 16 library entries across APK/AAB; all LOAD segments have at least 16-KB alignment |

These counts describe separate suites, not additional unique product requirements.
Coverage gate success is not 100% whole-project coverage. Static alignment does
not establish physical operation on a 16-KB device. Registered build warnings
remain documented in `BUILD_WARNINGS.md`; this is not a zero-warning claim.

## Downloads

- [Root Excel reports](https://github.com/Faizze-PI/Vitalis/actions/runs/40865519244/artifacts/12894097994)
- [Native-runtime Excel report](https://github.com/Faizze-PI/Vitalis/actions/runs/40865519244/artifacts/12895830288)
- [Live Firebase Excel and XML](https://github.com/Faizze-PI/Vitalis/actions/runs/40865519244/artifacts/12895154934)
- [Unsigned verification artifacts](https://github.com/Faizze-PI/Vitalis/actions/runs/40865519244/artifacts/12895014029)

Unsigned artifacts cannot be installed. They are not a new public release.
Artifacts expire according to each workflow's retention policy.

Release SHA-256:

| File | SHA-256 |
|---|---|
| APK | `e73b813231428be850bf28d983e1e5451ef321cd68f278121a5edf4351e3de32` |
| AAB | `e45b60179e4d122070f63f3a837dbe191417bdc06ccaa90becaf2c676486c981` |

## Remaining acceptance

1. [Repeat qualification 41313192814](https://github.com/Faizze-PI/Vitalis/actions/runs/41313192814)
   passed all ten jobs in a fresh hosted checkout of the same source. Root and
   native case identities/outcomes match; Android JVM again passed 155 cases.
   Both live API runs again passed seven cases. The APK is byte-identical.
   AAB application payloads match; only `compilation.buildTimeNs` in R8 build
   metadata differs. This explains the AAB hash difference without claiming
   byte-identical archives. All 258 FFI symbols referenced by generated bindings
   and the runtime bridge were independently found in both release artifacts.
2. PR #16 integrated the qualification changes into the existing qualification
   branch. PR #15's checks still govern integration into `main`; that merge is
   not established by the two candidate qualification runs.
3. The seven instrumentation cases per API cover narrow startup/transfer fixture
   behavior. Complete on-phone UI, model-library, notification, document-picker,
   process-recovery and preservation acceptance is still required.
4. The OPPO subsequently reconnected. A fresh debug-signed arm64 profile APK
   was built at `071581cae8be2239dd57b74a132f7bc1e41c838c` (only documentation
   differs from the qualified runtime source). Certificate comparison passed;
   an in-place update succeeded and the installed APK hash matched the candidate.
   Every prior row in 14 database tables and the preference file remained
   unchanged after installation and five stopped-state launches. Database
   integrity passed. These are scoped preservation/startup passes, not complete
   feature or performance acceptance. Private snapshots remain local.
5. Ten-request inference, visible/native cancellation, prefix reuse, comparable
   legacy TTFT/throughput and workload-linked memory/thermal acceptance remain
   physical gates. Missing comparable legacy data retains its own hold.
6. Android CPU is not ratified. Windows acceptance and experimental Vulkan have
   separate requirements and are not established by this workflow.

Local raw evidence and the machine-readable artifact audit are retained under
`D:/VITALIS/evidence/full-qualification-40865519244`. Private phone evidence is
not included in the repository.
