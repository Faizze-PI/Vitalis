# Dependencies and toolchain

Versions below come from the documented source checkpoint and its two checked-in lockfiles. Manifest constraints and resolved versions differ. Transitive packages are listed completely; not every transitive package is imported directly or shipped on every platform. Licences remain governed by package/native notices, not this inventory.

SDK packages use `0.0.0` lockfile placeholders; this is not the installed Flutter version. The actual pinned Flutter/Dart versions are in the build-identity section and machine-readable toolchain policy.

## Application

Manifest: [pubspec.yaml](../../pubspec.yaml). Resolution: [pubspec.lock](../../pubspec.lock).

| Package | Kind | Constraint | Resolved | Use / why |
|---|---|---|---|---|
| `flutter` | Runtime | `SDK: flutter` | `0.0.0` | UI framework, rendering, navigation, platform integration and application runtime. |
| `provider` | Runtime | `6.1.5+1` | `6.1.5+1` | Dependency injection and observable ChangeNotifier state consumed by widgets. |
| `sqflite` | Runtime | `2.4.2+1` | `2.4.2+1` | SQLite persistence on Android; shared DatabaseHelper API. |
| `sqflite_common_ffi` | Runtime | `2.3.7+1` | `2.3.7+1` | Windows SQLite implementation and deterministic host database fixtures; portable package includes SQLite runtime. |
| `path_provider` | Runtime | `2.1.5` | `2.1.5` | Application-owned documents/support/cache directory discovery rather than fixed machine paths. |
| `flutter_markdown_plus` | Runtime | `1.0.7` | `1.0.7` | Assistant message Markdown rendering in the conversation UI. |
| `shared_preferences` | Runtime | `2.5.5` | `2.5.5` | Appearance/developer preferences and runtime-profile cache; not the conversation database. |
| `dio` | Runtime | `5.9.2` | `5.9.2` | Public Hub API calls, range metadata and foreground/bundled transfer transport. |
| `llm_llamacpp` | Runtime | `path: third_party/llm_llamacpp` | `0.3.2` | Locally vendored Dart/native inference integration with runtime ownership, cancellation, metadata and templates. |
| `battery_plus` | Runtime | `6.2.3` | `6.2.3` | Battery level/charging telemetry adapter. |
| `connectivity_plus` | Runtime | `6.1.5` | `6.1.5` | Network connectivity observation, principally relevant to downloads; not proof of actual Internet reachability. |
| `share_plus` | Runtime | `10.1.4` | `10.1.4` | Diagnostic sharing from the developer screen; conversation clipboard export is a separate flow. |
| `intl` | Runtime | `0.20.2` | `0.20.2` | Local diagnostic date/time formatting. |
| `characters` | Runtime | `^1.3.0` | `1.4.1` | Declared Unicode grapheme helper. No explicit package import was found in app lib; review transitive exports/usage before removal. |
| `crypto` | Runtime | `^3.0.6` | `3.0.7` | Streaming SHA-256 identity/integrity checks for model files, templates and locked sources. |
| `file_picker` | Runtime | `11.0.3` | `11.0.3` | User-selected local GGUF/document import rather than exact-filename discovery. |
| `package_info_plus` | Runtime | `8.3.1` | `8.3.1` | Runtime application version used in profile/version identity instead of a duplicated Dart version constant. |
| `flutter_test` | Development/test | `SDK: flutter` | `0.0.0` | Flutter unit/widget test framework; not shipped as the app runtime. |
| `integration_test` | Development/test | `SDK: flutter` | `0.0.0` | Flutter integration harness; must not enter release plugin registration. |
| `analyzer` | Development/test | `^9.0.0` | `9.0.0` | Source-analysis APIs for verification tooling; not app inference. |
| `yaml` | Development/test | `3.1.3` | `3.1.3` | Workflow/policy fixture parsing in developer verification and tests. |
| `logging` | Development/test | `1.3.0` | `1.3.0` | Structured runtime/hook diagnostics; release verbosity and private content still require explicit controls. |

### Complete resolved package list

