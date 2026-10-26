# Preview status

## Android 1.0.1

- Refreshed identity and conversation-focused navigation.
- Separate app and per-chat settings, with validated numeric controls.
- 1,394 root tests passed with seed 20261102; analysis passed.
- Arm64 profile APK built with non-production debug signing.
- In-place OPPO installation succeeded. Nine checked database tables matched before and after installation. Chat settings and the numeric editor opened; cancellation preserved the setting.

These are scoped checks, not production ratification. Full coverage collection failed when the test VM service disappeared; its cause remains unconfirmed. Clean-build, support-floor emulator, durable-transfer, performance and complete physical acceptance gates remain open. GitHub Actions is not enabled yet.

Windows CPU preview is next. Linux and Vulkan remain deferred.
