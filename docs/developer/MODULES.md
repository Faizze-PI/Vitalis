# Complete module reference

Documented source: `810e58af87ce43b6c9f9c85ca2a9dfb7b7583368`. 622 tracked files; 130 app Dart files. This catalogue explains maintained app/native/platform/tooling modules. Test/support files are in [TESTS.md](TESTS.md); assets and all other files remain indexed in [source-inventory.json](source-inventory.json).

Each purpose statement combines responsibility and why the file exists. “Referenced by” means lexical Dart import/export/part references, not a proven runtime call graph. Native calls, framework discovery, reflection and string-based channels are explained in [GUIDE.md](GUIDE.md). Symbols are a navigation aid, not an exhaustive generated API specification.

## Repository, dependencies and CI

### `.github/ISSUE_TEMPLATE/bug.yml`

Reproduction/evidence-focused public bug form with privacy guidance.

**Source:** [.github/ISSUE_TEMPLATE/bug.yml](../../.github/ISSUE_TEMPLATE/bug.yml).

### `.github/ISSUE_TEMPLATE/config.yml`

Issue chooser and private security report link; keeps sensitive reports out of public issues.

**Source:** [.github/ISSUE_TEMPLATE/config.yml](../../.github/ISSUE_TEMPLATE/config.yml).

### `.github/PULL_REQUEST_TEMPLATE.md`

Change, verification and data/privacy review prompts; no synthetic review or passing result is implied.

**Source:** [.github/PULL_REQUEST_TEMPLATE.md](../../.github/PULL_REQUEST_TEMPLATE.md).

### `.github/actionlint.yaml`

Declares the custom self-hosted arm64 runner label to the workflow linter; does not provision that runner.

**Source:** [.github/actionlint.yaml](../../.github/actionlint.yaml).

### `.github/actions/setup/action.yml`

Shared pinned CI environment and host native-library search path; initializes source-linked evidence before setup can fail.

**Source:** [.github/actions/setup/action.yml](../../.github/actions/setup/action.yml).

### `.github/dependabot.yml`

Monthly dependency update proposals for Actions, Pub and Gradle; updates require review, not automatic merge.

**Source:** [.github/dependabot.yml](../../.github/dependabot.yml).

### `.github/workflows/checks.yml`

Automatic scoped PR/main host tests, native fixture tests and verification builds; actual run outcomes remain separate from source configuration.

**Source:** [.github/workflows/checks.yml](../../.github/workflows/checks.yml).

### `.github/workflows/ci.yml`

Manual broader qualification/coverage/release/instrumentation matrix; unavailable arm64 runner infrastructure remains a hold.

**Source:** [.github/workflows/ci.yml](../../.github/workflows/ci.yml).

### `analysis_options.yaml`

Analyzer/lint selection and exclusions; inspect scope before treating clean analysis as whole-project proof.

**Source:** [analysis_options.yaml](../../analysis_options.yaml).

### `docs/branding/master.json`

Brand source metadata used for visual exports; not runtime/native configuration.

**Source:** [docs/branding/master.json](../../docs/branding/master.json).

### `docs/public/ci-workflow.example.yml`

Historical inactive publication example; never copy it over the maintained active workflows.

**Source:** [docs/public/ci-workflow.example.yml](../../docs/public/ci-workflow.example.yml).

### `pubspec.lock`

Exact root dependency resolution; reproducibility authority rather than an invitation to upgrade every outdated package.

**Source:** [pubspec.lock](../../pubspec.lock).

### `pubspec.yaml`

App identity, direct Dart/Flutter dependencies, assets and CPU-default hook configuration.

**Source:** [pubspec.yaml](../../pubspec.yaml).

## Android host and build

### `android/app/build.gradle.kts`

Android API/ABI, bytecode, test/coverage and build configuration; plugin versions come from settings/wrapper policy.

**Source:** [android/app/build.gradle.kts](../../android/app/build.gradle.kts).

### `android/app/proguard-rules.pro`

App shrinker/reflective/native keep policy; release runtime must validate any narrowing.

**Source:** [android/app/proguard-rules.pro](../../android/app/proguard-rules.pro).

### `android/app/src/main/java/com/vitalis/vitalis_app/MainActivity.java`

Flutter host/channel registration, device telemetry, memory events, notification permission and storage integration; the Java OS boundary.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/MainActivity.java](../../android/app/src/main/java/com/vitalis/vitalis_app/MainActivity.java).
**Declared types:** `MainActivity`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferActionReceiver.java`

Receives scoped notification transfer actions; forwards intent to durable control rather than mutating files directly.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferActionReceiver.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferActionReceiver.java).
**Declared types:** `TransferActionReceiver`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferController.java`

Validates Flutter transfer requests and coordinates manifests/schedulers; trust boundary for paths, IDs and immutable source URLs.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferController.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferController.java).
**Declared types:** `TransferController`, `StopPending`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferEngine.java`

Shared HTTP/Range/hash/write/retry engine used by both schedulers; owns transport execution and bounded writes.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferEngine.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferEngine.java).
**Declared types:** `TransferEngine`, `ProgressListener`, `ConnectionFactory`, `Sleeper`, `Clock`, `InvalidContentRange`, `OversizedContent`, `TruncatedContent`, `StopObserved`, `TransferOutcome`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferExecutionResult.java`

Typed engine result and stop/failure disposition; schedulers do not infer success from absence of an exception.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferExecutionResult.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferExecutionResult.java).
**Declared types:** `TransferExecutionResult`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferFailureCode.java`

Durable redacted failure-code vocabulary; distinguishes permanent validation errors from retryable transport failures.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferFailureCode.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferFailureCode.java).
**Declared types:** `TransferFailureCode`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferJobService.java`

API-34+ UIDT job lifecycle wrapper; asynchronous completion/stop/reschedule rules remain separate from engine work.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferJobService.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferJobService.java).
**Declared types:** `TransferJobService`, `OwnedJobThread`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferManifest.java`

Native durable transfer identity, shards, state/control generations and validation/projection fields; survives Flutter process loss.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferManifest.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferManifest.java).
**Declared types:** `TransferManifest`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferManifestStore.java`

Serialized atomic manifest persistence and revision handling; stale progress cannot overwrite newer stop intent.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferManifestStore.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferManifestStore.java).
**Declared types:** `TransferManifestStore`, `Transition`, `Operation`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferNotificationIds.java`

Stable scoped notification identity policy; avoids control collisions across jobs.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferNotificationIds.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferNotificationIds.java).
**Declared types:** `TransferNotificationIds`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferNotifications.java`

Transfer progress/control notifications and channel setup; communicates OS-owned work while Flutter is absent.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferNotifications.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferNotifications.java).
**Declared types:** `TransferNotifications`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferPolicy.java`

Named transport limits, deadlines and retry settings; shared engine/scheduler policy avoids duplicated magic values.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferPolicy.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferPolicy.java).
**Declared types:** `TransferPolicy`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferRecoveryAction.java`

Typed restart/retry/reconcile action vocabulary; recovery is explicit rather than silent reset.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferRecoveryAction.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferRecoveryAction.java).
**Declared types:** `TransferRecoveryAction`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferRunControl.java`

In-flight stop intent and acknowledgement/control generation; separates cancellation request from writer termination.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferRunControl.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferRunControl.java).
**Declared types:** `TransferRunControl`, `StopRequested`, `ConnectionClose`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferScheduler.java`

Chooses UIDT versus WorkManager and maintains scheduler identity; API selection stays outside Dart business logic.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferScheduler.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferScheduler.java).
**Declared types:** `TransferScheduler`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStopDisposition.java`

Typed user/system/terminal stop classifications; prevents every stop being blindly rescheduled.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStopDisposition.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStopDisposition.java).
**Declared types:** `TransferStopDisposition`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStopWorker.java`

Durable stop/reconciliation worker; obtains acknowledgement even when the original Flutter controller is gone.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStopWorker.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStopWorker.java).
**Declared types:** `TransferStopWorker`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStoragePreflight.java`

Android allocatable-storage checks through a background task queue; prevents large-file preflight blocking the UI thread.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStoragePreflight.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferStoragePreflight.java).
**Declared types:** `TransferStoragePreflight`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferWorker.java`

API-28–33 foreground WorkManager execution wrapper; propagates OS stop and engine outcomes.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferWorker.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferWorker.java).
**Declared types:** `TransferWorker`.

### `android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferWriterLease.java`

Exclusive cross-process writer lease; prevents duplicate native writers or deletion racing a live writer.

**Source:** [android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferWriterLease.java](../../android/app/src/main/java/com/vitalis/vitalis_app/transfer/TransferWriterLease.java).
**Declared types:** `TransferWriterLease`.

### `android/build.gradle.kts`

Shared Android repositories/output/task configuration; root of the Gradle application build.

**Source:** [android/build.gradle.kts](../../android/build.gradle.kts).

### `android/gradle.properties`

Gradle/Android build options; separate from user runtime preferences.

**Source:** [android/gradle.properties](../../android/gradle.properties).

### `android/gradle/wrapper/gradle-wrapper.properties`

Locked Gradle distribution/checksum/bootstrap deadline; wrapper source authority.

**Source:** [android/gradle/wrapper/gradle-wrapper.properties](../../android/gradle/wrapper/gradle-wrapper.properties).

### `android/gradlew`

POSIX checked-in Gradle wrapper entry point; generated wrapper infrastructure, not app code.

**Source:** [android/gradlew](../../android/gradlew).

### `android/gradlew.bat`

Windows checked-in Gradle wrapper entry point; forwards to the verified distribution.

**Source:** [android/gradlew.bat](../../android/gradlew.bat).

### `android/settings.gradle.kts`

Flutter plugin inclusion and AGP/Kotlin versions; resolves Android build plugins.

**Source:** [android/settings.gradle.kts](../../android/settings.gradle.kts).

### `android/test-dependency-policy.gradle`

Immutable AndroidX test dependency selection across app/plugin configurations; prevents inconsistent instrumentation resolution.

**Source:** [android/test-dependency-policy.gradle](../../android/test-dependency-policy.gradle).

## lib

### `lib/app_router.dart`

Named routes and route construction; separates navigation identity from screens and gates developer navigation.

**Source:** [lib/app_router.dart](../../lib/app_router.dart).
**Declared types:** `AppRoutes`.
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart).
**Direct test references:** [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/widgets/home_screen_test.dart](../../test/widgets/home_screen_test.dart).

### `lib/main.dart`

Composition root and first-frame entry point; wires observable startup and error boundaries before constructing the app.

**Source:** [lib/main.dart](../../lib/main.dart).
**Declared types:** `VitalisApp`.

## lib/constants

### `lib/constants/app_colors.dart`

Shared colour palette; avoids separate screens inventing inconsistent visual values.

**Source:** [lib/constants/app_colors.dart](../../lib/constants/app_colors.dart).
**Declared types:** `AppColors`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart), [lib/theme/app_theme.dart](../../lib/theme/app_theme.dart).

### `lib/constants/app_constants.dart`

App/database identity and bounded context/storage defaults; central policy values are not evidence of effective device performance.

**Source:** [lib/constants/app_constants.dart](../../lib/constants/app_constants.dart).
**Declared types:** `AppConstants`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/models/runtime_profile.dart](../../lib/models/runtime_profile.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart), [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/modals/chat_name_modal.dart](../../lib/screens/modals/chat_name_modal.dart), [lib/screens/modals/note_edit_modal.dart](../../lib/screens/modals/note_edit_modal.dart); 4 additional references in the inventory.
**Direct test references:** [test/database/installation_journal_test.dart](../../test/database/installation_journal_test.dart), [test/database/model_installation_journal_test.dart](../../test/database/model_installation_journal_test.dart), [test/database_test.dart](../../test/database_test.dart), [test/models/runtime_profile_test.dart](../../test/models/runtime_profile_test.dart), [test/providers/chat_settings_persistence_test.dart](../../test/providers/chat_settings_persistence_test.dart); more in the test map.

### `lib/constants/app_metrics.dart`

Shared spacing/dimension values; keeps presentation measurements separate from inference budgets.

**Source:** [lib/constants/app_metrics.dart](../../lib/constants/app_metrics.dart).
**Declared types:** `AppMetrics`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart), [lib/theme/app_theme.dart](../../lib/theme/app_theme.dart), [lib/widgets/attached_notes_bar.dart](../../lib/widgets/attached_notes_bar.dart), [lib/widgets/chat_input_field.dart](../../lib/widgets/chat_input_field.dart), [lib/widgets/conversation_status_bar.dart](../../lib/widgets/conversation_status_bar.dart), [lib/widgets/message_bubble.dart](../../lib/widgets/message_bubble.dart); 1 additional references in the inventory.

### `lib/constants/app_strings.dart`

Shared interface wording; keeps repeated labels and validation text consistent.

**Source:** [lib/constants/app_strings.dart](../../lib/constants/app_strings.dart).
**Declared types:** `AppStrings`.
**Referenced by:** [lib/models/generation_setting.dart](../../lib/models/generation_setting.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/modals/chat_history_modal.dart](../../lib/screens/modals/chat_history_modal.dart), [lib/screens/modals/chat_name_modal.dart](../../lib/screens/modals/chat_name_modal.dart), [lib/screens/modals/hamburger_menu.dart](../../lib/screens/modals/hamburger_menu.dart), [lib/screens/modals/note_edit_modal.dart](../../lib/screens/modals/note_edit_modal.dart), [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart); 11 additional references in the inventory.
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/widget_test.dart](../../test/widget_test.dart), [test/widgets/chat_history_read_only_test.dart](../../test/widgets/chat_history_read_only_test.dart), [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart), [test/widgets/conversation_design_test.dart](../../test/widgets/conversation_design_test.dart); more in the test map.

### `lib/constants/app_typography.dart`

Shared text styles; supplies a consistent visual hierarchy.

**Source:** [lib/constants/app_typography.dart](../../lib/constants/app_typography.dart).
**Declared types:** `AppTypography`.
**Referenced by:** [lib/theme/app_theme.dart](../../lib/theme/app_theme.dart).

## lib/database

### `lib/database/database_helper.dart`

SQLite opening, schema upgrades and record queries; central persistence authority for chats, content, models, jobs and cache.

**Source:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart).
**Declared types:** `DatabaseHelper`.
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart), [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart), [lib/services/legacy_model_preference_migration.dart](../../lib/services/legacy_model_preference_migration.dart), [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart), [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart); 3 additional references in the inventory.
**Direct test references:** [test/database/installation_journal_test.dart](../../test/database/installation_journal_test.dart), [test/database/model_installation_journal_test.dart](../../test/database/model_installation_journal_test.dart), [test/database_test.dart](../../test/database_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/chat_deletion_persistence_test.dart](../../test/providers/chat_deletion_persistence_test.dart); more in the test map.

### `lib/database/installation_journal_schema.dart`

Creates schema-8 installation intent/shard tables and constraints; records recoverable multi-step filesystem/database work.

**Source:** [lib/database/installation_journal_schema.dart](../../lib/database/installation_journal_schema.dart).
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart).

### `lib/database/model_installation_journal.dart`

Reads and revises durable installation snapshots; persists intent without independently deleting model files.

**Source:** [lib/database/model_installation_journal.dart](../../lib/database/model_installation_journal.dart).
**Declared types:** `ModelInstallationJournal`.
**Referenced by:** [lib/services/model_installation_promoter.dart](../../lib/services/model_installation_promoter.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).
**Direct test references:** [test/database/model_installation_journal_test.dart](../../test/database/model_installation_journal_test.dart), [test/services/model_installation_promoter_test.dart](../../test/services/model_installation_promoter_test.dart), [test/services/model_shard_restorer_test.dart](../../test/services/model_shard_restorer_test.dart).

### `lib/database/model_installation_projection.dart`

Applies validated installation records to the registry transactionally; separates SQL projection from native validation and file promotion.

**Source:** [lib/database/model_installation_projection.dart](../../lib/database/model_installation_projection.dart).
**Declared types:** `ModelInstallationProjection`.
**Referenced by:** [lib/database/model_installation_journal.dart](../../lib/database/model_installation_journal.dart).

### `lib/database/windows_database.dart`

Initializes desktop SQLite FFI and application-support storage during observable startup; preserves the shared schema.

**Source:** [lib/database/windows_database.dart](../../lib/database/windows_database.dart).
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/database/windows_database_test.dart](../../test/database/windows_database_test.dart).

## lib/models

### `lib/models/bundled_model_manifest.dart`

Immutable default-model repository, revision, digest and metadata authority; prevents trusting arbitrary first-downloaded bytes.

**Source:** [lib/models/bundled_model_manifest.dart](../../lib/models/bundled_model_manifest.dart).
**Declared types:** `BundledModelManifest`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/main.dart](../../lib/main.dart), [lib/models/model_settings.dart](../../lib/models/model_settings.dart), [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart), [lib/services/legacy_model_preference_migration.dart](../../lib/services/legacy_model_preference_migration.dart), [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart); 4 additional references in the inventory.
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/services/bundled_install_adapter_test.dart](../../test/services/bundled_install_adapter_test.dart), [test/services/legacy_model_preference_migration_test.dart](../../test/services/legacy_model_preference_migration_test.dart), [test/services/model_downloader_test.dart](../../test/services/model_downloader_test.dart), [test/services/model_registry_service_test.dart](../../test/services/model_registry_service_test.dart); more in the test map.

### `lib/models/chat.dart`

Conversation identity/title/timestamps and map conversion; the stable record around message history.

**Source:** [lib/models/chat.dart](../../lib/models/chat.dart).
**Declared types:** `Chat`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/providers/chat_deletion_persistence_test.dart](../../test/providers/chat_deletion_persistence_test.dart), [test/providers/chat_deletion_test.dart](../../test/providers/chat_deletion_test.dart), [test/providers/chat_history_status_test.dart](../../test/providers/chat_history_status_test.dart), [test/providers/chat_logging_privacy_test.dart](../../test/providers/chat_logging_privacy_test.dart); more in the test map.

### `lib/models/chat_deletion_error.dart`

Typed redacted deletion/pending failures; lets the UI distinguish unfinished deletion from success.

**Source:** [lib/models/chat_deletion_error.dart](../../lib/models/chat_deletion_error.dart).
**Declared types:** `ChatDeletionError`, `ChatDeletionPending`.
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/widgets/startup_mutation_access.dart](../../lib/widgets/startup_mutation_access.dart).
**Direct test references:** [test/widgets/chat_history_read_only_test.dart](../../test/widgets/chat_history_read_only_test.dart).

### `lib/models/context_plan_result.dart`