| Package | Resolved version | Resolution role | Source |
|---|---|---|---|
| `_fe_analyzer_shared` | `92.0.0` | transitive | hosted |
| `analyzer` | `9.0.0` | direct dev | hosted |
| `args` | `2.7.0` | transitive | hosted |
| `async` | `2.13.1` | transitive | hosted |
| `battery_plus` | `6.2.3` | direct main | hosted |
| `battery_plus_platform_interface` | `2.0.1` | transitive | hosted |
| `boolean_selector` | `2.1.2` | transitive | hosted |
| `characters` | `1.4.1` | direct main | hosted |
| `clock` | `1.1.2` | transitive | hosted |
| `code_assets` | `1.2.1` | transitive | hosted |
| `collection` | `1.19.1` | transitive | hosted |
| `connectivity_plus` | `6.1.5` | direct main | hosted |
| `connectivity_plus_platform_interface` | `2.1.0` | transitive | hosted |
| `convert` | `3.1.2` | transitive | hosted |
| `cross_file` | `0.3.5+2` | transitive | hosted |
| `crypto` | `3.0.7` | direct main | hosted |
| `dbus` | `0.7.14` | transitive | hosted |
| `dio` | `5.9.2` | direct main | hosted |
| `dio_web_adapter` | `2.1.2` | transitive | hosted |
| `fake_async` | `1.3.3` | transitive | hosted |
| `ffi` | `2.2.0` | transitive | hosted |
| `file` | `7.0.1` | transitive | hosted |
| `file_picker` | `11.0.3` | direct main | hosted |
| `fixnum` | `1.1.1` | transitive | hosted |
| `flutter` | `0.0.0` | direct main | sdk |
| `flutter_driver` | `0.0.0` | transitive | sdk |
| `flutter_markdown_plus` | `1.0.7` | direct main | hosted |
| `flutter_plugin_android_lifecycle` | `2.0.35` | transitive | hosted |
| `flutter_test` | `0.0.0` | direct dev | sdk |
| `flutter_web_plugins` | `0.0.0` | transitive | sdk |
| `fuchsia_remote_debug_protocol` | `0.0.0` | transitive | sdk |
| `glob` | `2.2.0` | transitive | hosted |
| `hooks` | `2.0.2` | transitive | hosted |
| `http` | `1.6.0` | transitive | hosted |
| `http_parser` | `4.1.2` | transitive | hosted |
| `integration_test` | `0.0.0` | direct dev | sdk |
| `intl` | `0.20.2` | direct main | hosted |
| `jni` | `1.0.0` | transitive | hosted |
| `jni_flutter` | `1.0.1` | transitive | hosted |
| `leak_tracker` | `11.0.2` | transitive | hosted |
| `leak_tracker_flutter_testing` | `3.0.10` | transitive | hosted |
| `leak_tracker_testing` | `3.0.2` | transitive | hosted |
| `llm_core` | `0.3.2` | transitive | hosted |
| `llm_llamacpp` | `0.3.2` | direct main | path |
| `logging` | `1.3.0` | direct dev | hosted |
| `markdown` | `7.3.1` | transitive | hosted |
| `matcher` | `0.12.19` | transitive | hosted |
| `material_color_utilities` | `0.13.0` | transitive | hosted |
| `meta` | `1.18.0` | transitive | hosted |
| `mime` | `2.0.0` | transitive | hosted |
| `nested` | `1.0.0` | transitive | hosted |
| `nm` | `0.5.0` | transitive | hosted |
| `objective_c` | `9.5.0` | transitive | hosted |
| `package_config` | `2.2.0` | transitive | hosted |
| `package_info_plus` | `8.3.1` | direct main | hosted |
| `package_info_plus_platform_interface` | `3.2.1` | transitive | hosted |
| `path` | `1.9.1` | transitive | hosted |
| `path_provider` | `2.1.5` | direct main | hosted |
| `path_provider_android` | `2.3.1` | transitive | hosted |
| `path_provider_foundation` | `2.6.0` | transitive | hosted |
| `path_provider_linux` | `2.2.1` | transitive | hosted |
| `path_provider_platform_interface` | `2.1.2` | transitive | hosted |
| `path_provider_windows` | `2.3.0` | transitive | hosted |
| `petitparser` | `7.0.2` | transitive | hosted |
| `platform` | `3.1.6` | transitive | hosted |
| `plugin_platform_interface` | `2.1.8` | transitive | hosted |
| `process` | `5.0.5` | transitive | hosted |
| `provider` | `6.1.5+1` | direct main | hosted |
| `pub_semver` | `2.2.0` | transitive | hosted |
| `record_use` | `0.6.0` | transitive | hosted |
| `share_plus` | `10.1.4` | direct main | hosted |
| `share_plus_platform_interface` | `5.0.2` | transitive | hosted |
| `shared_preferences` | `2.5.5` | direct main | hosted |
| `shared_preferences_android` | `2.4.23` | transitive | hosted |
| `shared_preferences_foundation` | `2.5.6` | transitive | hosted |
| `shared_preferences_linux` | `2.4.1` | transitive | hosted |
| `shared_preferences_platform_interface` | `2.4.2` | transitive | hosted |
| `shared_preferences_web` | `2.4.3` | transitive | hosted |
| `shared_preferences_windows` | `2.4.1` | transitive | hosted |
| `sky_engine` | `0.0.0` | transitive | sdk |
| `source_span` | `1.10.2` | transitive | hosted |
| `sqflite` | `2.4.2+1` | direct main | hosted |
| `sqflite_android` | `2.4.2+3` | transitive | hosted |
| `sqflite_common` | `2.5.8` | transitive | hosted |
| `sqflite_common_ffi` | `2.3.7+1` | direct main | hosted |
| `sqflite_darwin` | `2.4.2` | transitive | hosted |
| `sqflite_platform_interface` | `2.4.0` | transitive | hosted |
| `sqlite3` | `2.9.4` | transitive | hosted |
| `stack_trace` | `1.12.1` | transitive | hosted |
| `stream_channel` | `2.1.4` | transitive | hosted |
| `string_scanner` | `1.4.1` | transitive | hosted |
| `sync_http` | `0.3.1` | transitive | hosted |
| `synchronized` | `3.4.0+1` | transitive | hosted |
| `term_glyph` | `1.2.2` | transitive | hosted |
| `test_api` | `0.7.11` | transitive | hosted |
| `typed_data` | `1.4.0` | transitive | hosted |
| `upower` | `0.7.0` | transitive | hosted |
| `url_launcher_linux` | `3.2.2` | transitive | hosted |
| `url_launcher_platform_interface` | `2.3.2` | transitive | hosted |
| `url_launcher_web` | `2.4.3` | transitive | hosted |
| `url_launcher_windows` | `3.1.5` | transitive | hosted |
| `uuid` | `4.5.3` | transitive | hosted |
| `vector_math` | `2.2.0` | transitive | hosted |
| `vm_service` | `15.2.0` | transitive | hosted |
| `watcher` | `1.2.1` | transitive | hosted |
| `web` | `1.1.1` | transitive | hosted |
| `webdriver` | `3.1.0` | transitive | hosted |
| `win32` | `5.15.0` | transitive | hosted |
| `xdg_directories` | `1.1.0` | transitive | hosted |
| `xml` | `6.6.1` | transitive | hosted |
| `yaml` | `3.1.3` | direct dev | hosted |

