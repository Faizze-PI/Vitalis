# Contributing

VITALIS currently focuses on Android CPU. Please keep changes small and preserve Provider/ChangeNotifier, offline inference, data-preserving migrations and the locked native build.

1. Describe the observed problem and reproduction. Distinguish model-answer quality from runtime, rendering and persistence failures.
2. Add a regression for a reproducible defect, then implement the correction.
3. Use the pinned environment and gate launchers documented in the README. Record the scope of checks actually run.
4. Keep credentials, model weights, generated binaries, databases and private phone evidence out of commits.
5. Retain third-party notices. Contributions to original VITALIS code are intended under Apache-2.0; separately licensed vendored code retains its applicable terms.

For a bug report, include the source commit, Android API/ABI, model repository/revision/hash when relevant, expected/observed behaviour and redacted diagnostics. Do not post personal prompts, chats, device identifiers or authentication material.

Do not clear another person's app data or use production signing material for tests. Destructive fault injection belongs in isolated fixtures.
