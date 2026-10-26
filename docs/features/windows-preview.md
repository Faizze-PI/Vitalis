# Windows CPU preview

The official Flutter x64 runner retains Provider, the model registry, GGUF validation, native runtime and database schema. Native Assets compiles the existing locked llama.cpp source. CPU is the only packaged inference backend.

Windows initializes sqflite_common_ffi inside the observable startup database task. New databases, imported models, default downloads and logs use application support. Android locations are retained. Windows memory, low-memory, power and disk readings use SDK APIs; thermal and performance-core classification remain unknown and tuning stays conservative. Downloads use the shared foreground transfer adapter and recover persisted partial work at restart; Android background-service guarantees do not apply.

JNI 1.0.0 fails MSVC because its bundled header unconditionally uses GCC export syntax. Only JNI and its required jni_util package were upgraded; other lockfile versions were preserved.

The release folder must be packaged in full with SQLite, C++ runtime dependencies and licences using tool/package_windows_preview.ps1 after source checkpointing. A portable ZIP is a testing preview, not formal Windows ratification. Actual UI and native inference acceptance remains in progress. Linux and Vulkan are deferred.

## Retained checks

- Root analysis passed; 1,402 root tests passed with seed 20261028.
- Hardcode verifier passed with 76 registered dispositions; its scope is not a whole-project proof.
- The immutable bundled-model registry/ownership gate passed on Windows, including competing-owner rejection and acknowledged shutdown.
- Release build passed; inspected application/native DLLs are x64 and the main EXE is positively unsigned.
- Actual Windows UI opened the library, imported and probed the model, retained its model/chat across restart, and completed a local greeting. The source fixes for import progress and first-chat navigation are regression-tested; packaged-app retesting is next.

Formal Windows CPU ratification, broad transfer fault/integration acceptance and performance comparisons remain incomplete. The Android 1.0.1 APK is delivered separately; Windows changes do not retroactively qualify that APK.