## Vendored inference package

Manifest: [third_party/llm_llamacpp/pubspec.yaml](../../third_party/llm_llamacpp/pubspec.yaml). Resolution: [third_party/llm_llamacpp/pubspec.lock](../../third_party/llm_llamacpp/pubspec.lock).

| Package | Kind | Constraint | Resolved | Use / why |
|---|---|---|---|---|
| `flutter` | Runtime | `SDK: flutter` | `0.0.0` | UI framework, rendering, navigation, platform integration and application runtime. |
| `llm_core` | Runtime | `^0.3.2` | `0.3.2` | Vendored package-neutral chat/message/repository abstractions implemented by LlamaCppChatRepository. |
| `ffi` | Runtime | `^2.1.3` | `2.2.0` | Dart FFI allocation, UTF conversions and native interop helpers. |
| `http` | Runtime | `^1.6.0` | `1.6.0` | Vendored generic HTTP support; root app Hub/transfer paths primarily use Dio. |
| `path` | Runtime | `^1.9.0` | `1.9.1` | Cross-platform path handling, used by app services and the native package. Root currently receives it transitively; direct declaration should be reviewed. |
| `hooks` | Runtime | `^2.0.0` | `2.0.2` | Dart Native Assets build-hook protocol. |
| `code_assets` | Runtime | `^1.2.1` | `1.2.1` | Native code-asset registration and platform bundling metadata. |
| `logging` | Runtime | `^1.3.0` | `1.3.0` | Structured runtime/hook diagnostics; release verbosity and private content still require explicit controls. |
| `meta` | Runtime | `1.18.0` | `1.18.0` | Dart API/analysis annotations. |
| `crypto` | Runtime | `^3.0.0` | `3.0.7` | Streaming SHA-256 identity/integrity checks for model files, templates and locked sources. |
| `lints` | Development/test | `^6.1.0` | `6.1.0` | Vendored Dart lint policy. |
| `test` | Development/test | `^1.31.0` | `1.31.2` | Pure-Dart test framework used by vendored runtime/product gates. |
| `ffigen` | Development/test | `^21.0.0` | `21.0.0` | Generates C ABI bindings from headers; needs compatible libclang and locked source headers. |
| `dotenv` | Development/test | `^4.2.0` | `4.2.0` | Vendored development/test environment support; no VITALIS cloud credential feature is implied. |