Selected formatted context, token budgets and exclusion counts; explains what inference actually receives.

**Source:** [lib/models/context_plan_result.dart](../../lib/models/context_plan_result.dart).
**Declared types:** `ContextPlanResult`.
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/services/context_planner.dart](../../lib/services/context_planner.dart).

### `lib/models/device_safety_policy.dart`

Nullable sensor snapshot and safety/cooldown rules; separates policy from platform sensor collection.

**Source:** [lib/models/device_safety_policy.dart](../../lib/models/device_safety_policy.dart).
**Declared types:** `DeviceSafetyClock`, `DeviceSafetySnapshot`, `DeviceSafetyPolicy`.
**Referenced by:** [lib/services/hardware_sentinel_service.dart](../../lib/services/hardware_sentinel_service.dart), [lib/services/memory_pressure_service.dart](../../lib/services/memory_pressure_service.dart).
**Direct test references:** [test/models/device_safety_policy_test.dart](../../test/models/device_safety_policy_test.dart), [test/services/hardware_sentinel_service_test.dart](../../test/services/hardware_sentinel_service_test.dart), [test/services/memory_pressure_service_test.dart](../../test/services/memory_pressure_service_test.dart), [test/services/safety_logging_privacy_test.dart](../../test/services/safety_logging_privacy_test.dart).

### `lib/models/diagnostics_policy.dart`

Named diagnostic limits/timing; bounds local logging behaviour.

**Source:** [lib/models/diagnostics_policy.dart](../../lib/models/diagnostics_policy.dart).
**Declared types:** `DiagnosticsPolicy`.
**Referenced by:** [lib/utils/app_logger.dart](../../lib/utils/app_logger.dart).

### `lib/models/generation_setting.dart`

Generation-setting metadata and presentation limits/presets; aligns numeric editors with validated runtime settings.

**Source:** [lib/models/generation_setting.dart](../../lib/models/generation_setting.dart).
**Declared types:** `GenerationSettingsPresentationPolicy`, `GenerationSetting`.
**Referenced by:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart).
**Direct test references:** [test/models/generation_setting_test.dart](../../test/models/generation_setting_test.dart).

### `lib/models/generation_watchdog_policy.dart`

Progress timeout and maximum-duration configuration; bounds waiting without pretending native work terminated.

**Source:** [lib/models/generation_watchdog_policy.dart](../../lib/models/generation_watchdog_policy.dart).
**Declared types:** `WatchdogTimerFactory`, `GenerationWatchdogPolicy`.
**Referenced by:** [lib/services/chat_state_controller.dart](../../lib/services/chat_state_controller.dart).
**Direct test references:** [test/services/chat_state_controller_test.dart](../../test/services/chat_state_controller_test.dart), [test/services/runtime_watchdog_policy_test.dart](../../test/services/runtime_watchdog_policy_test.dart), [test_native/owner_close_recovery_test.dart](../../test_native/owner_close_recovery_test.dart).

### `lib/models/hub_model.dart`

Hub summaries, variants/shards, search pages and fit assessments; typed network/catalogue data for the library.

**Source:** [lib/models/hub_model.dart](../../lib/models/hub_model.dart).
**Declared types:** `HubSort`, `DeviceFitLevel`, `HubModelSummary`, `GgufFile`, `GgufVariant`, `HubSearchPage`, `DeviceFitAssessment`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/services/device_fit_estimator.dart](../../lib/services/device_fit_estimator.dart), [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart), [lib/services/model_hub_client.dart](../../lib/services/model_hub_client.dart), [lib/services/model_update_service.dart](../../lib/services/model_update_service.dart), [lib/services/persistent_hub_search_cache.dart](../../lib/services/persistent_hub_search_cache.dart).
**Direct test references:** [test/database_test.dart](../../test/database_test.dart), [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart), [test/services/device_fit_estimator_test.dart](../../test/services/device_fit_estimator_test.dart); more in the test map.

### `lib/models/imported_model_file.dart`

Picker-neutral imported-file contracts; avoids tying registry logic directly to a widget or document-picker implementation.

**Source:** [lib/models/imported_model_file.dart](../../lib/models/imported_model_file.dart).
**Declared types:** `ImportedModelFile`, `ModelImportPicker`, `ModelImportSetPicker`.
**Referenced by:** [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).

### `lib/models/message.dart`

Role/text/timestamp/error record; distinguishes conversation turns from failed or incomplete records.

**Source:** [lib/models/message.dart](../../lib/models/message.dart).
**Declared types:** `MessageRole`, `Message`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/services/context_planner.dart](../../lib/services/context_planner.dart), [lib/widgets/message_bubble.dart](../../lib/widgets/message_bubble.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/database_test.dart](../../test/database_test.dart), [test/models/message_test.dart](../../test/models/message_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/chat_deletion_persistence_test.dart](../../test/providers/chat_deletion_persistence_test.dart); more in the test map.

### `lib/models/model_defaults.dart`

New-chat and migration sampling defaults; one authority prevents database/UI defaults drifting.

**Source:** [lib/models/model_defaults.dart](../../lib/models/model_defaults.dart).
**Declared types:** `ModelDefaults`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/models/generation_setting.dart](../../lib/models/generation_setting.dart), [lib/models/model_settings.dart](../../lib/models/model_settings.dart).
**Direct test references:** [test/models/generation_setting_test.dart](../../test/models/generation_setting_test.dart).

### `lib/models/model_descriptor.dart`

Persistent model identity, local/remote metadata, install and compatibility state; per-chat selection refers to this identity.

**Source:** [lib/models/model_descriptor.dart](../../lib/models/model_descriptor.dart).
**Declared types:** `ModelDescriptor`.
**Referenced by:** [lib/database/model_installation_journal.dart](../../lib/database/model_installation_journal.dart), [lib/main.dart](../../lib/main.dart), [lib/models/runtime_profile.dart](../../lib/models/runtime_profile.dart), [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/services/legacy_model_preference_migration.dart](../../lib/services/legacy_model_preference_migration.dart); 7 additional references in the inventory.
**Direct test references:** [test/database/model_installation_journal_test.dart](../../test/database/model_installation_journal_test.dart), [test/models/runtime_profile_test.dart](../../test/models/runtime_profile_test.dart), [test/models/thinking_capability_test.dart](../../test/models/thinking_capability_test.dart), [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart), [test/providers/initial_model_chat_test.dart](../../test/providers/initial_model_chat_test.dart); more in the test map.

### `lib/models/model_download_job.dart`

Persistent download job state/progress; separates job lifetime from an open screen.

**Source:** [lib/models/model_download_job.dart](../../lib/models/model_download_job.dart).
**Declared types:** `ModelDownloadJobState`, `ModelDownloadJob`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart), [lib/services/model_update_service.dart](../../lib/services/model_update_service.dart).
**Direct test references:** [test/models/model_download_job_test.dart](../../test/models/model_download_job_test.dart), [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart), [test/services/android_durable_transfer_adapter_test.dart](../../test/services/android_durable_transfer_adapter_test.dart); more in the test map.

### `lib/models/model_installation.dart`

Journal phases, hash authority, shards and snapshots; makes partial installation state explicit.

**Source:** [lib/models/model_installation.dart](../../lib/models/model_installation.dart).
**Declared types:** `InstallationPhase`, `ModelHashAuthority`, `InstallationConflict`, `InstallationShard`, `InstallationSnapshot`.
**Referenced by:** [lib/database/model_installation_journal.dart](../../lib/database/model_installation_journal.dart), [lib/models/restoration_artifact.dart](../../lib/models/restoration_artifact.dart), [lib/services/model_installation_promoter.dart](../../lib/services/model_installation_promoter.dart), [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).
**Direct test references:** [test/database/model_installation_journal_test.dart](../../test/database/model_installation_journal_test.dart), [test/services/model_installation_promoter_test.dart](../../test/services/model_installation_promoter_test.dart), [test/services/model_shard_restorer_test.dart](../../test/services/model_shard_restorer_test.dart).

### `lib/models/model_library_policy.dart`

Download limits, storage estimates, large-model threshold, immutable URI and compatibility-probe policies; validates trust boundaries.

**Source:** [lib/models/model_library_policy.dart](../../lib/models/model_library_policy.dart).
**Declared types:** `ModelLibraryPolicy`, `HubArtifactUriPolicy`, `CompatibilityProbePolicy`.
**Referenced by:** [lib/models/hub_model.dart](../../lib/models/hub_model.dart), [lib/models/model_descriptor.dart](../../lib/models/model_descriptor.dart), [lib/models/runtime_profile.dart](../../lib/models/runtime_profile.dart), [lib/services/device_fit_estimator.dart](../../lib/services/device_fit_estimator.dart), [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart), [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart).
**Direct test references:** [test/models/hub_artifact_uri_policy_test.dart](../../test/models/hub_artifact_uri_policy_test.dart).

### `lib/models/model_settings.dart`

Per-chat model, sampling, thinking and runtime override settings; requested configuration is separate from effective native profile.

**Source:** [lib/models/model_settings.dart](../../lib/models/model_settings.dart).
**Declared types:** `TuningMode`, `AccelerationPreference`, `ThinkingMode`, `ModelSettings`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/models/generation_setting.dart](../../lib/models/generation_setting.dart), [lib/models/runtime_profile.dart](../../lib/models/runtime_profile.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/database_test.dart](../../test/database_test.dart), [test/models/generation_setting_test.dart](../../test/models/generation_setting_test.dart), [test/models/model_settings_test.dart](../../test/models/model_settings_test.dart), [test/models/runtime_profile_test.dart](../../test/models/runtime_profile_test.dart); more in the test map.

### `lib/models/model_storage_error.dart`

Typed busy, identity-mismatch, picker-cancel and safety-stop errors; prevents generic errors being mistaken for corrupt files.

**Source:** [lib/models/model_storage_error.dart](../../lib/models/model_storage_error.dart).
**Declared types:** `ModelStorageBusy`, `ModelIdentityMismatch`, `ModelSelectionCancelled`, `ModelProbeSafetyStop`.
**Referenced by:** [lib/models/restoration_artifact.dart](../../lib/models/restoration_artifact.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/services/model_recovery_controller.dart](../../lib/services/model_recovery_controller.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).
**Direct test references:** [test/services/model_recovery_controller_test.dart](../../test/services/model_recovery_controller_test.dart).

### `lib/models/model_verification_phase.dart`

Verification progress phases/callback contract; exposes hashing, metadata and native checks without activating a model.

**Source:** [lib/models/model_verification_phase.dart](../../lib/models/model_verification_phase.dart).
**Declared types:** `ModelVerificationPhase`, `ModelVerificationPhaseSink`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/services/model_recovery_controller.dart](../../lib/services/model_recovery_controller.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart), [lib/widgets/model_recovery_status_label.dart](../../lib/widgets/model_recovery_status_label.dart).
**Direct test references:** [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/services/model_download_manager_test.dart](../../test/services/model_download_manager_test.dart), [test/services/model_recovery_controller_test.dart](../../test/services/model_recovery_controller_test.dart), [test/services/model_registry_service_test.dart](../../test/services/model_registry_service_test.dart), [test/widgets/model_recovery_status_label_test.dart](../../test/widgets/model_recovery_status_label_test.dart); more in the test map.

### `lib/models/note.dart`

Reusable note text and persistence mapping; supplies attached context independently of chat history.

**Source:** [lib/models/note.dart](../../lib/models/note.dart).
**Declared types:** `Note`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/modals/note_edit_modal.dart](../../lib/screens/modals/note_edit_modal.dart), [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart), [lib/services/context_planner.dart](../../lib/services/context_planner.dart); 1 additional references in the inventory.
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/database_test.dart](../../test/database_test.dart), [test/providers/chat_deletion_persistence_test.dart](../../test/providers/chat_deletion_persistence_test.dart), [test/providers/chat_deletion_test.dart](../../test/providers/chat_deletion_test.dart), [test/providers/chat_logging_privacy_test.dart](../../test/providers/chat_logging_privacy_test.dart); more in the test map.

### `lib/models/persistence_policy.dart`

Named history-pagination policy; avoids independent page-size defaults.

**Source:** [lib/models/persistence_policy.dart](../../lib/models/persistence_policy.dart).
**Declared types:** `PaginationPolicy`.
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart).
**Direct test references:** [test/providers/chat_logging_privacy_test.dart](../../test/providers/chat_logging_privacy_test.dart).

### `lib/models/persona.dart`

Named system-prompt preset; changes instructions rather than model weights.

**Source:** [lib/models/persona.dart](../../lib/models/persona.dart).
**Declared types:** `Persona`.
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart), [lib/screens/modals/persona_selection_modal.dart](../../lib/screens/modals/persona_selection_modal.dart), [lib/widgets/attached_notes_bar.dart](../../lib/widgets/attached_notes_bar.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/database_test.dart](../../test/database_test.dart), [test/providers/chat_logging_privacy_test.dart](../../test/providers/chat_logging_privacy_test.dart), [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart), [test/providers/saved_content_logging_privacy_test.dart](../../test/providers/saved_content_logging_privacy_test.dart); more in the test map.

### `lib/models/restoration_artifact.dart`

Exact file/shard identity for recovery; retains original hash authority instead of upgrading a local hash to publisher trust.

**Source:** [lib/models/restoration_artifact.dart](../../lib/models/restoration_artifact.dart).
**Declared types:** `RestorationArtifact`.
**Referenced by:** [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).

### `lib/models/runtime_capabilities.dart`

Device/backend capability snapshot and profile-cache identity; controls safe tuning and invalidation.

**Source:** [lib/models/runtime_capabilities.dart](../../lib/models/runtime_capabilities.dart).
**Declared types:** `RuntimeCapabilities`, `RuntimeProfileKey`.
**Referenced by:** [lib/models/runtime_profile.dart](../../lib/models/runtime_profile.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart), [lib/services/runtime_auto_tuner.dart](../../lib/services/runtime_auto_tuner.dart), [lib/services/runtime_capabilities_provider.dart](../../lib/services/runtime_capabilities_provider.dart), [lib/services/runtime_profile_store.dart](../../lib/services/runtime_profile_store.dart).
**Direct test references:** [test/models/runtime_profile_test.dart](../../test/models/runtime_profile_test.dart), [test/services/model_registry_service_test.dart](../../test/services/model_registry_service_test.dart), [test/services/model_registry_uninstall_test.dart](../../test/services/model_registry_uninstall_test.dart), [test/services/model_warmup_service_test.dart](../../test/services/model_warmup_service_test.dart), [test/services/runtime_auto_tuner_test.dart](../../test/services/runtime_auto_tuner_test.dart); more in the test map.

### `lib/models/runtime_profile.dart`

Effective context/output/thread/batch/backend-related execution configuration and conservative derivation; validates requested overrides.

**Source:** [lib/models/runtime_profile.dart](../../lib/models/runtime_profile.dart).
**Declared types:** `RuntimeProfile`.
**Referenced by:** [lib/services/backend_self_test.dart](../../lib/services/backend_self_test.dart), [lib/services/context_planner.dart](../../lib/services/context_planner.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart), [lib/services/runtime_auto_tuner.dart](../../lib/services/runtime_auto_tuner.dart), [lib/services/runtime_profile_store.dart](../../lib/services/runtime_profile_store.dart).
**Direct test references:** [test/models/runtime_profile_test.dart](../../test/models/runtime_profile_test.dart), [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart), [test/providers/generation_recovery_test.dart](../../test/providers/generation_recovery_test.dart), [test/services/context_planner_test.dart](../../test/services/context_planner_test.dart), [test/services/model_registry_service_test.dart](../../test/services/model_registry_service_test.dart); more in the test map.

### `lib/models/startup_capabilities.dart`

Separate database/migration/safety/model and access capabilities; one ready subsystem cannot grant every permission.

**Source:** [lib/models/startup_capabilities.dart](../../lib/models/startup_capabilities.dart).
**Declared types:** `StartupModelReadiness`, `StartupCapabilities`.
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/services/model_startup_inspector.dart](../../lib/services/model_startup_inspector.dart), [lib/services/selected_model_readiness.dart](../../lib/services/selected_model_readiness.dart), [lib/services/startup_access_guard.dart](../../lib/services/startup_access_guard.dart), [lib/services/startup_capability_source.dart](../../lib/services/startup_capability_source.dart), [lib/services/startup_coordinator.dart](../../lib/services/startup_coordinator.dart).
**Direct test references:** [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart), [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart), [test/providers/initial_model_chat_test.dart](../../test/providers/initial_model_chat_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/providers/startup_access_guard_test.dart](../../test/providers/startup_access_guard_test.dart); more in the test map.

## lib/providers

### `lib/providers/chat_provider.dart`

Observable chat/history/settings/attachments/persona orchestration and persistence; maintains selection epochs and pending saves/deletions.

**Source:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart).
**Declared types:** `ChatProvider`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart), [lib/screens/modals/chat_history_modal.dart](../../lib/screens/modals/chat_history_modal.dart), [lib/screens/modals/persona_selection_modal.dart](../../lib/screens/modals/persona_selection_modal.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/ui/debug_settings_screen.dart](../../lib/ui/debug_settings_screen.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/database_test.dart](../../test/database_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/chat_deletion_persistence_test.dart](../../test/providers/chat_deletion_persistence_test.dart), [test/providers/chat_deletion_test.dart](../../test/providers/chat_deletion_test.dart); more in the test map.

### `lib/providers/chat_settings_persistence.dart`

Part of ChatProvider that serializes settings writes and settlement; protects newer edits from delayed older writes.

**Source:** [lib/providers/chat_settings_persistence.dart](../../lib/providers/chat_settings_persistence.dart).
**Declared types:** `ChatSettingsSaveError`, `_ChatSettingsPersistence`.
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart).

### `lib/providers/generation_provider.dart`

Observable send/stream/stop/recovery lifecycle and context/native metrics; coordinates warmup and the chat state controller.

**Source:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart).
**Declared types:** `GenerationProvider`.
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/ui/debug_settings_screen.dart](../../lib/ui/debug_settings_screen.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [test/database_test.dart](../../test/database_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/chat_deletion_persistence_test.dart](../../test/providers/chat_deletion_persistence_test.dart), [test/providers/chat_deletion_test.dart](../../test/providers/chat_deletion_test.dart), [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart); more in the test map.

### `lib/providers/generation_recovery.dart`

GenerationProvider lifecycle part for retained cleanup/recovery actors; prevents references being dropped before termination is established.

**Source:** [lib/providers/generation_recovery.dart](../../lib/providers/generation_recovery.dart).
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart).

### `lib/providers/health_provider.dart`

UI-facing safety/health observation; widgets subscribe without owning sensor collection.

