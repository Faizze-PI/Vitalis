# Testing and evidence

## Automated checks

The **Checks** workflow runs on pull requests and main-branch pushes. It covers Linux/Windows root tests, Linux analysis and formatting, hash-verified native text and registry/ownership tests, Android verification APKs, and a Windows portable verification build. It retains source-linked logs and build artifacts. Consult the actual [Actions runs](https://github.com/Faizze-PI/Vitalis/actions); workflow source alone is not evidence of a passing run.

**Full qualification** is a separate manual workflow. It includes coverage, additional native/stress work, release inspection and Android instrumentation. Its emulator job requires a compatible self-hosted arm64 runner labelled `vitalis-arm64-emulator`. That infrastructure is not currently established. Do not skip it and call qualification complete.

## What remains unproven

- Complete fresh root and vendored risk-coverage qualification.
- API-28 and API-34+ arm64 instrumentation, including scheduler recovery.
- Durable downloads and installation-recovery fault acceptance.
- Complete Android physical performance, cancellation, preservation and stability acceptance.
- Windows cross-machine, transfer and performance qualification.

Phone results cannot establish API-28 or 16-KB page compatibility unless the tested hardware actually has those properties. Missing comparable legacy timing leaves the comparative-performance gate blocked.

## Evidence rules

Record source SHA, command/test identity, expected and observed results, exit status, and logs. Retain failed runs alongside successful reruns. Separate source fixes, regression tests, physical verification and unsupported measurements. Do not upload personal phone evidence, chats, model files, credentials or signing material.

See [status](https://github.com/Faizze-PI/Vitalis/blob/main/docs/public/STATUS.md), [build instructions](https://github.com/Faizze-PI/Vitalis/blob/main/docs/public/BUILDING.md), and [release provenance](https://github.com/Faizze-PI/Vitalis/blob/main/docs/public/RELEASE_PROVENANCE.md).