### Complete resolved package list

| Package | Resolved version | Resolution role | Source |
|---|---|---|---|
| `_fe_analyzer_shared` | `100.0.0` | transitive | hosted |
| `analyzer` | `13.0.0` | transitive | hosted |
| `args` | `2.7.0` | transitive | hosted |
| `async` | `2.13.1` | transitive | hosted |
| `boolean_selector` | `2.1.2` | transitive | hosted |
| `characters` | `1.4.1` | transitive | hosted |
| `cli_config` | `0.2.0` | transitive | hosted |
| `cli_util` | `0.4.2` | transitive | hosted |
| `code_assets` | `1.2.1` | direct main | hosted |
| `collection` | `1.19.1` | transitive | hosted |
| `convert` | `3.1.2` | transitive | hosted |
| `coverage` | `1.15.1` | transitive | hosted |
| `crypto` | `3.0.7` | direct main | hosted |
| `dart_style` | `3.1.9` | transitive | hosted |
| `dotenv` | `4.2.0` | direct dev | hosted |
| `ffi` | `2.2.0` | direct main | hosted |
| `ffigen` | `21.0.0` | direct dev | hosted |
| `file` | `7.0.1` | transitive | hosted |
| `flutter` | `0.0.0` | direct main | sdk |
| `frontend_server_client` | `4.0.0` | transitive | hosted |
| `glob` | `2.2.0` | transitive | hosted |
| `hooks` | `2.0.2` | direct main | hosted |
| `http` | `1.6.0` | direct main | hosted |
| `http_multi_server` | `3.2.2` | transitive | hosted |
| `http_parser` | `4.1.2` | transitive | hosted |
| `io` | `1.1.0` | transitive | hosted |
| `lints` | `6.1.0` | direct dev | hosted |
| `llm_core` | `0.3.2` | direct main | hosted |
| `logging` | `1.3.0` | direct main | hosted |
| `matcher` | `0.12.20` | transitive | hosted |
| `material_color_utilities` | `0.13.0` | transitive | hosted |
| `meta` | `1.18.0` | direct main | hosted |
| `mime` | `2.1.0` | transitive | hosted |
| `native_toolchain_c` | `0.19.2` | transitive | hosted |
| `node_preamble` | `2.0.2` | transitive | hosted |
| `package_config` | `2.2.0` | transitive | hosted |
| `path` | `1.9.1` | direct main | hosted |
| `pool` | `1.5.3` | transitive | hosted |
| `pub_semver` | `2.2.1` | transitive | hosted |
| `quiver` | `3.2.2` | transitive | hosted |
| `record_use` | `0.6.0` | transitive | hosted |
| `shelf` | `1.4.2` | transitive | hosted |
| `shelf_packages_handler` | `3.0.2` | transitive | hosted |
| `shelf_static` | `1.1.3` | transitive | hosted |
| `shelf_web_socket` | `3.0.0` | transitive | hosted |
| `sky_engine` | `0.0.0` | transitive | sdk |
| `source_map_stack_trace` | `2.1.2` | transitive | hosted |
| `source_maps` | `0.10.14` | transitive | hosted |
| `source_span` | `1.10.2` | transitive | hosted |
| `stack_trace` | `1.12.2` | transitive | hosted |
| `stream_channel` | `2.1.4` | transitive | hosted |
| `string_scanner` | `1.4.1` | transitive | hosted |
| `term_glyph` | `1.2.2` | transitive | hosted |
| `test` | `1.31.2` | direct dev | hosted |
| `test_api` | `0.7.13` | transitive | hosted |
| `test_core` | `0.6.19` | transitive | hosted |
| `typed_data` | `1.4.0` | transitive | hosted |
| `vector_math` | `2.2.0` | transitive | hosted |
| `vm_service` | `15.3.0` | transitive | hosted |
| `watcher` | `1.2.1` | transitive | hosted |
| `web` | `1.1.1` | transitive | hosted |
| `web_socket` | `1.0.1` | transitive | hosted |
| `web_socket_channel` | `3.0.3` | transitive | hosted |
| `webkit_inspection_protocol` | `1.2.1` | transitive | hosted |
| `yaml` | `3.1.4` | transitive | hosted |
| `yaml_edit` | `2.2.4` | transitive | hosted |