**Source:** [lib/providers/health_provider.dart](../../lib/providers/health_provider.dart).
**Declared types:** `HealthProvider`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/ui/debug_settings_screen.dart](../../lib/ui/debug_settings_screen.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [test/providers/health_provider_test.dart](../../test/providers/health_provider_test.dart), [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart).

### `lib/providers/model_library_provider.dart`

Search/cache/library/download/recovery/update observable state; keeps long-lived model actions outside screen-local state.

**Source:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart).
**Declared types:** `ModelLibraryStatus`, `ModelLibraryCacheState`, `ModelLibraryProvider`.
**Referenced by:** [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart), [test/widgets/model_library_screen_states_test.dart](../../test/widgets/model_library_screen_states_test.dart).

### `lib/providers/note_provider.dart`

Note CRUD and access checks; central state for note lists/editors.

**Source:** [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart).
**Declared types:** `NoteProvider`.
**Referenced by:** [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/database_test.dart](../../test/database_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/saved_content_logging_privacy_test.dart](../../test/providers/saved_content_logging_privacy_test.dart), [test/providers/startup_access_guard_test.dart](../../test/providers/startup_access_guard_test.dart); more in the test map.

### `lib/providers/persona_provider.dart`

Persona CRUD/mapping state and committed change callbacks; keeps active-chat instructions synchronized with stored personas.

**Source:** [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart).
**Declared types:** `PersonaProvider`.
**Referenced by:** [lib/screens/modals/persona_selection_modal.dart](../../lib/screens/modals/persona_selection_modal.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/database_test.dart](../../test/database_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/saved_content_logging_privacy_test.dart](../../test/providers/saved_content_logging_privacy_test.dart), [test/providers/startup_access_guard_test.dart](../../test/providers/startup_access_guard_test.dart); more in the test map.

### `lib/providers/theme_provider.dart`

Persisted appearance preference and ordered preference writes; theme survives navigation/restart.

**Source:** [lib/providers/theme_provider.dart](../../lib/providers/theme_provider.dart).
**Declared types:** `ThemePreferenceManifest`, `ThemeProvider`.
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/providers/theme_lifecycle_test.dart](../../test/providers/theme_lifecycle_test.dart), [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart), [test/widgets/settings_recovery_test.dart](../../test/widgets/settings_recovery_test.dart).

## lib/screens

### `lib/screens/chat_screen.dart`

Conversation surface and lazy runtime preparation; binds composer, response rendering and selected-model readiness.

**Source:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).
**Declared types:** `ChatScreen`, `_ChatScreenState`.
**Referenced by:** [lib/app_router.dart](../../lib/app_router.dart).
**Direct test references:** [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart).

### `lib/screens/chats_overview_screen.dart`

Conversation overview and selection actions; entry point into stored histories.

**Source:** [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart).
**Declared types:** `ChatsOverviewScreen`, `_ChatsOverviewScreenState`.
**Referenced by:** [lib/screens/home_screen.dart](../../lib/screens/home_screen.dart).
**Direct test references:** [test/widgets/home_screen_test.dart](../../test/widgets/home_screen_test.dart).

### `lib/screens/home_screen.dart`

Home destinations with lazy mounting; avoids initializing every destination immediately.

**Source:** [lib/screens/home_screen.dart](../../lib/screens/home_screen.dart).
**Declared types:** `HomeScreen`, `_HomeScreenState`.
**Referenced by:** [lib/app_router.dart](../../lib/app_router.dart).
**Direct test references:** [test/widgets/home_screen_test.dart](../../test/widgets/home_screen_test.dart).

### `lib/screens/model_library_screen.dart`

Recommended/search/installed/download library presentation, filters and model actions; delegates stateful operations to providers/services.

**Source:** [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart).
**Declared types:** `ModelLibraryScreen`, `_ModelLibraryScreenState`, `_ModelSizeFilter`, `_InstalledModelAction`, `_SearchFiltersSheet`, `_SearchFiltersSheetState`.
**Referenced by:** [lib/app_router.dart](../../lib/app_router.dart), [lib/screens/home_screen.dart](../../lib/screens/home_screen.dart).
**Direct test references:** [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/widgets/model_library_screen_states_test.dart](../../test/widgets/model_library_screen_states_test.dart).

### `lib/screens/saved_screen.dart`

Saved-content destination; exposes reusable notes/personas through the conversation-focused navigation.

**Source:** [lib/screens/saved_screen.dart](../../lib/screens/saved_screen.dart).
**Declared types:** `SavedScreen`.
**Referenced by:** [lib/screens/home_screen.dart](../../lib/screens/home_screen.dart).
**Direct test references:** [test/widgets/saved_screen_test.dart](../../test/widgets/saved_screen_test.dart).

### `lib/screens/settings_app_sections.dart`

App-level appearance/privacy sections, as a settings part; separates global choices from current-chat inference settings.

**Source:** [lib/screens/settings_app_sections.dart](../../lib/screens/settings_app_sections.dart).
**Declared types:** `_AppSettingsSections`.
**Referenced by:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart).

### `lib/screens/settings_chat_sections.dart`

Per-chat model/generation/runtime sections, as a settings part; shows requested/effective model controls.

**Source:** [lib/screens/settings_chat_sections.dart](../../lib/screens/settings_chat_sections.dart).
**Declared types:** `_ChatSettingsSections`.
**Referenced by:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart).

### `lib/screens/settings_mutation_actions.dart`

Settings mutation/reset actions, as a settings part; preserves concurrent edits and coordinates profile invalidation/readiness.

**Source:** [lib/screens/settings_mutation_actions.dart](../../lib/screens/settings_mutation_actions.dart).
**Declared types:** `_SettingsMutationActions`.
**Referenced by:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart).

### `lib/screens/settings_screen.dart`

App/chat settings shell and lifecycle; joins the section parts without duplicating routing.

**Source:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart).
**Declared types:** `SettingsScreen`, `_SettingsScreenState`, `_DebugTapGate`, `_DebugTapGateState`.
**Referenced by:** [lib/app_router.dart](../../lib/app_router.dart), [lib/screens/home_screen.dart](../../lib/screens/home_screen.dart).
**Direct test references:** [test/widgets/settings_recovery_test.dart](../../test/widgets/settings_recovery_test.dart).

### `lib/screens/setup_screen.dart`

First-run/default-model setup and readiness entry; helps a user obtain a model before conversation use.

**Source:** [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart).
**Declared types:** `SetupScreen`, `_SetupScreenState`.
**Referenced by:** [lib/app_router.dart](../../lib/app_router.dart).

## lib/screens/modals

### `lib/screens/modals/chat_history_modal.dart`

Compact saved-history selector; provides navigation without embedding persistence logic in the composer.

**Source:** [lib/screens/modals/chat_history_modal.dart](../../lib/screens/modals/chat_history_modal.dart).
**Declared types:** `ChatHistoryModal`, `_ChatHistoryModalState`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart).
**Direct test references:** [test/widgets/chat_history_read_only_test.dart](../../test/widgets/chat_history_read_only_test.dart).

### `lib/screens/modals/chat_name_modal.dart`

Chat title editor; validates and submits explicit rename intent.

**Source:** [lib/screens/modals/chat_name_modal.dart](../../lib/screens/modals/chat_name_modal.dart).
**Declared types:** `ChatNameModal`, `_ChatNameModalState`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart).

### `lib/screens/modals/hamburger_menu.dart`

Shared menu/navigation actions; keeps menu presentation reusable.

**Source:** [lib/screens/modals/hamburger_menu.dart](../../lib/screens/modals/hamburger_menu.dart).
**Declared types:** `HamburgerMenu`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).

### `lib/screens/modals/note_edit_modal.dart`

Note creation/edit dialog with semantics and pending-write handling; protects stored content from duplicate submissions.

**Source:** [lib/screens/modals/note_edit_modal.dart](../../lib/screens/modals/note_edit_modal.dart).
**Declared types:** `NoteEditModal`, `_NoteEditModalState`.
**Referenced by:** [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart).
**Direct test references:** [test/widgets/saved_content_read_only_test.dart](../../test/widgets/saved_content_read_only_test.dart).

### `lib/screens/modals/notes_list_selection_modal.dart`

Note-attachment selection; supports persistent context associations rather than transient prompt-only text.

**Source:** [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart).
**Declared types:** `NotesListSelectionModal`, `_NotesListSelectionModalState`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/saved_screen.dart](../../lib/screens/saved_screen.dart).
**Direct test references:** [test/widgets/saved_content_read_only_test.dart](../../test/widgets/saved_content_read_only_test.dart).

### `lib/screens/modals/persona_selection_modal.dart`

Persona selection/creation dialog; manages the intentional one-active-persona-per-chat choice.

**Source:** [lib/screens/modals/persona_selection_modal.dart](../../lib/screens/modals/persona_selection_modal.dart).
**Declared types:** `PersonaSelectionModal`, `_PersonaSelectionModalState`, `_CreatePersonaDialog`, `_CreatePersonaDialogState`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/saved_screen.dart](../../lib/screens/saved_screen.dart).
**Direct test references:** [test/widgets/persona_selection_persistence_test.dart](../../test/widgets/persona_selection_persistence_test.dart), [test/widgets/saved_content_read_only_test.dart](../../test/widgets/saved_content_read_only_test.dart), [test/widgets/saved_screen_test.dart](../../test/widgets/saved_screen_test.dart).

## lib/services

### `lib/services/application_error_reporter.dart`

Framework/platform exception boundary; reports redacted failures without exposing raw private payloads.

**Source:** [lib/services/application_error_reporter.dart](../../lib/services/application_error_reporter.dart).
**Declared types:** `ApplicationErrorReporter`.
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/services/application_error_reporter_test.dart](../../test/services/application_error_reporter_test.dart).

### `lib/services/application_private_directory.dart`

Platform-aware private/support-directory choice; keeps desktop data out of development directories.

**Source:** [lib/services/application_private_directory.dart](../../lib/services/application_private_directory.dart).
**Referenced by:** [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/utils/app_logger.dart](../../lib/utils/app_logger.dart).
**Direct test references:** [test/services/application_private_directory_test.dart](../../test/services/application_private_directory_test.dart).

### `lib/services/backend_self_test.dart`

Backend probe result and execution contract; separates availability from tested backend suitability.

**Source:** [lib/services/backend_self_test.dart](../../lib/services/backend_self_test.dart).
**Declared types:** `BackendSelfTestResult`, `BackendProbe`, `BackendSelfTest`.
**Referenced by:** [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).
**Direct test references:** [test/services/runtime_auto_tuner_test.dart](../../test/services/runtime_auto_tuner_test.dart).

### `lib/services/chat_state_controller.dart`

Generation finite-state machine, progress/safety/watchdog/cancellation orchestration; centralizes runtime state transitions.

**Source:** [lib/services/chat_state_controller.dart](../../lib/services/chat_state_controller.dart).
**Declared types:** `ChatStatus`, `ChatFailureCode`, `ChatStateController`.
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/widgets/chat_input_field.dart](../../lib/widgets/chat_input_field.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart), [test/providers/generation_recovery_test.dart](../../test/providers/generation_recovery_test.dart), [test/services/chat_state_controller_test.dart](../../test/services/chat_state_controller_test.dart); more in the test map.

### `lib/services/context_planner.dart`

Native-tokenizer context selection and output budgeting; retains required input and newest contiguous complete turns.

**Source:** [lib/services/context_planner.dart](../../lib/services/context_planner.dart).
**Declared types:** `ContextPlanningError`, `ContextPlanner`, `ContextTokenCounter`, `LlamaContextTokenCounter`.
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart).
**Direct test references:** [test/services/context_planner_test.dart](../../test/services/context_planner_test.dart), [test_native/unicode_tokenization_test.dart](../../test_native/unicode_tokenization_test.dart).

### `lib/services/device_fit_estimator.dart`

Model/device memory and storage suitability estimates; warnings are estimates, not guarantees of successful allocation.

**Source:** [lib/services/device_fit_estimator.dart](../../lib/services/device_fit_estimator.dart).
**Declared types:** `DeviceFitEstimator`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart).
**Direct test references:** [test/services/device_fit_estimator_test.dart](../../test/services/device_fit_estimator_test.dart).

### `lib/services/hardware_sentinel_service.dart`

App-scoped safety aggregation and heavy-operation admission; cancels/blocks unsafe work using current telemetry.

**Source:** [lib/services/hardware_sentinel_service.dart](../../lib/services/hardware_sentinel_service.dart).
**Declared types:** `HardwareSentinelException`, `LowPowerThrottlingException`, `HardwareSentinelService`.
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/providers/health_provider.dart](../../lib/providers/health_provider.dart), [lib/services/chat_state_controller.dart](../../lib/services/chat_state_controller.dart), [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/model_download_test.dart](../../test/model_download_test.dart), [test/provider_test.dart](../../test/provider_test.dart), [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart); more in the test map.

### `lib/services/hardware_telemetry.dart`

Injectable battery, connectivity and device-snapshot adapters; missing sensors remain nullable rather than fake healthy values.

**Source:** [lib/services/hardware_telemetry.dart](../../lib/services/hardware_telemetry.dart).
**Declared types:** `BatteryTelemetry`, `BatteryPlusTelemetry`, `ConnectivityTelemetry`, `ConnectivityPlusTelemetry`, `DeviceSnapshotTelemetry`, `MethodChannelDeviceSnapshotTelemetry`.
**Referenced by:** [lib/services/hardware_sentinel_service.dart](../../lib/services/hardware_sentinel_service.dart), [lib/services/hardware_sentinel_service.dart](../../lib/services/hardware_sentinel_service.dart).

### `lib/services/legacy_model_preference_migration.dart`

Verified migration of old global model preferences into registry identity; removes legacy keys only after durable checks.

**Source:** [lib/services/legacy_model_preference_migration.dart](../../lib/services/legacy_model_preference_migration.dart).
**Declared types:** `LegacyModelPreferenceManifest`, `LegacyMigrationFailureCode`, `LegacyMigrationFailure`, `LegacyModelPreferenceMigration`.
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/services/legacy_model_preference_migration_test.dart](../../test/services/legacy_model_preference_migration_test.dart).

### `lib/services/lifecycle_manager.dart`

Shared disposable/leak-tracking lifecycle contract; makes resource retirement visible to callers.

**Source:** [lib/services/lifecycle_manager.dart](../../lib/services/lifecycle_manager.dart).
**Declared types:** `LifecycleManager`.
**Referenced by:** [lib/services/chat_state_controller.dart](../../lib/services/chat_state_controller.dart), [lib/services/hardware_sentinel_service.dart](../../lib/services/hardware_sentinel_service.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).

### `lib/services/memory_pressure_service.dart`

Framework/system memory-pressure subscription; supplies safety signals without inducing artificial pressure.

**Source:** [lib/services/memory_pressure_service.dart](../../lib/services/memory_pressure_service.dart).
**Declared types:** `MemoryPressureService`.
**Referenced by:** [lib/services/hardware_sentinel_service.dart](../../lib/services/hardware_sentinel_service.dart).
**Direct test references:** [test/services/hardware_sentinel_service_test.dart](../../test/services/hardware_sentinel_service_test.dart), [test/services/memory_pressure_service_test.dart](../../test/services/memory_pressure_service_test.dart), [test/services/safety_logging_privacy_test.dart](../../test/services/safety_logging_privacy_test.dart).

### `lib/services/model_download_manager.dart`

General Hub job coordination, transfer adapters, persistence, reconciliation and installation admission; not the same as the bundled setup downloader.

**Source:** [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart).
**Declared types:** `ModelFileStore`, `ApplicationModelFileStore`, `PlatformTransferAdapter`, `DurableTransferControl`, `DioTransferAdapter`, `TransferResult`, `TransferReconciliation`, `AndroidDurableTransferAdapter`, `_NativeTransferStopRequested`, `DownloadJobStore`, `DatabaseDownloadJobStore`, `ModelDownloadOperations`, `ModelDownloadManager`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/services/model_update_service.dart](../../lib/services/model_update_service.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart), [test/services/android_durable_transfer_adapter_test.dart](../../test/services/android_durable_transfer_adapter_test.dart), [test/services/model_download_manager_test.dart](../../test/services/model_download_manager_test.dart); more in the test map.

### `lib/services/model_download_service.dart`

Observable bundled-download/reset lifecycle; keeps admitted operations until transport/storage work settles.

**Source:** [lib/services/model_download_service.dart](../../lib/services/model_download_service.dart).
**Declared types:** `DownloadState`, `ModelDownloadService`.
**Referenced by:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/model_download_test.dart](../../test/model_download_test.dart), [test/services/model_download_service_lifecycle_test.dart](../../test/services/model_download_service_lifecycle_test.dart), [test/widgets/settings_recovery_test.dart](../../test/widgets/settings_recovery_test.dart).

### `lib/services/model_download_staging.dart`

Job-and-artifact-specific partial paths; prevents another download/cancel operation owning the same staging file.

**Source:** [lib/services/model_download_staging.dart](../../lib/services/model_download_staging.dart).
**Declared types:** `ModelDownloadStaging`.
**Referenced by:** [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart).
**Direct test references:** [test/services/model_download_manager_test.dart](../../test/services/model_download_manager_test.dart), [test/services/model_download_staging_test.dart](../../test/services/model_download_staging_test.dart).

### `lib/services/model_downloader.dart`

Immutable bundled-model download, hash checking, retry, storage and scoped reset; supports first-run setup without trusting mutable model bytes.

**Source:** [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart).
**Declared types:** `ModelDownloadSpec`, `ModelDownloadEnvironment`, `BundledModelRegistry`, `DatabaseBundledModelRegistry`, `AndroidModelDownloadEnvironment`, `ModelDownloader`, `DownloadResult`.
**Referenced by:** [lib/services/model_download_service.dart](../../lib/services/model_download_service.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [integration_test/helpers.dart](../../integration_test/helpers.dart), [test/model_download_test.dart](../../test/model_download_test.dart), [test/services/bundled_install_adapter_test.dart](../../test/services/bundled_install_adapter_test.dart), [test/services/model_download_service_lifecycle_test.dart](../../test/services/model_download_service_lifecycle_test.dart); more in the test map.

### `lib/services/model_hub_client.dart`

Anonymous official Hub API search/repository/variant resolution and URL validation; never sends conversations for inference.

**Source:** [lib/services/model_hub_client.dart](../../lib/services/model_hub_client.dart).
**Declared types:** `ModelHubClient`, `HuggingFaceModelHubClient`, `ModelHubAccessException`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/services/model_update_service.dart](../../lib/services/model_update_service.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart), [test/services/model_hub_client_test.dart](../../test/services/model_hub_client_test.dart), [test/services/model_update_service_test.dart](../../test/services/model_update_service_test.dart).

### `lib/services/model_installation_promoter.dart`

