# Contributing

Start with a reproducible problem, an open issue and a small pull request. Preserve Provider/ChangeNotifier, offline inference, data-preserving migrations and the locked native source. Do not introduce a state-management rewrite to solve an unrelated defect.

Use the [pinned build environment](https://github.com/Faizze-PI/Vitalis/blob/main/docs/public/BUILDING.md). Add a regression for a reproducible bug and report exactly which checks ran. Missing native-model fixtures must fail rather than silently skip.

Pull requests should explain the user-visible change, reproduction, regression coverage and limitations. Public logs must be redacted. Never publish credentials, private databases, model weights or signing keys.

Sensitive findings belong through [private security reporting](https://github.com/Faizze-PI/Vitalis/security), where enabled, rather than public issue details. See [CONTRIBUTING](https://github.com/Faizze-PI/Vitalis/blob/main/CONTRIBUTING.md) and [SECURITY](https://github.com/Faizze-PI/Vitalis/blob/main/SECURITY.md).
