# Firebase Android instrumentation

The dedicated project `vitalis-c94ea` has billing disabled. The recorded ARM64
`MediumPhone.arm` runs cover API 28 and API 35. They do not establish physical
phone performance, thermal behavior, model inference acceptance, or complete
application qualification.

## Verified results

- Source `c444200f21abec2609ff1104c9d2763b8515fcd4`: seven instrumentation tests
  passed on each API, with zero XML failures, errors, or skips.
- [Firebase execution](https://console.firebase.google.com/project/vitalis-c94ea/testlab/histories/bh.c7e0f29956b52924/matrices/8732966506937508425).
- [Retained-result Excel and XML](https://github.com/Faizze-PI/Vitalis/actions/runs/40861234608/artifacts/12890839681).
- Report generation has 33 passing unit tests. Duplicate cases, inconsistent
  totals, malformed XML, and invalid durations are rejected.

The retained-report workflow regenerates a workbook from committed disposable
test XML. It does not execute Android tests. Its source field identifies the
tested app commit, rather than the reporting workflow commit.

## Live Actions integration

The `firebase-fixture-build.yml` workflow builds matching app/test APKs, verifies
their source and SHA-256, and uses Workload Identity Federation to run Firebase.
Its initial two attempts authenticated but failed while uploading to Firebase's
managed results bucket. These failures remain visible in run `40812312734`.
After allowing eight minutes for the documented Editor permission to propagate,
attempt 3 passed: seven cases on API 28 and seven on API 35. Billing remained
disabled. The role is required for this Firebase-managed bucket's legacy ACL;
it is scoped to the dedicated test project.

Federation is restricted to repository ID `1433731805`, owner ID `172577800`,
the `ci/firebase-fixture-20261029` ref, and that exact workflow file. No private
service-account key is used. Moving the workflow requires an explicit update
to the provider condition; do not broaden it to arbitrary repositories or PRs.

The managed bucket is owned by Firebase. Google documents write access through
the customer project's basic Owner/Editor roles. The CI identity has Editor in
this dedicated test project. Do not put production or personal data in this
project. Billing must remain disabled. Automated Excel collection is being
qualified in run `40863941194`; do not claim its completion until that run and
its artifacts have been inspected.

## References

- [Managed bucket permissions](https://firebase.google.com/docs/test-lab/reference/toolresults/rest/v1beta3/projects/initializeSettings)
- [IAM propagation](https://docs.cloud.google.com/iam/docs/access-change-propagation)
- [Keyless GitHub authentication](https://github.com/google-github-actions/auth)

Do not replace the failed live job with a green report-only job in qualification.
Retained results, live workflow results, host checks, and physical validation
remain distinct evidence sources.