Validated journal-driven file promotion with leases and interruption recovery; protects existing destinations from overwrite/deletion.

**Source:** [lib/services/model_installation_promoter.dart](../../lib/services/model_installation_promoter.dart).
**Declared types:** `InstallationFileLease`, `InstallationFileMove`, `InstallationFileFailureCode`, `InstallationFileFailure`, `InstallationPromotionInterrupted`, `ModelInstallationPromoter`.
**Referenced by:** [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).
**Direct test references:** [test/services/model_installation_promoter_test.dart](../../test/services/model_installation_promoter_test.dart).

### `lib/services/model_recovery_controller.dart`

Single-flight verification/recovery progress owned by the provider layer; does not silently select, delete or substitute a model.

**Source:** [lib/services/model_recovery_controller.dart](../../lib/services/model_recovery_controller.dart).
**Declared types:** `ModelRecoveryState`, `ModelRecoveryController`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart), [lib/widgets/model_recovery_status_label.dart](../../lib/widgets/model_recovery_status_label.dart).
**Direct test references:** [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/services/model_recovery_controller_test.dart](../../test/services/model_recovery_controller_test.dart), [test/widgets/model_recovery_status_label_test.dart](../../test/widgets/model_recovery_status_label_test.dart).

### `lib/services/model_registry_service.dart`

Registry identity/import/verification/selection/uninstall operations with storage/native ownership; protects existing models and chat assignments.

**Source:** [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart).
**Declared types:** `ModelRootResolver`, `ModelDirectoryResolver`, `GgufMetadataReader`, `CompatibilityProbeFactory`, `ModelRegistryService`, `_DigestSink`.
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart), [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart), [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart); 1 additional references in the inventory.
**Direct test references:** [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart), [test/providers/initial_model_chat_test.dart](../../test/providers/initial_model_chat_test.dart), [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart); more in the test map.

### `lib/services/model_shard_restorer.dart`

Explicit exact-byte single/split model restoration; resumes staged recovery and waits for native probe cleanup.

**Source:** [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).
**Declared types:** `ModelShardRestorer`.
**Referenced by:** [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart).

### `lib/services/model_shard_staging.dart`

Shard-restoration staging part; retains journal-owned candidates on failure and only cleans invocation-owned temporary candidates.

**Source:** [lib/services/model_shard_staging.dart](../../lib/services/model_shard_staging.dart).
**Declared types:** `_ModelShardStaging`.
**Referenced by:** [lib/services/model_shard_restorer.dart](../../lib/services/model_shard_restorer.dart).

### `lib/services/model_startup_inspector.dart`

Read-only selected-model file/validation assessment; never runs hidden bootstrap inference or substitutes another model.

**Source:** [lib/services/model_startup_inspector.dart](../../lib/services/model_startup_inspector.dart).
**Declared types:** `StartupModelFiles`, `LocalStartupModelFiles`, `ModelStartupInspector`.
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/services/model_startup_inspector_test.dart](../../test/services/model_startup_inspector_test.dart), [test_native/split_model_restoration_test.dart](../../test_native/split_model_restoration_test.dart).

### `lib/services/model_storage_preflight.dart`

On-demand allocatable-storage query; separates large-download preflight from frequent telemetry polling.

**Source:** [lib/services/model_storage_preflight.dart](../../lib/services/model_storage_preflight.dart).
**Referenced by:** [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart), [lib/services/model_downloader.dart](../../lib/services/model_downloader.dart).

### `lib/services/model_update_service.dart`

Explicit immutable-revision update checks and persisted availability; installed bytes do not silently mutate.

**Source:** [lib/services/model_update_service.dart](../../lib/services/model_update_service.dart).
**Declared types:** `ModelUpdateAvailability`, `ModelUpdateService`, `ModelUpdateRecordStore`, `DatabaseModelUpdateRecordStore`, `HubModelUpdateService`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart).
**Direct test references:** [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/services/model_update_service_test.dart](../../test/services/model_update_service_test.dart).

### `lib/services/model_verification_runtime.dart`

Owner-scoped native compatibility-probe lifecycle and recovery; busy/cleanup failure does not automatically mean invalid bytes.

**Source:** [lib/services/model_verification_runtime.dart](../../lib/services/model_verification_runtime.dart).
**Declared types:** `ModelVerificationRuntime`.
**Referenced by:** [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart).
**Direct test references:** [test/services/model_verification_runtime_test.dart](../../test/services/model_verification_runtime_test.dart), [test_native/registry_probe_cleanup_test.dart](../../test_native/registry_probe_cleanup_test.dart).

### `lib/services/model_warmup_recovery.dart`

Warmup lifecycle/recovery part; drains retained actors without self-deadlocking or treating an expired waiter as termination.

**Source:** [lib/services/model_warmup_recovery.dart](../../lib/services/model_warmup_recovery.dart).
**Referenced by:** [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).

### `lib/services/model_warmup_service.dart`

Persistent selected-model/context preparation, tuning and handoff for interactive use; initialization is distinct from hidden token generation.

**Source:** [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).
**Declared types:** `RuntimeTuningStatus`, `ModelWarmupOutcome`, `LlamaRepositoryFactory`, `AppVersionResolver`, `ModelWarmupService`.
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [test/provider_test.dart](../../test/provider_test.dart), [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart), [test/providers/generation_recovery_test.dart](../../test/providers/generation_recovery_test.dart), [test/services/model_warmup_service_test.dart](../../test/services/model_warmup_service_test.dart), [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart); more in the test map.

### `lib/services/native_transfer_stop.dart`

Durable writer stop/pause acknowledgement and deadlines; timeout never authorizes partial deletion by itself.

**Source:** [lib/services/native_transfer_stop.dart](../../lib/services/native_transfer_stop.dart).
**Declared types:** `NativeStopTimerFactory`, `NativeTransferStopPolicy`, `NativeStopFailure`, `NativeTransferStopUnconfirmed`, `NativeTransferStopController`, `_StopDeadline`.
**Referenced by:** [lib/services/model_download_manager.dart](../../lib/services/model_download_manager.dart).
**Direct test references:** [test/services/android_durable_transfer_adapter_test.dart](../../test/services/android_durable_transfer_adapter_test.dart), [test/services/model_download_manager_test.dart](../../test/services/model_download_manager_test.dart), [test/services/native_transfer_stop_test.dart](../../test/services/native_transfer_stop_test.dart).

### `lib/services/notification_permission_service.dart`

User-initiated Android notification-permission boundary; distinguishes granted, denied, unavailable and in-progress states.

**Source:** [lib/services/notification_permission_service.dart](../../lib/services/notification_permission_service.dart).
**Declared types:** `NotificationPermissionStatus`, `NotificationPermissionService`.
**Referenced by:** [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart).
**Direct test references:** [test/services/notification_permission_service_test.dart](../../test/services/notification_permission_service_test.dart).

### `lib/services/persistent_hub_search_cache.dart`

Database-backed freshness, stale-offline retention and LRU pruning; browsing can reuse bounded stored results.

**Source:** [lib/services/persistent_hub_search_cache.dart](../../lib/services/persistent_hub_search_cache.dart).
**Declared types:** `HubSearchCacheClock`, `HubSearchCachePolicy`, `HubSearchCacheEntry`, `PersistentHubSearchCache`, `DatabaseHubSearchCache`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart).
**Direct test references:** [test/database_test.dart](../../test/database_test.dart), [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart).

### `lib/services/platform_model_folder_opener.dart`

Platform-appropriate model-folder opening; desktop support does not imply Android filesystem browsing.

**Source:** [lib/services/platform_model_folder_opener.dart](../../lib/services/platform_model_folder_opener.dart).
**Declared types:** `PlatformModelFolderOpener`, `ApplicationModelFolderOpener`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart).

### `lib/services/remote_gguf_inspector.dart`

Bounded streaming range fetch and metadata parser; rejects excessive/malformed metadata rather than buffering an unlimited model body.

**Source:** [lib/services/remote_gguf_inspector.dart](../../lib/services/remote_gguf_inspector.dart).
**Declared types:** `RemoteGgufInspectionPolicy`, `RemoteGgufMetadata`, `RemoteRangeResult`, `RemoteRangeReader`, `DioRemoteRangeReader`, `RemoteGgufInspector`, `BoundedRemoteGgufInspector`, `GgufRangeIncomplete`, `GgufHeaderParser`, `_GgufReader`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart).
**Direct test references:** [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart), [test/services/remote_gguf_inspector_test.dart](../../test/services/remote_gguf_inspector_test.dart), [test/widgets/model_library_screen_states_test.dart](../../test/widgets/model_library_screen_states_test.dart).

### `lib/services/response_frame_timing.dart`

Request-scoped provider receipt/frame offsets; labels the UI measurement boundary separately from native token sampling.

**Source:** [lib/services/response_frame_timing.dart](../../lib/services/response_frame_timing.dart).
**Declared types:** `ResponseFrameTiming`, `ResponseFrameTimingTracker`.
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart).
**Direct test references:** [test/services/response_frame_timing_test.dart](../../test/services/response_frame_timing_test.dart), [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart).

### `lib/services/runtime_auto_tuner.dart`

Bounded CPU candidate benchmarking, conservative baseline validation and cancellation; rejects unsafe, stale and non-finite results.

**Source:** [lib/services/runtime_auto_tuner.dart](../../lib/services/runtime_auto_tuner.dart).
**Declared types:** `TuningCancellationToken`, `TuningCancelled`, `RuntimeTuningBaselineUnavailable`, `RuntimeBenchmarkConfigurationUnavailable`, `RuntimeBenchmarkResult`, `RuntimeBenchmarkRunner`, `RuntimeAutoTuner`.
**Referenced by:** [lib/services/backend_self_test.dart](../../lib/services/backend_self_test.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).
**Direct test references:** [test/services/runtime_auto_tuner_test.dart](../../test/services/runtime_auto_tuner_test.dart), [test/services/runtime_benchmark_workload_test.dart](../../test/services/runtime_benchmark_workload_test.dart).

### `lib/services/runtime_benchmark_workload.dart`

Exact-token rendered benchmark prompt/output workload; enables meaningful configuration comparisons.

**Source:** [lib/services/runtime_benchmark_workload.dart](../../lib/services/runtime_benchmark_workload.dart).
**Declared types:** `RuntimeBenchmarkPolicy`, `RuntimeBenchmarkWorkloadUnavailable`, `RuntimeBenchmarkWorkload`.
**Referenced by:** [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart), [lib/services/runtime_auto_tuner.dart](../../lib/services/runtime_auto_tuner.dart).
**Direct test references:** [test/services/model_warmup_service_test.dart](../../test/services/model_warmup_service_test.dart), [test/services/runtime_benchmark_workload_test.dart](../../test/services/runtime_benchmark_workload_test.dart), [test_native/benchmark_workload_test.dart](../../test_native/benchmark_workload_test.dart).

### `lib/services/runtime_capabilities_provider.dart`

Capability collection behind a platform-neutral snapshot interface; supplies topology/memory/thermal/backend inputs for profiles.

**Source:** [lib/services/runtime_capabilities_provider.dart](../../lib/services/runtime_capabilities_provider.dart).
**Declared types:** `RuntimeCapabilitiesProvider`, `AndroidRuntimeCapabilitiesProvider`.
**Referenced by:** [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).
**Direct test references:** [test/services/model_registry_service_test.dart](../../test/services/model_registry_service_test.dart), [test/services/model_warmup_service_test.dart](../../test/services/model_warmup_service_test.dart), [test/services/runtime_capabilities_provider_test.dart](../../test/services/runtime_capabilities_provider_test.dart), [test/support/shard_restore_fixture.dart](../../test/support/shard_restore_fixture.dart), [test_native/bundled_install_projection_test.dart](../../test_native/bundled_install_projection_test.dart); more in the test map.

### `lib/services/runtime_profile_store.dart`

Versioned per-device/model/backend profile cache and current-owner commit checks; interrupted tuning cannot publish successful profiles.

**Source:** [lib/services/runtime_profile_store.dart](../../lib/services/runtime_profile_store.dart).
**Declared types:** `StoredRuntimeProfile`, `RuntimeProfileStore`, `RuntimeProfileStoreManifest`, `SharedPreferencesRuntimeProfileStore`, `RuntimeProfilePersistenceFailure`.
**Referenced by:** [lib/services/model_registry_service.dart](../../lib/services/model_registry_service.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart).
**Direct test references:** [test/services/model_registry_service_test.dart](../../test/services/model_registry_service_test.dart), [test/services/model_registry_uninstall_test.dart](../../test/services/model_registry_uninstall_test.dart), [test/services/model_warmup_service_test.dart](../../test/services/model_warmup_service_test.dart), [test/services/runtime_profile_store_test.dart](../../test/services/runtime_profile_store_test.dart), [test_native/tuning_preemption_test.dart](../../test_native/tuning_preemption_test.dart).

### `lib/services/selected_model_readiness.dart`

Serialized selected-model availability checks and stale-completion rejection; changing chats cannot inherit another model's readiness.

**Source:** [lib/services/selected_model_readiness.dart](../../lib/services/selected_model_readiness.dart).
**Declared types:** `SelectedModelReadiness`.
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart), [lib/services/startup_capability_source.dart](../../lib/services/startup_capability_source.dart), [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Direct test references:** [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart), [test/providers/initial_model_chat_test.dart](../../test/providers/initial_model_chat_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/services/selected_model_readiness_test.dart](../../test/services/selected_model_readiness_test.dart), [test/services/startup_capability_source_test.dart](../../test/services/startup_capability_source_test.dart); more in the test map.

### `lib/services/startup_access_guard.dart`

Current capability admission for browsing/mutation/inference; guards service actions as well as disabled widgets.

**Source:** [lib/services/startup_access_guard.dart](../../lib/services/startup_access_guard.dart).
**Declared types:** `StartupAccessOperation`, `StartupAccessDenied`, `StartupAccessGuard`.
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart), [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart), [lib/screens/modals/note_edit_modal.dart](../../lib/screens/modals/note_edit_modal.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart); 4 additional references in the inventory.
**Direct test references:** [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart), [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart), [test/providers/initial_model_chat_test.dart](../../test/providers/initial_model_chat_test.dart), [test/providers/startup_access_guard_test.dart](../../test/providers/startup_access_guard_test.dart), [test/widgets/chat_history_read_only_test.dart](../../test/widgets/chat_history_read_only_test.dart); more in the test map.

### `lib/services/startup_capability_source.dart`

Combines bootstrap prerequisites with current model readiness; keeps different readiness dimensions explicit.

**Source:** [lib/services/startup_capability_source.dart](../../lib/services/startup_capability_source.dart).
**Declared types:** `StartupCapabilitySource`.
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/services/startup_capability_source_test.dart](../../test/services/startup_capability_source_test.dart).

### `lib/services/startup_coordinator.dart`

Ordered, timed, single-flight observable initialization; retains timed-out underlying work and rejects overlapping retries.

**Source:** [lib/services/startup_coordinator.dart](../../lib/services/startup_coordinator.dart).
**Declared types:** `StartupState`, `StartupTask`, `StartupClock`, `StartupTraceSink`, `StartupModelAssessment`, `StartupCoordinator`.
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/services/startup_capability_source.dart](../../lib/services/startup_capability_source.dart), [lib/widgets/startup_shell.dart](../../lib/widgets/startup_shell.dart).
**Direct test references:** [test/services/legacy_model_preference_migration_test.dart](../../test/services/legacy_model_preference_migration_test.dart), [test/services/startup_capabilities_test.dart](../../test/services/startup_capabilities_test.dart), [test/services/startup_capability_source_test.dart](../../test/services/startup_capability_source_test.dart), [test/services/startup_coordinator_test.dart](../../test/services/startup_coordinator_test.dart), [test/widgets/startup_shell_test.dart](../../test/widgets/startup_shell_test.dart).

## lib/theme

### `lib/theme/app_theme.dart`

Light/dark Material theme assembly; consumes shared visual tokens.

**Source:** [lib/theme/app_theme.dart](../../lib/theme/app_theme.dart).
**Declared types:** `AppTheme`.
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart), [test/widgets/conversation_design_test.dart](../../test/widgets/conversation_design_test.dart).

## lib/ui

### `lib/ui/debug_settings_screen.dart`

Developer diagnostics, settings and diagnostic sharing; private logs require review before export.

**Source:** [lib/ui/debug_settings_screen.dart](../../lib/ui/debug_settings_screen.dart).
**Declared types:** `DebugSettingsScreen`, `_DebugSettingsScreenState`.
**Referenced by:** [lib/app_router.dart](../../lib/app_router.dart).

## lib/utils

### `lib/utils/app_logger.dart`

Local structured/persisted logging and diagnostics limits; source-side privacy and sink failures must remain explicit.

**Source:** [lib/utils/app_logger.dart](../../lib/utils/app_logger.dart).
**Declared types:** `LogCleanupResult`, `AppLogger`.
**Referenced by:** [lib/database/database_helper.dart](../../lib/database/database_helper.dart), [lib/main.dart](../../lib/main.dart), [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart), [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart), [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart); 13 additional references in the inventory.
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart), [test/providers/chat_logging_privacy_test.dart](../../test/providers/chat_logging_privacy_test.dart), [test/providers/saved_content_logging_privacy_test.dart](../../test/providers/saved_content_logging_privacy_test.dart), [test/services/application_error_reporter_test.dart](../../test/services/application_error_reporter_test.dart), [test/services/bundled_install_adapter_test.dart](../../test/services/bundled_install_adapter_test.dart); more in the test map.

### `lib/utils/async_mutex.dart`

Asynchronous critical-section serialization; protects shared Dart-side operations without pretending to stop native work.

**Source:** [lib/utils/async_mutex.dart](../../lib/utils/async_mutex.dart).
**Declared types:** `AsyncMutex`.
**Referenced by:** [lib/utils/app_logger.dart](../../lib/utils/app_logger.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart).

### `lib/utils/date_formatter.dart`

Shared date presentation; keeps stored timestamps separate from display wording.

**Source:** [lib/utils/date_formatter.dart](../../lib/utils/date_formatter.dart).
**Declared types:** `DateFormatter`.
**Referenced by:** [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart), [lib/screens/modals/chat_history_modal.dart](../../lib/screens/modals/chat_history_modal.dart), [lib/widgets/message_bubble.dart](../../lib/widgets/message_bubble.dart).
**Direct test references:** [test/utils/date_formatter_test.dart](../../test/utils/date_formatter_test.dart).

### `lib/utils/debug_state.dart`

Persisted developer-mode state; controls entry to diagnostic interfaces.