## Native and platform dependencies

| Component | Source/configuration | Why it exists |
|---|---|---|
| llama.cpp b10727 | Native lock commit `ab0b3bd3c846839e9014c03b071f0f550a57ca84`; SHA-256-verified archive | GGUF loading, tokenizer, context, sampling and decoding |
| GGML base/coordinator/CPU | Built from the same locked llama.cpp source | Tensor operations and CPU backend; packaged dependencies must resolve together |
| Owned C++ runtime bridge | `third_party/llm_llamacpp/native/vitalis_runtime_bridge.cpp` | Atomic cancellation, process/backend and model-file ownership |
| Owned template bridge + locked common Jinja sources | Native template header/implementation and build hook | Authoritative configured chat rendering/thinking support |
| Android NDK / C++ runtime | NDK `28.2.13676358`, API 28 arm64 | Cross-compiles native libraries and supplies required C++ runtime dependencies |
| CMake / Ninja / host compiler | Hook and runner CMake files; host tool installations | Builds source code; not arbitrary downloaded prebuilt inference libraries |
| Visual C++ / Win32 | Windows runner and portable inspection/packaging scripts | Windows application host and required runtime dependency closure |
| SQLite | sqflite Android / sqflite_common_ffi Windows | Local relational persistence and transactional migration |
| AndroidX WorkManager `2.12.0` | Android app Gradle dependencies | API-28–33 foreground transfer execution and durable scheduling |
| Guava `33.7.2-android` | Explicit Android Gradle dependency | WorkManager Java ListenableFuture implementation; avoids conflict-marker-only resolution |
| JUnit `4.13.2`, Robolectric `4.17` | Android JVM test dependencies | Java Android-host/transfer tests without treating a host simulation as a physical result |
| AndroidX Test runner `1.7.0`, JUnit extension `1.3.0` | Policy and Gradle test resolution | Actual Android instrumentation harness; compatible API/ABI execution still required |
| JaCoCo `0.8.13` | Android Gradle coverage tasks | Java transfer execution/line/branch report inputs and gate checks |
| Vulkan / SPIR-V | Experimental optional hook path; not CPU default | Future independently qualified GPU backend; source/build support is not representative-device stability evidence |

## Build identity

Flutter **3.44.7**, Dart **3.12.2**, JDK **21.0.9**, Android compile SDK **36**, target SDK **35**, minimum SDK **28**, Gradle **8.14.6**, Android Gradle Plugin **8.11.1**, Kotlin plugin **2.2.20**, Java bytecode **17**. Consult `tool/toolchain_policy.json`, Gradle settings/wrapper and lockfiles as the authority before changing any number. CMake/compiler availability must be recorded by the build environment; this document does not invent a universally pinned host compiler version.

## Hosted services

- **GitHub:** source, issues, pull requests, Actions, Wiki, Projects, releases, security reporting and dependency alerts. It is not an inference backend. Workflow revisions are pinned in workflow source; inspect actual runs for outcomes.
- **Hugging Face:** anonymous public metadata and model artifact transport. No app OAuth/token entry, gated-model support or cloud inference is implied.
- **Pub, Google/Maven and GitHub source archives:** development dependency/source resolution. End-user inference does not contact these development services.

## Upgrade policy

Review one dependency change at a time against SDK compatibility, platform APIs, migration, ABI, cancellation, native-symbol and packaging gates. Outdated-version output is not permission to update everything. Preserve both lockfiles and native/wrapper checksum authorities. Never commit model weights, signing keys, credentials or private app databases.
