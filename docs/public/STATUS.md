# Preview status

## Android 1.0.1

- Refreshed identity and conversation-focused navigation.
- Separate app and per-chat settings, with validated numeric controls.
- 1,394 root tests passed with seed 20261102; analysis passed.
- Arm64 profile APK built with non-production debug signing.
- In-place OPPO installation succeeded. Nine checked database tables matched before and after installation. Chat settings and the numeric editor opened; cancellation preserved the setting.

These are scoped checks, not production ratification. Full coverage collection failed when the test VM service disappeared; its cause remains unconfirmed. Clean-build, support-floor emulator, durable-transfer, performance and complete physical acceptance gates remain open. GitHub Actions is being introduced through [PR #5](https://github.com/Faizze-PI/Vitalis/pull/5); consult the actual runs rather than treating workflow configuration as a pass.

## Windows 1.0.1 preview

The official Flutter x64 runner uses the existing CPU Native Assets backend. The desktop port passed analysis, 1,402 root tests (latest seed 20261029), the verified-model registry/ownership test, and a release build. The actual desktop app imported and validated Qwen, retained chat/model state across restart, and completed a local greeting. Import progress and first-chat navigation have focused regressions. The complete portable folder includes SQLite and C++ runtime dependencies. The final ZIP passed the dependency/symbol/payload checks, loaded its DLLs with Java removed from the test environment, and opened saved chats outside the development repository. The Android-only JNI bridge is excluded; users do not need Java.

This is a testing preview, not formal platform ratification. Full desktop transfer fault/integration coverage, performance characterization and cross-machine testing remain open. Windows 11 was exercised; other supported Windows configurations remain unverified. Android-specific background download guarantees do not apply to desktop foreground transfers.

Linux and Vulkan remain deferred.