**Source:** [lib/utils/debug_state.dart](../../lib/utils/debug_state.dart).
**Declared types:** `DebugState`.
**Referenced by:** [lib/app_router.dart](../../lib/app_router.dart), [lib/screens/modals/hamburger_menu.dart](../../lib/screens/modals/hamburger_menu.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/ui/debug_settings_screen.dart](../../lib/ui/debug_settings_screen.dart).

### `lib/utils/log_sanitizer.dart`

Redaction helpers for sensitive diagnostic content; secondary protection after avoiding private logging at source.

**Source:** [lib/utils/log_sanitizer.dart](../../lib/utils/log_sanitizer.dart).
**Declared types:** `LogSanitizer`.
**Referenced by:** [lib/utils/app_logger.dart](../../lib/utils/app_logger.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart).

### `lib/utils/memory_monitor.dart`

Memory-monitoring helper; measurements must retain their platform-specific semantics.

**Source:** [lib/utils/memory_monitor.dart](../../lib/utils/memory_monitor.dart).
**Declared types:** `MemoryMonitor`.
**Referenced by:** [lib/providers/health_provider.dart](../../lib/providers/health_provider.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart).

### `lib/utils/stream_transformers.dart`

Stream-processing utilities; shared stream behaviour should preserve cancellation/error propagation.

**Source:** [lib/utils/stream_transformers.dart](../../lib/utils/stream_transformers.dart).
**Declared types:** `BufferedStreamTransformer`.
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart).

### `lib/utils/text_limits.dart`

Unicode-scalar and UTF-8 storage validation; avoids character-count/token-count confusion.

**Source:** [lib/utils/text_limits.dart](../../lib/utils/text_limits.dart).
**Referenced by:** [lib/providers/chat_provider.dart](../../lib/providers/chat_provider.dart), [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart), [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart).

### `lib/utils/validation_exception.dart`

Typed user-input validation failures; separates content-free messages from internal runtime exceptions.

**Source:** [lib/utils/validation_exception.dart](../../lib/utils/validation_exception.dart).
**Declared types:** `ValidationException`.
**Referenced by:** [lib/providers/note_provider.dart](../../lib/providers/note_provider.dart), [lib/providers/persona_provider.dart](../../lib/providers/persona_provider.dart).
**Direct test references:** [integration_test/app_test.dart](../../integration_test/app_test.dart).

## lib/widgets

### `lib/widgets/animated_dots.dart`

Small generation/loading animation; presentation only, not evidence that native work is progressing.

**Source:** [lib/widgets/animated_dots.dart](../../lib/widgets/animated_dots.dart).
**Declared types:** `AnimatedDots`, `_AnimatedDotsState`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).

### `lib/widgets/attached_notes_bar.dart`

Visible attached-note controls; reflects persistent ordered context selection.

**Source:** [lib/widgets/attached_notes_bar.dart](../../lib/widgets/attached_notes_bar.dart).
**Declared types:** `AttachedNotesBar`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).

### `lib/widgets/chat_input_field.dart`

Composer text/send/stop interaction and semantics; delegates generation ownership to state/services.

**Source:** [lib/widgets/chat_input_field.dart](../../lib/widgets/chat_input_field.dart).
**Declared types:** `ChatInputField`, `_ChatInputFieldState`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).
**Direct test references:** [test/widgets/conversation_design_test.dart](../../test/widgets/conversation_design_test.dart).

### `lib/widgets/confirm_dialog.dart`

Reusable explicit confirmation surface; destructive model/content actions stay distinguishable.

**Source:** [lib/widgets/confirm_dialog.dart](../../lib/widgets/confirm_dialog.dart).
**Declared types:** `ConfirmDialog`.
**Referenced by:** [lib/screens/modals/chat_history_modal.dart](../../lib/screens/modals/chat_history_modal.dart), [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart), [lib/screens/modals/persona_selection_modal.dart](../../lib/screens/modals/persona_selection_modal.dart).
**Direct test references:** [test/widget_test.dart](../../test/widget_test.dart).

### `lib/widgets/conversation_status_bar.dart`

Compact conversation/runtime/context status; communicates execution state without owning inference.

**Source:** [lib/widgets/conversation_status_bar.dart](../../lib/widgets/conversation_status_bar.dart).
**Declared types:** `ConversationStatusBar`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).
**Direct test references:** [test/widgets/conversation_design_test.dart](../../test/widgets/conversation_design_test.dart).

### `lib/widgets/message_bubble.dart`

Role-aware Markdown response rendering and accessibility; avoids duplicate visible/semantic assistant responses.

**Source:** [lib/widgets/message_bubble.dart](../../lib/widgets/message_bubble.dart).
**Declared types:** `MessageBubble`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).
**Direct test references:** [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart), [test/widgets/conversation_design_test.dart](../../test/widgets/conversation_design_test.dart), [test/widgets/message_bubble_test.dart](../../test/widgets/message_bubble_test.dart), [test_native/native_response_frame_test.dart](../../test_native/native_response_frame_test.dart).

### `lib/widgets/model_recovery_status_label.dart`

Pure recovery-state wording; presents real operation states rather than empty placeholders.

**Source:** [lib/widgets/model_recovery_status_label.dart](../../lib/widgets/model_recovery_status_label.dart).
**Declared types:** `ModelRecoveryStatusLabel`.
**Referenced by:** [lib/screens/model_library_screen.dart](../../lib/screens/model_library_screen.dart).
**Direct test references:** [test/widgets/model_recovery_status_label_test.dart](../../test/widgets/model_recovery_status_label_test.dart).

### `lib/widgets/progress_bar.dart`

Progress presentation; does not independently control transfers or inference.

**Source:** [lib/widgets/progress_bar.dart](../../lib/widgets/progress_bar.dart).
**Declared types:** `ProgressBar`.
**Referenced by:** [lib/screens/setup_screen.dart](../../lib/screens/setup_screen.dart).
**Direct test references:** [test/widget_test.dart](../../test/widget_test.dart).

### `lib/widgets/response_frame_observer.dart`

Paint-frame observation for a specific response identity; records a frame proxy, not display-panel latency.

**Source:** [lib/widgets/response_frame_observer.dart](../../lib/widgets/response_frame_observer.dart).
**Declared types:** `ResponseFrameObserver`, `_ResponseFrameRenderObject`.
**Referenced by:** [lib/screens/chat_screen.dart](../../lib/screens/chat_screen.dart).
**Direct test references:** [test/widgets/response_frame_observer_test.dart](../../test/widgets/response_frame_observer_test.dart), [test_native/native_response_frame_test.dart](../../test_native/native_response_frame_test.dart).

### `lib/widgets/saved_text_preview.dart`

Presentation-only preview of stored text; never truncates the underlying record.

**Source:** [lib/widgets/saved_text_preview.dart](../../lib/widgets/saved_text_preview.dart).
**Referenced by:** [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart), [lib/screens/modals/persona_selection_modal.dart](../../lib/screens/modals/persona_selection_modal.dart).

### `lib/widgets/startup_mutation_access.dart`

Readiness-aware control wrapping; UI permission follows the same guard used by persistence.

**Source:** [lib/widgets/startup_mutation_access.dart](../../lib/widgets/startup_mutation_access.dart).
**Declared types:** `StartupMutationAccess`.
**Referenced by:** [lib/screens/chats_overview_screen.dart](../../lib/screens/chats_overview_screen.dart), [lib/screens/modals/chat_history_modal.dart](../../lib/screens/modals/chat_history_modal.dart), [lib/screens/modals/hamburger_menu.dart](../../lib/screens/modals/hamburger_menu.dart), [lib/screens/modals/note_edit_modal.dart](../../lib/screens/modals/note_edit_modal.dart), [lib/screens/modals/notes_list_selection_modal.dart](../../lib/screens/modals/notes_list_selection_modal.dart), [lib/screens/modals/persona_selection_modal.dart](../../lib/screens/modals/persona_selection_modal.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/widgets/validated_setting_editor_dialog.dart](../../lib/widgets/validated_setting_editor_dialog.dart).
**Direct test references:** [test/widgets/saved_content_read_only_test.dart](../../test/widgets/saved_content_read_only_test.dart).

### `lib/widgets/startup_shell.dart`

First-frame boot/error/degraded/ready shell; initialization cannot hide Flutter behind an indefinite Android splash.

**Source:** [lib/widgets/startup_shell.dart](../../lib/widgets/startup_shell.dart).
**Declared types:** `StartupShell`, `_StartupShellState`.
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/widgets/startup_shell_test.dart](../../test/widgets/startup_shell_test.dart).

### `lib/widgets/system_prompt_editor_dialog.dart`

Explicit system-instruction editor; distinguishes persisted instruction text from rendered prompt tokens.

**Source:** [lib/widgets/system_prompt_editor_dialog.dart](../../lib/widgets/system_prompt_editor_dialog.dart).
**Declared types:** `SystemPromptEditorDialog`.
**Referenced by:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart).

### `lib/widgets/validated_setting_editor_dialog.dart`

Bounded numeric setting editor with validation; rejects invalid values before settings persistence.

**Source:** [lib/widgets/validated_setting_editor_dialog.dart](../../lib/widgets/validated_setting_editor_dialog.dart).
**Declared types:** `ValidatedSettingEditorDialog`, `_ValidatedSettingEditorDialogState`.
**Referenced by:** [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/widgets/system_prompt_editor_dialog.dart](../../lib/widgets/system_prompt_editor_dialog.dart).

### `lib/widgets/vitalis_dependencies.dart`

Provider composition graph and test factories; owns application dependency wiring separately from routes.

**Source:** [lib/widgets/vitalis_dependencies.dart](../../lib/widgets/vitalis_dependencies.dart).
**Declared types:** `WarmupServiceFactory`, `ChatControllerFactory`, `VitalisDependencies`.
**Referenced by:** [lib/main.dart](../../lib/main.dart).
**Direct test references:** [test/widgets/vitalis_dependencies_test.dart](../../test/widgets/vitalis_dependencies_test.dart).

## Native runtime / analysis_options.yaml

### `third_party/llm_llamacpp/analysis_options.yaml`

Vendored analysis/lint scope; distinct from root application analysis.

**Source:** [third_party/llm_llamacpp/analysis_options.yaml](../../third_party/llm_llamacpp/analysis_options.yaml).

## Native runtime / example

### `third_party/llm_llamacpp/example/cli_example.dart`

Generic package CLI demonstration; not a qualified VITALIS entry point or authority for model defaults.

**Source:** [third_party/llm_llamacpp/example/cli_example.dart](../../third_party/llm_llamacpp/example/cli_example.dart).

## Native runtime / example_app

### `third_party/llm_llamacpp/example_app/analysis_options.yaml`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/analysis_options.yaml](../../third_party/llm_llamacpp/example_app/analysis_options.yaml).

### `third_party/llm_llamacpp/example_app/android/app/build.gradle.kts`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/android/app/build.gradle.kts](../../third_party/llm_llamacpp/example_app/android/app/build.gradle.kts).

### `third_party/llm_llamacpp/example_app/android/build.gradle.kts`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/android/build.gradle.kts](../../third_party/llm_llamacpp/example_app/android/build.gradle.kts).

### `third_party/llm_llamacpp/example_app/android/gradle.properties`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/android/gradle.properties](../../third_party/llm_llamacpp/example_app/android/gradle.properties).

### `third_party/llm_llamacpp/example_app/android/gradle/wrapper/gradle-wrapper.properties`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/android/gradle/wrapper/gradle-wrapper.properties](../../third_party/llm_llamacpp/example_app/android/gradle/wrapper/gradle-wrapper.properties).

### `third_party/llm_llamacpp/example_app/android/settings.gradle.kts`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/android/settings.gradle.kts](../../third_party/llm_llamacpp/example_app/android/settings.gradle.kts).

### `third_party/llm_llamacpp/example_app/ios/Flutter/flutter_export_environment.sh`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/ios/Flutter/flutter_export_environment.sh](../../third_party/llm_llamacpp/example_app/ios/Flutter/flutter_export_environment.sh).

### `third_party/llm_llamacpp/example_app/ios/Runner/GeneratedPluginRegistrant.h`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/ios/Runner/GeneratedPluginRegistrant.h](../../third_party/llm_llamacpp/example_app/ios/Runner/GeneratedPluginRegistrant.h).

### `third_party/llm_llamacpp/example_app/lib/main.dart`

Retained package demonstration composition; separate from the VITALIS shipping app.

**Source:** [third_party/llm_llamacpp/example_app/lib/main.dart](../../third_party/llm_llamacpp/example_app/lib/main.dart).
**Declared types:** `LlamaCppTestApp`.

### `third_party/llm_llamacpp/example_app/lib/screens/chat_screen.dart`

Demonstration conversation screen; not VITALIS's app conversation screen or acceptance target.

**Source:** [third_party/llm_llamacpp/example_app/lib/screens/chat_screen.dart](../../third_party/llm_llamacpp/example_app/lib/screens/chat_screen.dart).
**Declared types:** `ChatScreen`, `_ChatScreenState`, `_MessageRole`, `_ChatMessage`, `_MessageBubble`.
**Referenced by:** [third_party/llm_llamacpp/example_app/lib/screens/home_screen.dart](../../third_party/llm_llamacpp/example_app/lib/screens/home_screen.dart).

### `third_party/llm_llamacpp/example_app/lib/screens/home_screen.dart`

Demonstration home/navigation screen; retained package illustration only.

**Source:** [third_party/llm_llamacpp/example_app/lib/screens/home_screen.dart](../../third_party/llm_llamacpp/example_app/lib/screens/home_screen.dart).
**Declared types:** `HomeScreen`, `_HomeScreenState`.
**Referenced by:** [third_party/llm_llamacpp/example_app/lib/main.dart](../../third_party/llm_llamacpp/example_app/lib/main.dart).

### `third_party/llm_llamacpp/example_app/lib/tools/calculator_tool.dart`

Example calculator tool; does not enable external tools in VITALIS.

**Source:** [third_party/llm_llamacpp/example_app/lib/tools/calculator_tool.dart](../../third_party/llm_llamacpp/example_app/lib/tools/calculator_tool.dart).
**Declared types:** `CalculatorTool`.
**Referenced by:** [third_party/llm_llamacpp/example_app/lib/screens/chat_screen.dart](../../third_party/llm_llamacpp/example_app/lib/screens/chat_screen.dart).

### `third_party/llm_llamacpp/example_app/linux/CMakeLists.txt`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/linux/CMakeLists.txt](../../third_party/llm_llamacpp/example_app/linux/CMakeLists.txt).

### `third_party/llm_llamacpp/example_app/linux/flutter/generated_plugin_registrant.cc`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/linux/flutter/generated_plugin_registrant.cc](../../third_party/llm_llamacpp/example_app/linux/flutter/generated_plugin_registrant.cc).

### `third_party/llm_llamacpp/example_app/linux/flutter/generated_plugin_registrant.h`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/linux/flutter/generated_plugin_registrant.h](../../third_party/llm_llamacpp/example_app/linux/flutter/generated_plugin_registrant.h).

### `third_party/llm_llamacpp/example_app/linux/flutter/generated_plugins.cmake`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/linux/flutter/generated_plugins.cmake](../../third_party/llm_llamacpp/example_app/linux/flutter/generated_plugins.cmake).

### `third_party/llm_llamacpp/example_app/linux/llm_llamacpp_plugin.cc`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/linux/llm_llamacpp_plugin.cc](../../third_party/llm_llamacpp/example_app/linux/llm_llamacpp_plugin.cc).

### `third_party/llm_llamacpp/example_app/macos/Flutter/ephemeral/flutter_export_environment.sh`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/macos/Flutter/ephemeral/flutter_export_environment.sh](../../third_party/llm_llamacpp/example_app/macos/Flutter/ephemeral/flutter_export_environment.sh).

### `third_party/llm_llamacpp/example_app/pubspec.yaml`

Retained demonstration-app platform/build configuration. Not VITALIS release or support evidence; generated example machine settings are not portable build authority.

**Source:** [third_party/llm_llamacpp/example_app/pubspec.yaml](../../third_party/llm_llamacpp/example_app/pubspec.yaml).

## Native runtime / ffigen.yaml

### `third_party/llm_llamacpp/ffigen.yaml`

Retained generic llama-header binding generation configuration; verify header identity against the locked native archive before regenerating.

**Source:** [third_party/llm_llamacpp/ffigen.yaml](../../third_party/llm_llamacpp/ffigen.yaml).

## Native runtime / hook

### `third_party/llm_llamacpp/hook/build.dart`

Hash-locked cross-target CMake Native Assets build and code-asset registration; no arbitrary prebuilt runtime download.

**Source:** [third_party/llm_llamacpp/hook/build.dart](../../third_party/llm_llamacpp/hook/build.dart).
**Declared types:** `on`.
**Direct test references:** [test/native_asset_registration_test.dart](../../test/native_asset_registration_test.dart).

### `third_party/llm_llamacpp/hook/native_provenance.dart`

Build provenance/ABI arguments and validation support; keeps locked source identity visible to native checks.

**Source:** [third_party/llm_llamacpp/hook/native_provenance.dart](../../third_party/llm_llamacpp/hook/native_provenance.dart).
**Referenced by:** [third_party/llm_llamacpp/hook/build.dart](../../third_party/llm_llamacpp/hook/build.dart).
**Direct test references:** [test/tool/native_provenance_test.dart](../../test/tool/native_provenance_test.dart).

## Native runtime / lib

### `third_party/llm_llamacpp/lib/llm_llamacpp.dart`

Vendored package public exports; application imports this boundary for repository/model/runtime types.

**Source:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart).
**Referenced by:** [lib/main.dart](../../lib/main.dart), [lib/models/generation_setting.dart](../../lib/models/generation_setting.dart), [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/providers/model_library_provider.dart](../../lib/providers/model_library_provider.dart), [lib/screens/settings_screen.dart](../../lib/screens/settings_screen.dart), [lib/services/chat_state_controller.dart](../../lib/services/chat_state_controller.dart), [lib/services/context_planner.dart](../../lib/services/context_planner.dart), [lib/services/legacy_model_preference_migration.dart](../../lib/services/legacy_model_preference_migration.dart); 11 additional references in the inventory.
**Direct test references:** [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart), [test/providers/generation_recovery_test.dart](../../test/providers/generation_recovery_test.dart), [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart), [test/services/chat_logging_privacy_test.dart](../../test/services/chat_logging_privacy_test.dart), [test/services/chat_state_controller_test.dart](../../test/services/chat_state_controller_test.dart); more in the test map.

### `third_party/llm_llamacpp/lib/src/backend_info.dart`

Native backend information/detection helpers; generic backend names are not proof that the app ships those backends.

**Source:** [third_party/llm_llamacpp/lib/src/backend_info.dart](../../third_party/llm_llamacpp/lib/src/backend_info.dart).
**Declared types:** `BackendInfo`, `BackendDetector`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart).

### `third_party/llm_llamacpp/lib/src/backend_initializer.dart`

Process-aware backend initialization and CPU backend loading; avoids unsafe Dart callbacks on native worker threads.

**Source:** [third_party/llm_llamacpp/lib/src/backend_initializer.dart](../../third_party/llm_llamacpp/lib/src/backend_initializer.dart).
**Declared types:** `BackendInitializationPhase`, `BackendInitializer`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/model_loader.dart](../../third_party/llm_llamacpp/lib/src/model_loader.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).

### `third_party/llm_llamacpp/lib/src/bindings/llama_bindings.dart`

Generated-style low-level llama.cpp FFI declarations; must match the locked native ABI, not be edited casually.

**Source:** [third_party/llm_llamacpp/lib/src/bindings/llama_bindings.dart](../../third_party/llm_llamacpp/lib/src/bindings/llama_bindings.dart).
**Declared types:** `LlamaBindings`, `UnnamedStruct`, `UnnamedUnion`, `_iobuf`, `ggml_backend_buffer`, `ggml_backend_buffer_type`, `ggml_backend_device`, `ggml_cgraph`, `ggml_context`, `ggml_log_level`, `ggml_numa_strategy`, `ggml_op`, `ggml_opt_context`, `ggml_opt_dataset`, `ggml_opt_optimizer_params`, `ggml_opt_optimizer_type`, `ggml_opt_result`, `ggml_tensor`, `ggml_threadpool`, `ggml_type`, `gguf_context`, `llama_adapter_lora`, `llama_attention_type`, `llama_batch`, `llama_chat_message`, `llama_context`, `llama_context_params`, `llama_context_type`, `llama_flash_attn_type`, `llama_ftype`, `llama_lazy_mode`, `llama_load_mode`, `llama_logit_bias`, `llama_memory_i`, `llama_memory_t`, `llama_model`, `llama_model_imatrix_data`, `llama_model_kv_override`, `llama_model_kv_override_type`, `llama_model_meta_key`, `llama_model_params`, `llama_model_quantize_params`, `llama_model_set_tensor_data_t`, `llama_model_set_tensor_data_tFunction`, `Dartllama_model_set_tensor_data_tFunction`, `llama_model_tensor_buft_override`, `llama_model_tensor_override`, `llama_opt_param_filter`, `llama_opt_param_filterFunction`, `Dartllama_opt_param_filterFunction`, `llama_opt_params`, `llama_perf_context_data`, `llama_perf_sampler_data`, `llama_pooling_type`, `llama_pos`, `Dartllama_pos`, `llama_progress_callback`, `llama_progress_callbackFunction`, `Dartllama_progress_callbackFunction`, `llama_rope_scaling_type`, `llama_rope_type`, `llama_sampler`, `llama_sampler_chain_params`, `llama_sampler_context_t`, `llama_sampler_data`, `llama_sampler_i`, `llama_sampler_seq_config`, `llama_seq_id`, `Dartllama_seq_id`, `llama_split_mode`, `llama_state_seq_flags`, `Dartllama_state_seq_flags`, `llama_token`, `Dartllama_token`, `llama_token_attr`, `llama_token_data`, `llama_token_data_array`, `llama_token_type`, `llama_vocab`, `llama_vocab_type`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/backend_initializer.dart](../../third_party/llm_llamacpp/lib/src/backend_initializer.dart), [third_party/llm_llamacpp/lib/src/bindings/llama_bindings_compat.dart](../../third_party/llm_llamacpp/lib/src/bindings/llama_bindings_compat.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/llamacpp_model.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_model.dart), [third_party/llm_llamacpp/lib/src/lora_adapter.dart](../../third_party/llm_llamacpp/lib/src/lora_adapter.dart), [third_party/llm_llamacpp/lib/src/model_loader.dart](../../third_party/llm_llamacpp/lib/src/model_loader.dart), [third_party/llm_llamacpp/lib/src/native_runtime_bridge.dart](../../third_party/llm_llamacpp/lib/src/native_runtime_bridge.dart), [third_party/llm_llamacpp/lib/src/native_template_applier.dart](../../third_party/llm_llamacpp/lib/src/native_template_applier.dart); 1 additional references in the inventory.
**Direct test references:** [test/services/native_template_applier_test.dart](../../test/services/native_template_applier_test.dart), [test_native/model_wrapper_contract_test.dart](../../test_native/model_wrapper_contract_test.dart), [test_native/qwen_thinking_control_test.dart](../../test_native/qwen_thinking_control_test.dart), [test_native/sampler_history_contract_test.dart](../../test_native/sampler_history_contract_test.dart), [test_native/unicode_tokenization_test.dart](../../test_native/unicode_tokenization_test.dart).

### `third_party/llm_llamacpp/lib/src/bindings/llama_bindings_compat.dart`

Compatibility helpers around the locked low-level bindings; isolates ABI-facing adaptation.

**Source:** [third_party/llm_llamacpp/lib/src/bindings/llama_bindings_compat.dart](../../third_party/llm_llamacpp/lib/src/bindings/llama_bindings_compat.dart).
**Declared types:** `LlamaBindingsAdapterCompatibility`, `_AppliedAdapter`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/lora_adapter.dart](../../third_party/llm_llamacpp/lib/src/lora_adapter.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).

### `third_party/llm_llamacpp/lib/src/empty_think_envelope_filter.dart`

Narrow empty structural envelope handling; not reasoning-mode control or permission to remove genuine reasoning.

**Source:** [third_party/llm_llamacpp/lib/src/empty_think_envelope_filter.dart](../../third_party/llm_llamacpp/lib/src/empty_think_envelope_filter.dart).
**Declared types:** `EmptyThinkEnvelopeFilter`.
**Direct test references:** [third_party/llm_llamacpp/test/unit/empty_think_envelope_filter_test.dart](../../third_party/llm_llamacpp/test/unit/empty_think_envelope_filter_test.dart).

### `third_party/llm_llamacpp/lib/src/error_translator.dart`

Typed translation of worker/native errors; preserves meaning across isolate transport.

**Source:** [third_party/llm_llamacpp/lib/src/error_translator.dart](../../third_party/llm_llamacpp/lib/src/error_translator.dart).
**Declared types:** `InferenceErrorTranslator`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).

### `third_party/llm_llamacpp/lib/src/exceptions.dart`

Busy, disposed, recovery, backend, context, tokenization and inference exception vocabulary; callers can distinguish recovery from bad input.

**Source:** [third_party/llm_llamacpp/lib/src/exceptions.dart](../../third_party/llm_llamacpp/lib/src/exceptions.dart).
**Declared types:** `InferenceRuntimeBusy`, `InferenceRepositoryDisposed`, `InferenceCapabilityUnsupported`, `InferenceRecoveryRequired`, `InferencePreparationCancelled`, `BackendInitException`, `InferenceException`, `ContextCreationException`, `LoraLoadException`, `TokenizationException`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/error_translator.dart](../../third_party/llm_llamacpp/lib/src/error_translator.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/llamacpp_model.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_model.dart), [third_party/llm_llamacpp/lib/src/lora_adapter.dart](../../third_party/llm_llamacpp/lib/src/lora_adapter.dart), [third_party/llm_llamacpp/lib/src/native_template_applier.dart](../../third_party/llm_llamacpp/lib/src/native_template_applier.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart](../../third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart); 3 additional references in the inventory.
**Direct test references:** [test/services/native_template_applier_test.dart](../../test/services/native_template_applier_test.dart).

### `third_party/llm_llamacpp/lib/src/generation_options.dart`

Native sampling options and ABI probability/integer bounds; validates settings before FFI.

**Source:** [third_party/llm_llamacpp/lib/src/generation_options.dart](../../third_party/llm_llamacpp/lib/src/generation_options.dart).
**Declared types:** `NativeSamplingLimits`, `GenerationOptions`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/runtime_cleanup_fault_test.dart](../../test/services/runtime_cleanup_fault_test.dart), [test/services/sampling_input_validation_test.dart](../../test/services/sampling_input_validation_test.dart).

### `third_party/llm_llamacpp/lib/src/gguf_metadata.dart`

GGUF metadata types and representation; identity/template/capability inspection does not require loading all tensors.

**Source:** [third_party/llm_llamacpp/lib/src/gguf_metadata.dart](../../third_party/llm_llamacpp/lib/src/gguf_metadata.dart).
**Declared types:** `GgufMetadataType`, `GgufMetadata`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart).

### `third_party/llm_llamacpp/lib/src/gguf_metadata_reader.dart`

Bounded buffered local GGUF reader; avoids unbounded metadata allocation and excessive per-token filesystem calls.

**Source:** [third_party/llm_llamacpp/lib/src/gguf_metadata_reader.dart](../../third_party/llm_llamacpp/lib/src/gguf_metadata_reader.dart).
**Declared types:** `_GgufBufferedReader`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/gguf_metadata.dart](../../third_party/llm_llamacpp/lib/src/gguf_metadata.dart).

### `third_party/llm_llamacpp/lib/src/inference_isolate_handler.dart`

Persistent native session request handler, prompt/template/cache and timing work; runs away from the UI isolate.

**Source:** [third_party/llm_llamacpp/lib/src/inference_isolate_handler.dart](../../third_party/llm_llamacpp/lib/src/inference_isolate_handler.dart).
**Declared types:** `_SessionTimings`, `_RuntimeProgressEmitter`, `_NativeInferenceSession`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).

### `third_party/llm_llamacpp/lib/src/inference_isolate_messages.dart`

Private prepare/generate/cancel/unload/tokenize request/response transport parts; carries request/session identity.

**Source:** [third_party/llm_llamacpp/lib/src/inference_isolate_messages.dart](../../third_party/llm_llamacpp/lib/src/inference_isolate_messages.dart).
**Declared types:** `_InferenceRequestMessage`, `_PrepareRequestMessage`, `_CancelRequestMessage`, `_UnloadRequestMessage`, `_TokenizeRequestMessage`, `_TokenCount`, `_CancellationHandle`, `_Prepared`, `_IsolateResponse`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).

### `third_party/llm_llamacpp/lib/src/inference_output_timing.dart`

Monotonic sampled/emitted timing recorder; prevents text emission being confused with rendering.

**Source:** [third_party/llm_llamacpp/lib/src/inference_output_timing.dart](../../third_party/llm_llamacpp/lib/src/inference_output_timing.dart).
**Declared types:** `InferenceOutputTiming`, `InferenceOutputTimingRecorder`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/isolate_messages.dart](../../third_party/llm_llamacpp/lib/src/isolate_messages.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/inference_output_timing_test.dart](../../test/services/inference_output_timing_test.dart).

### `third_party/llm_llamacpp/lib/src/inference_sampler_config.dart`

Native sampler-chain construction; sampling history must follow the locked API contract.

**Source:** [third_party/llm_llamacpp/lib/src/inference_sampler_config.dart](../../third_party/llm_llamacpp/lib/src/inference_sampler_config.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).

### `third_party/llm_llamacpp/lib/src/inference_token_generator.dart`

Native token decode/output/stop loop; handles single acceptance, bounded output and request completion reasons.

**Source:** [third_party/llm_llamacpp/lib/src/inference_token_generator.dart](../../third_party/llm_llamacpp/lib/src/inference_token_generator.dart).
**Declared types:** `_GenerationResult`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).

### `third_party/llm_llamacpp/lib/src/isolate_messages.dart`

Public typed token/configuration/completion/cancellation/error/progress events; replaces interpreting error-looking text as ordinary output.

**Source:** [third_party/llm_llamacpp/lib/src/isolate_messages.dart](../../third_party/llm_llamacpp/lib/src/isolate_messages.dart).
**Declared types:** `IsolateMessage`, `InferenceToken`, `InferenceRuntimeConfiguration`, `InferenceComplete`, `InferenceCompletionReason`, `InferenceCancelled`, `InferenceError`, `InferenceCleanupRequired`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/native_template_applier.dart](../../third_party/llm_llamacpp/lib/src/native_template_applier.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/inference_output_timing_test.dart](../../test/services/inference_output_timing_test.dart), [test/services/native_template_applier_test.dart](../../test/services/native_template_applier_test.dart), [test_native/benchmark_workload_test.dart](../../test_native/benchmark_workload_test.dart), [test_native/helper_cleanup_fault_test.dart](../../test_native/helper_cleanup_fault_test.dart), [test_native/output_timing_contract_test.dart](../../test_native/output_timing_contract_test.dart); more in the test map.

### `third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart`

Public repository facade, owned resources and metrics; implements the llm_core chat contract for local inference.

**Source:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).
**Declared types:** `LlamaCppChatRepository`, `LlamaCppInferenceMetrics`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart).

### `third_party/llm_llamacpp/lib/src/llamacpp_chat_repository_deprecated.dart`

Retained deprecated compatibility surface; not a separate app inference architecture.

**Source:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository_deprecated.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository_deprecated.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).

### `third_party/llm_llamacpp/lib/src/llamacpp_chat_repository_impl.dart`

Repository implementation part for streaming, shutdown and late-event rejection; belongs to the facade, not a second runtime.

**Source:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository_impl.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository_impl.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).

### `third_party/llm_llamacpp/lib/src/llamacpp_model.dart`

Native model handle/path/options lifecycle; ownership must outlive active context work.

**Source:** [third_party/llm_llamacpp/lib/src/llamacpp_model.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_model.dart).
**Declared types:** `LlamaCppModel`, `ModelLoadOptions`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/lora_adapter.dart](../../third_party/llm_llamacpp/lib/src/lora_adapter.dart), [third_party/llm_llamacpp/lib/src/model_loader.dart](../../third_party/llm_llamacpp/lib/src/model_loader.dart).

### `third_party/llm_llamacpp/lib/src/loader/loader.dart`

Conditional Flutter/pure-Dart loader dispatch; platform selection determines how code assets are opened.

**Source:** [third_party/llm_llamacpp/lib/src/loader/loader.dart](../../third_party/llm_llamacpp/lib/src/loader/loader.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/backend_initializer.dart](../../third_party/llm_llamacpp/lib/src/backend_initializer.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/llamacpp_model.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_model.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/model_installation_promoter_test.dart](../../test/services/model_installation_promoter_test.dart), [test_native/model_wrapper_contract_test.dart](../../test_native/model_wrapper_contract_test.dart), [test_native/owner_close_recovery_test.dart](../../test_native/owner_close_recovery_test.dart), [test_native/qwen_thinking_control_test.dart](../../test_native/qwen_thinking_control_test.dart), [test_native/sampler_history_contract_test.dart](../../test_native/sampler_history_contract_test.dart); more in the test map.

### `third_party/llm_llamacpp/lib/src/loader/loader_flutter.dart`

Flutter platform dynamic-library loader; host tester library search paths still require explicit qualification.

**Source:** [third_party/llm_llamacpp/lib/src/loader/loader_flutter.dart](../../third_party/llm_llamacpp/lib/src/loader/loader_flutter.dart).

### `third_party/llm_llamacpp/lib/src/loader/loader_io.dart`

Pure-Dart library search/override/dependency loading; retained generic search behaviour is not a desktop product-support promise.

**Source:** [third_party/llm_llamacpp/lib/src/loader/loader_io.dart](../../third_party/llm_llamacpp/lib/src/loader/loader_io.dart).

### `third_party/llm_llamacpp/lib/src/loader/loader_stub.dart`

Unsupported-loader fallback; fails explicitly where native loading is unavailable.

**Source:** [third_party/llm_llamacpp/lib/src/loader/loader_stub.dart](../../third_party/llm_llamacpp/lib/src/loader/loader_stub.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/loader/loader.dart](../../third_party/llm_llamacpp/lib/src/loader/loader.dart).

### `third_party/llm_llamacpp/lib/src/loader/native_library_path.dart`

Native library location support; keeps path resolution out of higher-level model logic.

**Source:** [third_party/llm_llamacpp/lib/src/loader/native_library_path.dart](../../third_party/llm_llamacpp/lib/src/loader/native_library_path.dart).
**Declared types:** `DlInfo`, `DladdrNative`, `DladdrDart`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/backend_initializer.dart](../../third_party/llm_llamacpp/lib/src/backend_initializer.dart).

### `third_party/llm_llamacpp/lib/src/lora_adapter.dart`

Vendored LoRA adapter representation/lifecycle; no corresponding supported VITALIS user feature is implied.

**Source:** [third_party/llm_llamacpp/lib/src/lora_adapter.dart](../../third_party/llm_llamacpp/lib/src/lora_adapter.dart).
**Declared types:** `LlamaLoraAdapter`, `LoraManager`, `LoraConfig`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).

### `third_party/llm_llamacpp/lib/src/model_loader.dart`

Native model-load helpers; separates model resources from conversation orchestration.

**Source:** [third_party/llm_llamacpp/lib/src/model_loader.dart](../../third_party/llm_llamacpp/lib/src/model_loader.dart).
**Declared types:** `LlamaCppModelLoader`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart).

### `third_party/llm_llamacpp/lib/src/native_log.dart`

Injectable native diagnostic facade; release verbosity and redaction remain application concerns.

**Source:** [third_party/llm_llamacpp/lib/src/native_log.dart](../../third_party/llm_llamacpp/lib/src/native_log.dart).
**Declared types:** `NativeLogLevel`, `NativeLogSink`, `NativeLog`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/backend_initializer.dart](../../third_party/llm_llamacpp/lib/src/backend_initializer.dart), [third_party/llm_llamacpp/lib/src/loader/loader_flutter.dart](../../third_party/llm_llamacpp/lib/src/loader/loader_flutter.dart), [third_party/llm_llamacpp/lib/src/loader/loader_io.dart](../../third_party/llm_llamacpp/lib/src/loader/loader_io.dart), [third_party/llm_llamacpp/lib/src/loader/native_library_path.dart](../../third_party/llm_llamacpp/lib/src/loader/native_library_path.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).

### `third_party/llm_llamacpp/lib/src/native_runtime_bridge.dart`

Dart access to native cancellation, backend and model-file ownership operations; lease lifetime prevents unsafe file mutation.

**Source:** [third_party/llm_llamacpp/lib/src/native_runtime_bridge.dart](../../third_party/llm_llamacpp/lib/src/native_runtime_bridge.dart).
**Declared types:** `NativeRuntimeBridge`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/backend_initializer.dart](../../third_party/llm_llamacpp/lib/src/backend_initializer.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/llamacpp_model.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_model.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/model_installation_promoter_test.dart](../../test/services/model_installation_promoter_test.dart), [test_native/model_wrapper_contract_test.dart](../../test_native/model_wrapper_contract_test.dart), [test_native/owner_close_recovery_test.dart](../../test_native/owner_close_recovery_test.dart).

### `third_party/llm_llamacpp/lib/src/native_template_applier.dart`

Native configured chat-template invocation; token counting and generation use the same rendering authority.

**Source:** [third_party/llm_llamacpp/lib/src/native_template_applier.dart](../../third_party/llm_llamacpp/lib/src/native_template_applier.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/native_template_applier_test.dart](../../test/services/native_template_applier_test.dart).

### `third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart`

Persistent worker ownership/transport and context retention; central model/context session instead of per-message reload.

**Source:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Declared types:** `PersistentInferenceIsolate`, `NativeRuntimePolicy`, `_PreparationAdmission`, `_HelperStart`, `_InitializationProgress`, `_InitializationFailure`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).
**Direct test references:** [test/services/runtime_cleanup_fault_test.dart](../../test/services/runtime_cleanup_fault_test.dart), [test/services/sampling_input_validation_test.dart](../../test/services/sampling_input_validation_test.dart), [test_native/cold_generation_loading_cancellation_test.dart](../../test_native/cold_generation_loading_cancellation_test.dart), [test_native/cold_tokenization_cancellation_test.dart](../../test_native/cold_tokenization_cancellation_test.dart), [test_native/helper_cleanup_fault_test.dart](../../test_native/helper_cleanup_fault_test.dart); more in the test map.

### `third_party/llm_llamacpp/lib/src/prompt_batching.dart`

Bounded prompt chunk construction/decoding helpers; prompts larger than batch must not abort native decode.

**Source:** [third_party/llm_llamacpp/lib/src/prompt_batching.dart](../../third_party/llm_llamacpp/lib/src/prompt_batching.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [third_party/llm_llamacpp/test/unit/prompt_batching_test.dart](../../third_party/llm_llamacpp/test/unit/prompt_batching_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_cancellation_control.dart`

Request-scoped cancellation transport bookkeeping; native acknowledgement, not a Dart flag, establishes stop.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_cancellation_control.dart](../../third_party/llm_llamacpp/lib/src/runtime_cancellation_control.dart).
**Declared types:** `RuntimeCancellationControl`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/runtime_cancellation_control_test.dart](../../test/services/runtime_cancellation_control_test.dart), [test/services/runtime_cleanup_quarantine_test.dart](../../test/services/runtime_cleanup_quarantine_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_cleanup_fault.dart`

Explicitly gated native cleanup fault injection; normal builds must not accept test fault commands.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_cleanup_fault.dart](../../third_party/llm_llamacpp/lib/src/runtime_cleanup_fault.dart).
**Declared types:** `RuntimeCleanupFault`, `RuntimeCleanupFaultController`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [tool/runtime_fault_mode_probe.dart](../../tool/runtime_fault_mode_probe.dart).
**Direct test references:** [test/services/runtime_cleanup_fault_test.dart](../../test/services/runtime_cleanup_fault_test.dart), [test_native/helper_cleanup_fault_test.dart](../../test_native/helper_cleanup_fault_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_cleanup_quarantine.dart`

Retained unconfirmed cleanup transport records; prevents false readiness without creating another ownership lock.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_cleanup_quarantine.dart](../../third_party/llm_llamacpp/lib/src/runtime_cleanup_quarantine.dart).
**Declared types:** `RuntimeCleanupQuarantine`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/runtime_cleanup_quarantine_test.dart](../../test/services/runtime_cleanup_quarantine_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart`

Initialization waiter/late-completion guard; timeout retains ownership of still-running initialization.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart](../../third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart).
**Declared types:** `RuntimeInitializationGuard`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [third_party/llm_llamacpp/lib/src/runtime_shutdown_waiter.dart](../../third_party/llm_llamacpp/lib/src/runtime_shutdown_waiter.dart).
**Direct test references:** [test/services/runtime_initialization_guard_test.dart](../../test/services/runtime_initialization_guard_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_native_termination.dart`

Terminal native acknowledgement tracking independent of a paused consumer; proves request settlement.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_native_termination.dart](../../third_party/llm_llamacpp/lib/src/runtime_native_termination.dart).
**Declared types:** `NativeTerminationOutcome`, `RuntimeNativeTermination`, `_NativeTerminationRequest`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/runtime_native_termination_test.dart](../../test/services/runtime_native_termination_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_owner_recovery_guard.dart`

Shares one owner's recovery attempt; reservation remains the authority granting native access.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_owner_recovery_guard.dart](../../third_party/llm_llamacpp/lib/src/runtime_owner_recovery_guard.dart).
**Declared types:** `RuntimeOwnerRecoveryGuard`.
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/services/chat_state_controller.dart](../../lib/services/chat_state_controller.dart), [lib/services/model_verification_runtime.dart](../../lib/services/model_verification_runtime.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).
**Direct test references:** [test/services/runtime_owner_recovery_guard_test.dart](../../test/services/runtime_owner_recovery_guard_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_progress.dart`

Typed real decode/initialization progress and tracking; timer heartbeats are not completed native work.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_progress.dart](../../third_party/llm_llamacpp/lib/src/runtime_progress.dart).
**Declared types:** `RuntimeProgressPhase`, `RuntimeProgress`, `LlamaCppProgressChunk`, `RuntimeProgressTracker`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart](../../third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart).

### `third_party/llm_llamacpp/lib/src/runtime_request_finalizer.dart`

Request-local cleanup outcome and finalization; publication failure does not establish receiver acknowledgement.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_request_finalizer.dart](../../third_party/llm_llamacpp/lib/src/runtime_request_finalizer.dart).
**Declared types:** `RuntimeCleanupStep`, `RuntimeCleanupOutcome`, `RuntimeRequestFinalizer`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [third_party/llm_llamacpp/lib/src/runtime_cleanup_fault.dart](../../third_party/llm_llamacpp/lib/src/runtime_cleanup_fault.dart).
**Direct test references:** [test/services/runtime_cleanup_fault_test.dart](../../test/services/runtime_cleanup_fault_test.dart), [test/services/runtime_cleanup_quarantine_test.dart](../../test/services/runtime_cleanup_quarantine_test.dart), [test/services/runtime_request_finalizer_test.dart](../../test/services/runtime_request_finalizer_test.dart), [test_native/helper_cleanup_fault_test.dart](../../test_native/helper_cleanup_fault_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_session_reservation.dart`

Single operation/context ownership authority and immutable diagnostic snapshot; rejects competing prepare/cancel/unload work.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_session_reservation.dart](../../third_party/llm_llamacpp/lib/src/runtime_session_reservation.dart).
**Declared types:** `RuntimeOperationKind`, `RuntimeReservationState`, `RuntimeRecoveryOutcome`, `RuntimeOperationSnapshot`, `RuntimeSessionReservation`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [third_party/llm_llamacpp/lib/src/runtime_owner_recovery_guard.dart](../../third_party/llm_llamacpp/lib/src/runtime_owner_recovery_guard.dart).
**Direct test references:** [test/services/runtime_cleanup_quarantine_test.dart](../../test/services/runtime_cleanup_quarantine_test.dart), [test/services/runtime_session_recovery_test.dart](../../test/services/runtime_session_recovery_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_shutdown_waiter.dart`

Bounded observation of owned shutdown; timeout never shortens underlying native resource lifetime.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_shutdown_waiter.dart](../../third_party/llm_llamacpp/lib/src/runtime_shutdown_waiter.dart).
**Declared types:** `RuntimeShutdownWaiter`.
**Referenced by:** [lib/providers/generation_provider.dart](../../lib/providers/generation_provider.dart), [lib/services/chat_state_controller.dart](../../lib/services/chat_state_controller.dart), [lib/services/model_warmup_service.dart](../../lib/services/model_warmup_service.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [third_party/llm_llamacpp/lib/src/runtime_native_termination.dart](../../third_party/llm_llamacpp/lib/src/runtime_native_termination.dart).
**Direct test references:** [test/services/runtime_shutdown_waiter_test.dart](../../test/services/runtime_shutdown_waiter_test.dart).

### `third_party/llm_llamacpp/lib/src/runtime_watchdog_policy.dart`

Named native initialization/progress/shutdown deadlines; centralizes timing policy rather than scattering wait literals.

**Source:** [third_party/llm_llamacpp/lib/src/runtime_watchdog_policy.dart](../../third_party/llm_llamacpp/lib/src/runtime_watchdog_policy.dart).
**Declared types:** `RuntimeWatchdogTimerFactory`, `RuntimeWatchdogPolicy`, `RuntimeWatchdogDefaults`.
**Referenced by:** [lib/models/generation_watchdog_policy.dart](../../lib/models/generation_watchdog_policy.dart), [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart), [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart), [third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart](../../third_party/llm_llamacpp/lib/src/runtime_initialization_guard.dart), [third_party/llm_llamacpp/lib/src/runtime_native_termination.dart](../../third_party/llm_llamacpp/lib/src/runtime_native_termination.dart), [third_party/llm_llamacpp/lib/src/runtime_shutdown_waiter.dart](../../third_party/llm_llamacpp/lib/src/runtime_shutdown_waiter.dart).

### `third_party/llm_llamacpp/lib/src/stop_sequence_prefix.dart`

Partial stop-marker prefix handling; buffers only text that could still become a stop sequence.

**Source:** [third_party/llm_llamacpp/lib/src/stop_sequence_prefix.dart](../../third_party/llm_llamacpp/lib/src/stop_sequence_prefix.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart](../../third_party/llm_llamacpp/lib/src/persistent_inference_isolate.dart).
**Direct test references:** [test/services/stop_sequence_prefix_test.dart](../../test/services/stop_sequence_prefix_test.dart).

### `third_party/llm_llamacpp/lib/src/third_party/vitalis_chat_template.g.dart`

Generated template-bridge FFI bindings; regenerate from the owned native header rather than hand-editing signatures.

**Source:** [third_party/llm_llamacpp/lib/src/third_party/vitalis_chat_template.g.dart](../../third_party/llm_llamacpp/lib/src/third_party/vitalis_chat_template.g.dart).
**Referenced by:** [third_party/llm_llamacpp/lib/src/native_template_applier.dart](../../third_party/llm_llamacpp/lib/src/native_template_applier.dart).
**Direct test references:** [test_native/qwen_thinking_control_test.dart](../../test_native/qwen_thinking_control_test.dart).

### `third_party/llm_llamacpp/lib/src/third_party/vitalis_chat_template.record_use_mapping.g.dart`

Generated native-use mapping for tooling/tree shaking; metadata, not a separate runtime feature.

**Source:** [third_party/llm_llamacpp/lib/src/third_party/vitalis_chat_template.record_use_mapping.g.dart](../../third_party/llm_llamacpp/lib/src/third_party/vitalis_chat_template.record_use_mapping.g.dart).

### `third_party/llm_llamacpp/lib/src/tool_call_parser.dart`

Generic vendored tool-call parser; presence does not mean VITALIS exposes autonomous external tools.

**Source:** [third_party/llm_llamacpp/lib/src/tool_call_parser.dart](../../third_party/llm_llamacpp/lib/src/tool_call_parser.dart).
**Declared types:** `ToolCallParser`.
**Referenced by:** [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/tool_call_stream_handler.dart](../../third_party/llm_llamacpp/lib/src/tool_call_stream_handler.dart).
**Direct test references:** [third_party/llm_llamacpp/test/unit/tool_call_parser_test.dart](../../third_party/llm_llamacpp/test/unit/tool_call_parser_test.dart).

### `third_party/llm_llamacpp/lib/src/tool_call_stream_handler.dart`

Generic vendored streamed tool-call handling; distinguish retained package capability from app UI support.

**Source:** [third_party/llm_llamacpp/lib/src/tool_call_stream_handler.dart](../../third_party/llm_llamacpp/lib/src/tool_call_stream_handler.dart).
**Declared types:** `StreamHandlerResult`, `ToolCallStreamHandler`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).

### `third_party/llm_llamacpp/lib/src/tool_executor.dart`

Generic vendored tool execution helper; not a promise of enabled system/web tools in VITALIS.

**Source:** [third_party/llm_llamacpp/lib/src/tool_executor.dart](../../third_party/llm_llamacpp/lib/src/tool_executor.dart).
**Declared types:** `ToolExecutor`.
**Referenced by:** [third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart](../../third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart).

### `third_party/llm_llamacpp/lib/src/verified_thinking_templates.dart`

Audited template-content hash allowlist; thinking capability is not inferred from a filename.

**Source:** [third_party/llm_llamacpp/lib/src/verified_thinking_templates.dart](../../third_party/llm_llamacpp/lib/src/verified_thinking_templates.dart).
**Declared types:** `VerifiedThinkingTemplates`.
**Referenced by:** [lib/models/model_descriptor.dart](../../lib/models/model_descriptor.dart), [third_party/llm_llamacpp/lib/llm_llamacpp.dart](../../third_party/llm_llamacpp/lib/llm_llamacpp.dart), [third_party/llm_llamacpp/lib/src/native_template_applier.dart](../../third_party/llm_llamacpp/lib/src/native_template_applier.dart).

## Native runtime / native

### `third_party/llm_llamacpp/native/llama_cpp.lock.json`

Immutable llama.cpp commit/archive hash and Android native policy; source provenance, not executable code.

**Source:** [third_party/llm_llamacpp/native/llama_cpp.lock.json](../../third_party/llm_llamacpp/native/llama_cpp.lock.json).

### `third_party/llm_llamacpp/native/vitalis_chat_template.cpp`

Configured upstream Jinja rendering bridge; provides verified thinking/template behaviour without soft prompt-switch guessing.

**Source:** [third_party/llm_llamacpp/native/vitalis_chat_template.cpp](../../third_party/llm_llamacpp/native/vitalis_chat_template.cpp).

### `third_party/llm_llamacpp/native/vitalis_chat_template.h`

C ABI for the owned template bridge; authority for generated Dart template declarations.

**Source:** [third_party/llm_llamacpp/native/vitalis_chat_template.h](../../third_party/llm_llamacpp/native/vitalis_chat_template.h).
**Declared types:** `vitalis_chat_template_error`.

### `third_party/llm_llamacpp/native/vitalis_runtime_bridge.cpp`

Native atomic cancellation, backend ownership and file lease bridge; native threads never call arbitrary Dart logging callbacks.

**Source:** [third_party/llm_llamacpp/native/vitalis_runtime_bridge.cpp](../../third_party/llm_llamacpp/native/vitalis_runtime_bridge.cpp).

## Native runtime / pubspec.lock

### `third_party/llm_llamacpp/pubspec.lock`

Exact vendored development/test resolution; required for enforced clean dependency restoration.

**Source:** [third_party/llm_llamacpp/pubspec.lock](../../third_party/llm_llamacpp/pubspec.lock).

## Native runtime / pubspec.yaml

### `third_party/llm_llamacpp/pubspec.yaml`

Vendored dependencies and generic platform declarations; VITALIS delivery support is narrower than these declarations.

**Source:** [third_party/llm_llamacpp/pubspec.yaml](../../third_party/llm_llamacpp/pubspec.yaml).

## Native runtime / src

### `third_party/llm_llamacpp/src/include/ggml-alloc.h`

Retained upstream ggml-alloc.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/ggml-alloc.h](../../third_party/llm_llamacpp/src/include/ggml-alloc.h).
**Declared types:** `struct`.

### `third_party/llm_llamacpp/src/include/ggml-backend.h`

Retained upstream ggml-backend.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/ggml-backend.h](../../third_party/llm_llamacpp/src/include/ggml-backend.h).
**Declared types:** `struct`, `void`, `ggml_backend_buffer_usage`, `ggml_backend_dev_type`, `bool`, `ggml_backend_buffer_type_t`, `ggml_backend_meta_split_axis`.

### `third_party/llm_llamacpp/src/include/ggml-blas.h`

Retained upstream blas backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-blas.h](../../third_party/llm_llamacpp/src/include/ggml-blas.h).

### `third_party/llm_llamacpp/src/include/ggml-cann.h`

Retained upstream cann backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-cann.h](../../third_party/llm_llamacpp/src/include/ggml-cann.h).

### `third_party/llm_llamacpp/src/include/ggml-cpp.h`

Retained upstream ggml-cpp.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/ggml-cpp.h](../../third_party/llm_llamacpp/src/include/ggml-cpp.h).
**Declared types:** `std`.

### `third_party/llm_llamacpp/src/include/ggml-cpu.h`

Retained upstream ggml-cpu.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/ggml-cpu.h](../../third_party/llm_llamacpp/src/include/ggml-cpu.h).
**Declared types:** `ggml_numa_strategy`, `void`, `ggml_type`.

### `third_party/llm_llamacpp/src/include/ggml-cuda.h`

Retained upstream cuda backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-cuda.h](../../third_party/llm_llamacpp/src/include/ggml-cuda.h).

### `third_party/llm_llamacpp/src/include/ggml-et.h`

Retained upstream et backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-et.h](../../third_party/llm_llamacpp/src/include/ggml-et.h).

### `third_party/llm_llamacpp/src/include/ggml-hexagon.h`

Retained upstream hexagon backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-hexagon.h](../../third_party/llm_llamacpp/src/include/ggml-hexagon.h).

### `third_party/llm_llamacpp/src/include/ggml-metal.h`

Retained upstream metal backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-metal.h](../../third_party/llm_llamacpp/src/include/ggml-metal.h).

### `third_party/llm_llamacpp/src/include/ggml-opencl.h`

Retained upstream opencl backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-opencl.h](../../third_party/llm_llamacpp/src/include/ggml-opencl.h).

### `third_party/llm_llamacpp/src/include/ggml-openvino.h`

Retained upstream openvino backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-openvino.h](../../third_party/llm_llamacpp/src/include/ggml-openvino.h).

### `third_party/llm_llamacpp/src/include/ggml-opt.h`

Retained upstream ggml-opt.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/ggml-opt.h](../../third_party/llm_llamacpp/src/include/ggml-opt.h).
**Declared types:** `struct`, `ggml_opt_loss_type`, `ggml_type`, `ggml_opt_build_type`, `ggml_opt_optimizer_type`, `void`.

### `third_party/llm_llamacpp/src/include/ggml-rpc.h`

Retained upstream rpc backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-rpc.h](../../third_party/llm_llamacpp/src/include/ggml-rpc.h).

### `third_party/llm_llamacpp/src/include/ggml-sycl.h`

Retained upstream sycl backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-sycl.h](../../third_party/llm_llamacpp/src/include/ggml-sycl.h).

### `third_party/llm_llamacpp/src/include/ggml-virtgpu.h`

Retained upstream virtgpu backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-virtgpu.h](../../third_party/llm_llamacpp/src/include/ggml-virtgpu.h).

### `third_party/llm_llamacpp/src/include/ggml-vulkan.h`

Retained upstream vulkan backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-vulkan.h](../../third_party/llm_llamacpp/src/include/ggml-vulkan.h).

### `third_party/llm_llamacpp/src/include/ggml-webgpu.h`

Retained upstream webgpu backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-webgpu.h](../../third_party/llm_llamacpp/src/include/ggml-webgpu.h).

### `third_party/llm_llamacpp/src/include/ggml-zdnn.h`

Retained upstream zdnn backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-zdnn.h](../../third_party/llm_llamacpp/src/include/ggml-zdnn.h).

### `third_party/llm_llamacpp/src/include/ggml-zendnn.h`

Retained upstream zendnn backend API declarations. Header presence does not mean this backend is built, enabled, delivered or physically qualified by VITALIS.

**Source:** [third_party/llm_llamacpp/src/include/ggml-zendnn.h](../../third_party/llm_llamacpp/src/include/ggml-zendnn.h).

### `third_party/llm_llamacpp/src/include/ggml.h`

Retained upstream ggml.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/ggml.h](../../third_party/llm_llamacpp/src/include/ggml.h).
**Declared types:** `void`, `ggml_status`, `uint16_t`, `struct`, `ggml_type`, `ggml_prec`, `ggml_op_hint`, `ggml_ftype`, `ggml_op`, `ggml_unary_op`, `ggml_glu_op`, `ggml_object_type`, `ggml_log_level`, `ggml_tensor_flag`, `ggml_tri_type`, `bool`, `uint8_t`, `ggml_guid`, `ggml_op_pool`, `ggml_scale_mode`, `ggml_scale_flag`, `ggml_sort_order`, `ggml_sched_priority`.

### `third_party/llm_llamacpp/src/include/gguf.h`

Retained upstream gguf.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/gguf.h](../../third_party/llm_llamacpp/src/include/gguf.h).
**Declared types:** `gguf_type`, `size_t`.

### `third_party/llm_llamacpp/src/include/llama-cpp.h`

Retained upstream llama-cpp.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/llama-cpp.h](../../third_party/llm_llamacpp/src/include/llama-cpp.h).
**Declared types:** `std`.

### `third_party/llm_llamacpp/src/include/llama.h`

Retained upstream llama.h API declarations for tensor/model/format integration; build authority remains the hash-locked archive headers, not an assumed match to this copy.

**Source:** [third_party/llm_llamacpp/src/include/llama.h](../../third_party/llm_llamacpp/src/include/llama.h).
**Declared types:** `struct`, `int32_t`, `llama_vocab_type`, `llama_rope_type`, `llama_token_type`, `llama_token_attr`, `llama_ftype`, `llama_rope_scaling_type`, `llama_pooling_type`, `llama_attention_type`, `llama_flash_attn_type`, `llama_split_mode`, `llama_load_mode`, `llama_lazy_mode`, `llama_context_type`, `bool`, `llama_model_kv_override_type`, `llama_model_meta_key`, `ggml_type`, `void`, `uint32_t`, `ggml_opt_optimizer_type`.

### `third_party/llm_llamacpp/src/llama.h`

Additional retained llama C header copy; verify exact revision/ABI before generating bindings. The locked build source is authoritative.

**Source:** [third_party/llm_llamacpp/src/llama.h](../../third_party/llm_llamacpp/src/llama.h).
**Declared types:** `struct`, `int32_t`, `llama_vocab_type`, `llama_rope_type`, `llama_token_type`, `llama_token_attr`, `llama_ftype`, `llama_rope_scaling_type`, `llama_pooling_type`, `llama_attention_type`, `llama_flash_attn_type`, `llama_split_mode`, `llama_load_mode`, `llama_lazy_mode`, `llama_context_type`, `bool`, `llama_model_kv_override_type`, `llama_model_meta_key`, `ggml_type`, `void`, `uint32_t`, `ggml_opt_optimizer_type`.

## Native runtime / tool

### `third_party/llm_llamacpp/tool/ffigen.dart`

Owned template-header FFI generator with code-asset ID and use mapping; VITALIS_LIBCLANG can select libclang.

**Source:** [third_party/llm_llamacpp/tool/ffigen.dart](../../third_party/llm_llamacpp/tool/ffigen.dart).

## Native runtime / windows

### `third_party/llm_llamacpp/windows/llm_llamacpp_plugin.cpp`

Retained no-op legacy FFI plugin registrar; Native Assets packages the actual VITALIS native libraries.

**Source:** [third_party/llm_llamacpp/windows/llm_llamacpp_plugin.cpp](../../third_party/llm_llamacpp/windows/llm_llamacpp_plugin.cpp).

## Developer tools and verification

### `tool/JavaHardcodeScanner.java`

Java-side behavioural-constant scanning support; complements the registered-policy verifier.

**Source:** [tool/JavaHardcodeScanner.java](../../tool/JavaHardcodeScanner.java).
**Declared types:** `JavaHardcodeScanner`.

### `tool/TestReleaseAbiCollection.ps1`

Standalone regression for release ABI collection; tests packaging inspection, not runtime model quality.

**Source:** [tool/TestReleaseAbiCollection.ps1](../../tool/TestReleaseAbiCollection.ps1).

### `tool/TransferCoverageGate.java`

Java transfer coverage threshold and freshness verification; absence of coverage cannot count as success.

**Source:** [tool/TransferCoverageGate.java](../../tool/TransferCoverageGate.java).
**Declared types:** `TransferCoverageGate`.

### `tool/VerifyAndroidNativeInventory.java`

APK/AAB native inventory, ABI/dependency and code-asset checks; detects missing or unintended native payloads.

**Source:** [tool/VerifyAndroidNativeInventory.java](../../tool/VerifyAndroidNativeInventory.java).
**Declared types:** `VerifyAndroidNativeInventory`.

### `tool/VerifyFlutterNotices.java`

Android archive notice/licence inspection; validates required attribution in packaged artifacts.

**Source:** [tool/VerifyFlutterNotices.java](../../tool/VerifyFlutterNotices.java).
**Declared types:** `VerifyFlutterNotices`.

### `tool/VerifyGradleBootstrap.java`

Gradle wrapper/bootstrap policy inspection; verifies source/wrapper authority before native builds.

**Source:** [tool/VerifyGradleBootstrap.java](../../tool/VerifyGradleBootstrap.java).
**Declared types:** `VerifyGradleBootstrap`.

### `tool/VerifyUnsignedArtifacts.java`

Positive APK/AAB signature-structure inspection; a failed external signing tool alone cannot prove unsigned status.

**Source:** [tool/VerifyUnsignedArtifacts.java](../../tool/VerifyUnsignedArtifacts.java).
**Declared types:** `VerifyUnsignedArtifacts`.

### `tool/build_split_test_fixture.js`

Builds the locked upstream split helper and prepares a bounded split-model test fixture; never changes an original GGUF.

**Source:** [tool/build_split_test_fixture.js](../../tool/build_split_test_fixture.js).

### `tool/export_brand_icons.ps1`

Exports source branding into platform icon assets; design-generation tooling, not inference logic.

**Source:** [tool/export_brand_icons.ps1](../../tool/export_brand_icons.ps1).

### `tool/export_bundled_model_manifest.dart`

Dependency-free manifest export for CI fixture identity; avoids duplicating model revision/hash in workflow YAML.

**Source:** [tool/export_bundled_model_manifest.dart](../../tool/export_bundled_model_manifest.dart).
**Direct test references:** [test/tool/bundled_model_ci_test.dart](../../test/tool/bundled_model_ci_test.dart).

### `tool/generation_lock.dart`

Checkout-wide ownership lock for managed Flutter/native generation; protects shared generated outputs from races.

**Source:** [tool/generation_lock.dart](../../tool/generation_lock.dart).
**Declared types:** `GenerationLock`.
**Direct test references:** [test/tool/gate_safety_test.dart](../../test/tool/gate_safety_test.dart).

### `tool/package_windows_preview.ps1`

Portable Windows packaging from the completed CMake install manifest, licences and dependency inspection; refuses a dirty source tree.

**Source:** [tool/package_windows_preview.ps1](../../tool/package_windows_preview.ps1).

### `tool/prepare_split_fixture.dart`

Validates and records a split GGUF fixture/provenance; product native tests can require complete known shards.

**Source:** [tool/prepare_split_fixture.dart](../../tool/prepare_split_fixture.dart).
**Direct test references:** [test/tool/split_fixture_options_test.dart](../../test/tool/split_fixture_options_test.dart).

### `tool/run_android_release_gate.ps1`

Windows serialized Android release build/lint/inspection orchestration; release verification remains unsigned.

**Source:** [tool/run_android_release_gate.ps1](../../tool/run_android_release_gate.ps1).

### `tool/run_android_release_gate.sh`

POSIX equivalent of serialized Android release qualification; uses supported Flutter build commands.

**Source:** [tool/run_android_release_gate.sh](../../tool/run_android_release_gate.sh).

### `tool/run_gate.ps1`

Windows pinned-environment/lock/cache validation and Flutter command launcher; ordinary shell Java cannot silently choose the build.

**Source:** [tool/run_gate.ps1](../../tool/run_gate.ps1).

### `tool/run_gate.sh`

POSIX pinned-environment/lock/cache validation and Flutter launcher; preserves the same source policy across hosts.

**Source:** [tool/run_gate.sh](../../tool/run_gate.sh).

### `tool/runtime_fault_mode_probe.dart`

Controlled native fault-mode diagnostic entry; verifies compile-mode isolation of test-only faults.

**Source:** [tool/runtime_fault_mode_probe.dart](../../tool/runtime_fault_mode_probe.dart).

### `tool/toolchain_policy.json`

Machine-readable SDK/compiler/ABI/checksum authority; consumed by launchers, verifiers and CI.

**Source:** [tool/toolchain_policy.json](../../tool/toolchain_policy.json).

### `tool/validate_flutter_version.dart`

Structural Flutter/Dart machine-version validation; avoids whitespace/text-grep version assumptions.

**Source:** [tool/validate_flutter_version.dart](../../tool/validate_flutter_version.dart).
**Direct test references:** [test/tool/flutter_version_gate_test.dart](../../test/tool/flutter_version_gate_test.dart).

### `tool/verify_ci_acceptance.js`

Aggregate job-result gate; rejects failed, cancelled or skipped mandatory results.

**Source:** [tool/verify_ci_acceptance.js](../../tool/verify_ci_acceptance.js).

### `tool/verify_ci_workflow.dart`

Product-specific YAML/evidence/dependency contract validation; not a replacement for GitHub schema validation.

**Source:** [tool/verify_ci_workflow.dart](../../tool/verify_ci_workflow.dart).
**Direct test references:** [test/tool/ci_workflow_gate_test.dart](../../test/tool/ci_workflow_gate_test.dart), [tool/test_ci_workflow.dart](../../tool/test_ci_workflow.dart).

### `tool/verify_clean_outputs.dart`

Generated-output cleanup verification; does not authorize deleting user/source data.

**Source:** [tool/verify_clean_outputs.dart](../../tool/verify_clean_outputs.dart).
**Direct test references:** [test/tool/clean_outputs_test.dart](../../test/tool/clean_outputs_test.dart).

### `tool/verify_coverage.dart`

Risk-based Dart coverage verification with required-file checks; scope must match the report actually collected.

**Source:** [tool/verify_coverage.dart](../../tool/verify_coverage.dart).
**Declared types:** `CoverageRequirement`.
**Direct test references:** [test/tool/coverage_gate_test.dart](../../test/tool/coverage_gate_test.dart), [tool/test_coverage_integrity.dart](../../tool/test_coverage_integrity.dart).

### `tool/verify_flutter_notices.dart`

Flutter notice/licence verification support; keeps packaging notices traceable.

**Source:** [tool/verify_flutter_notices.dart](../../tool/verify_flutter_notices.dart).

### `tool/verify_flutter_selection.dart`

Checks Flutter's effective JDK/SDK configuration against the selected environment.

**Source:** [tool/verify_flutter_selection.dart](../../tool/verify_flutter_selection.dart).
**Direct test references:** [test/tool/flutter_selection_test.dart](../../test/tool/flutter_selection_test.dart).

### `tool/verify_gate_environment.dart`

Cache containment, SDK/NDK and conflicting-environment checks; rejects unsafe/out-of-checkout cache selections.

**Source:** [tool/verify_gate_environment.dart](../../tool/verify_gate_environment.dart).
**Referenced by:** [tool/verify_flutter_selection.dart](../../tool/verify_flutter_selection.dart).
**Direct test references:** [test/tool/gate_safety_test.dart](../../test/tool/gate_safety_test.dart).

### `tool/verify_hardcode_register.dart`

Registered behavioural-constant/disposition verification; passing registered scope is not a claim that every constant is reviewed.

**Source:** [tool/verify_hardcode_register.dart](../../tool/verify_hardcode_register.dart).
**Declared types:** `_BehavioralConstantVisitor`.
**Direct test references:** [test/tool/hardcode_verifier_test.dart](../../test/tool/hardcode_verifier_test.dart).

### `tool/verify_native_asset_manifest.dart`

Code-asset manifest identity/path/dependency expectations; distinguishes packaged assets from unrelated host binaries.

**Source:** [tool/verify_native_asset_manifest.dart](../../tool/verify_native_asset_manifest.dart).
**Direct test references:** [test/native_asset_manifest_test.dart](../../test/native_asset_manifest_test.dart).

### `tool/verify_runtime_fault_modes.dart`

Builds/checks fault-enabled versus production native command availability; prevents test faults leaking into shipping code.

**Source:** [tool/verify_runtime_fault_modes.dart](../../tool/verify_runtime_fault_modes.dart).

### `tool/verify_toolchain_policy.dart`

Validates source build declarations and wrapper authority against policy; fails before arbitrary dependency/build changes.

**Source:** [tool/verify_toolchain_policy.dart](../../tool/verify_toolchain_policy.dart).
**Direct test references:** [test/tool/toolchain_policy_test.dart](../../test/tool/toolchain_policy_test.dart).

### `tool/verify_windows_bundle.ps1`

PE architecture, library dependencies, exports, signing/payload inspection; packaging verification rather than inference performance evidence.

**Source:** [tool/verify_windows_bundle.ps1](../../tool/verify_windows_bundle.ps1).

## Windows runner and build

### `windows/CMakeLists.txt`

Windows application/native asset install build; assembles the portable Flutter runner and dependencies.

**Source:** [windows/CMakeLists.txt](../../windows/CMakeLists.txt).

### `windows/flutter/CMakeLists.txt`

Flutter engine/generated build integration; generated configuration is supplied by Flutter tooling.

**Source:** [windows/flutter/CMakeLists.txt](../../windows/flutter/CMakeLists.txt).

### `windows/flutter/generated_plugin_registrant.cc`

Generated Windows plugin registration implementation; regenerate rather than inventing manual plugin initialization.

**Source:** [windows/flutter/generated_plugin_registrant.cc](../../windows/flutter/generated_plugin_registrant.cc).

### `windows/flutter/generated_plugin_registrant.h`

Generated plugin registration declaration; paired with the generated implementation.

**Source:** [windows/flutter/generated_plugin_registrant.h](../../windows/flutter/generated_plugin_registrant.h).

### `windows/flutter/generated_plugins.cmake`

Generated plugin/native library CMake registration; describes resolved platform dependencies.

**Source:** [windows/flutter/generated_plugins.cmake](../../windows/flutter/generated_plugins.cmake).

### `windows/runner/CMakeLists.txt`

Win32 runner target and resources; builds the executable hosting Flutter.

**Source:** [windows/runner/CMakeLists.txt](../../windows/runner/CMakeLists.txt).

### `windows/runner/Runner.rc`

Windows executable icon/version/metadata resources; packaging identity rather than application state.

**Source:** [windows/runner/Runner.rc](../../windows/runner/Runner.rc).

### `windows/runner/flutter_window.cpp`

Flutter controller creation, plugin/channel registration and Windows telemetry; desktop OS adapter.

**Source:** [windows/runner/flutter_window.cpp](../../windows/runner/flutter_window.cpp).

### `windows/runner/flutter_window.h`

Flutter window/controller/channel ownership declarations; scopes native runner resources.

**Source:** [windows/runner/flutter_window.h](../../windows/runner/flutter_window.h).
**Declared types:** `FlutterWindow`.

### `windows/runner/main.cpp`

Windows executable entry point; initializes the runner/message loop and Dart project.

**Source:** [windows/runner/main.cpp](../../windows/runner/main.cpp).

### `windows/runner/resource.h`

Windows resource identifiers; joins icon/version resources to the runner.

**Source:** [windows/runner/resource.h](../../windows/runner/resource.h).

### `windows/runner/runner.exe.manifest`

Windows process/DPI/compatibility declaration; OS loader/UI behaviour for the executable.

**Source:** [windows/runner/runner.exe.manifest](../../windows/runner/runner.exe.manifest).

### `windows/runner/utils.cpp`

Runner command-line/console/UTF conversion helpers; platform glue shared by native entry/window code.

**Source:** [windows/runner/utils.cpp](../../windows/runner/utils.cpp).

### `windows/runner/utils.h`

Declarations for runner platform helpers; keeps platform-specific utility interfaces together.

**Source:** [windows/runner/utils.h](../../windows/runner/utils.h).

### `windows/runner/win32_window.cpp`

Win32 creation, sizing, DPI and message handling base; hosts the Flutter window surface.

**Source:** [windows/runner/win32_window.cpp](../../windows/runner/win32_window.cpp).
**Declared types:** `WindowClassRegistrar`.

### `windows/runner/win32_window.h`

Win32 window lifecycle and callback declarations; base ownership boundary for the runner.

**Source:** [windows/runner/win32_window.h](../../windows/runner/win32_window.h).
**Declared types:** `Win32Window`.

## Resource and generated-file families

| Family | Use and reason |
|---|---|
| `assets/brand`, `assets/icons`, launcher mipmaps and Windows ICO | Brand source/rendered platform icons; resolution variants are packaging assets, not separate inference modules. |
| `assets/store_screenshots` | Declared image assets; not proof of a tested release. |
| Android manifests, styles, backup/data-extraction/network XML | OS permissions, splash/theme, backup restrictions and HTTPS policy; inspect merged release manifests. |
| Flutter-generated platform registrants/CMake | Resolved plugin wiring; regeneration authority is Flutter, not manual editing. |
| `*.g.dart` and use mappings | Generated native declarations/metadata; preserve the header/source provenance. |
| Lockfiles, wrappers, licences and notices | Dependency/build identity and redistribution obligations; not user runtime data. |

Every individual tracked path and its SHA-256 is retained in the source inventory. No model weights, databases or private phone captures are required to use this handbook.
