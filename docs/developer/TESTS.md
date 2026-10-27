# Test and support map

Source: `810e58af87ce43b6c9f9c85ca2a9dfb7b7583368`. This lists test/support files and declared cases where a lightweight source scan can recover literal names. It does **not** report execution, authoritative coverage, skip status or a physical PASS. Parameterized/dynamic case names may not be recoverable from a literal scan.

Use product-specific immutable-model gates for acceptance; generic vendored tests/capabilities are not automatically supported app features. Test helpers/fixtures can have no declared cases.

## Android instrumentation

### [android/app/src/androidTest/java/com/vitalis/vitalis_app/ChatExportFixtureTest.java](../../android/app/src/androidTest/java/com/vitalis/vitalis_app/ChatExportFixtureTest.java)

Declared examples: `seedLongHistory`.

### [android/app/src/androidTest/java/com/vitalis/vitalis_app/transfer/TransferRuntimeInstrumentationTest.java](../../android/app/src/androidTest/java/com/vitalis/vitalis_app/transfer/TransferRuntimeInstrumentationTest.java)

Declared examples: `manifestSurvivesStoreReconstructionAndSelectsRecovery`; `pauseCancelAndSystemStopHaveDistinctSchedulerSemantics`; `foregroundNotificationCanBeCreatedFromPersistedState`.

### [android/app/src/androidTest/java/com/vitalis/vitalis_app/transfer/TransferStopWorkerInstrumentationTest.java](../../android/app/src/androidTest/java/com/vitalis/vitalis_app/transfer/TransferStopWorkerInstrumentationTest.java)

Declared examples: `pauseCannotAcknowledgeUntilWriterLeaseIsReleased`; `acknowledgedCancelRemovesOnlyItsOwnPartial`; `staleStopCannotChangeResumedGeneration`.

## Android JVM

### [android/app/src/test/java/com/vitalis/vitalis_app/LauncherIconTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/LauncherIconTest.java)

Declared examples: `manifestLauncherRendersAdaptiveLayersAtEveryShippedDensity`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferActionReceiverTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferActionReceiverTest.java)

Declared examples: `invalidActionsNeverEnterAsyncHandoff`; `missingBroadcastResultCannotClaimDurableStop`; `unavailableSchedulerFinishesBroadcastWithFailureNotStopAcknowledgement`; `rejectedHandoffFinishesBroadcastWithRedactedDiagnostic`; `unstartedHandoffDeadlineFinishesWithoutClaimingStop`; `pauseCallbackDoesNotWaitForManifestOwner`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferChannelTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferChannelTest.java)

Declared examples: `channelPauseRecoveryAndCancelPreserveDurableOwnership`; `unknownMethodDoesNotMutateTransferRecords`; `pendingStopReplyIsTypedWithoutResumingTheWriter`; `errorReplyDoesNotEchoCorruptManifestContents`; `manifestChannelUsesBackgroundQueueAndReturnsActualRecord`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferControllerValidationTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferControllerValidationTest.java)

Declared examples: `enqueueAndResumeRetainIdentityAndActualPartialBytes`; `malformedRequestsCannotCreateManifestOrChangePartial`; `enqueueCannotResumeAnUnacknowledgedStop`; `acknowledgedPauseCanBeEscalatedToCancellation`; `latePauseCannotDowngradePendingOrAcknowledgedCancellation`; `acceptsCanonicalQueryFreeUrlGeneratedByFlutterPolicy`; `rejectsInitialUrlQuerySoCredentialsCannotEnterManifest`; `rejectsPartialPathOutsideApplicationStorage`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferEngineTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferEngineTest.java)

Declared examples: `recoveryRejectsAnotherJobWithoutChangingStopStateOrPartial`; `failedExplicitRecoveryPreservesPartialAndRuntimeQuarantine`; `explicitChannelRecoveryClosesQuarantinedConnectionBeforeCancelCleanup`; `pauseAcknowledgementWaitsForEngineWriterLeaseRelease`; `pauseEscalatesToCancelAtEngineWriterReleaseBoundary`; `quarantinedTransferDoesNotInterruptFormerWorkerDoingUnrelatedWork`; `cancellationAfterFailedCloseKeepsPartialAndAcknowledgementPending`; `failedConnectionCleanupDoesNotOpenAnotherTransport`; `repeatedNativeCancelDoesNotInterruptCleanupOrAcknowledgeEarly`; `nativePauseEscalatesToCancelDuringCleanupWithoutAnotherInterrupt`; `recoveryCannotReplaceActiveCleanupOwner`; `nativeCancelWakesAnUninterruptibleReadBeforeAcknowledgingCleanup`. Additional declared cases are in the linked source.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferJobServiceTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferJobServiceTest.java)

Declared examples: `staleStopCallbackCannotStopResumedOwner`; `foreignTransferStopCallbackCannotStopOwner`; `destructionDuringPublicationSettlesUnstartedOwnerWithoutEngine`; `staleServiceAdmissionDoesNotConstructEngine`; `publicationReentryCannotAcquireUnstartedOwner`; `lateNotificationFailureCannotFailResumedGeneration`; `destructionDuringPausedCleanupRetainsOwnerAndStopIntent`; `userJobStopWakesUninterruptibleReadAndAcknowledgesPause`; `systemJobStopWakesUninterruptibleReadAndKeepsResumablePartial`; `serviceDestructionStopsOwnedReadAndKeepsResumablePartial`; `rejectedDuplicateDoesNotReplaceOwnersNotification`; `stopDuringBlockedInitializationReturnsBeforeStorageAndCannotFinishLate`. Additional declared cases are in the linked source.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferManifestStoreTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferManifestStoreTest.java)

Declared examples: `listingIgnoresStagingFilesAndRetainsOnlyDurableRecords`; `missingUpdateCannotCreateARecordOrInvokeItsTransition`; `transitionWithInventedRevisionCannotReplaceDurableData`; `emptyOrOversizedManifestFailsWithoutReplacingItsBytes`; `unavailableStorageDirectoryFailsWithoutChangingTheBlockingFile`; `mismatchedManifestIdentityCannotDeleteAnotherPartial`; `atomicUpdatesAcrossInstancesKeepAllProgressAndRevisions`; `legacyManifestWithoutStateRevisionUpgradesWithoutChangingIdentity`; `separateProcessLeaseBlocksManifestUpdateUntilReleased`; `staleProgressCannotReplaceAnotherStoreStopRequest`; `identityCollisionCannotReplaceExistingManifest`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferManifestTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferManifestTest.java)

Declared examples: `restartRecoveryUsesTheDurableValidationAndInstallationBoundary`; `missingLegacyStopAcknowledgementRemainsUnconfirmed`; `malformedStateRevisionsCannotMasqueradeAsLegacyRecords`; `jsonRoundTripPreservesImmutableIdentityAndProgress`; `recoveryActionAndRescheduleAreStateSpecific`; `userStopRequiresExplicitAcknowledgement`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferNotificationsTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferNotificationsTest.java)

Declared examples: `notificationTapOpensAppWithoutTransferControlSideEffects`; `notificationGlyphsHaveTransparentBackgrounds`; `identitiesRemainStableAfterStoreReopeningInReverseOrder`; `concurrentAllocatorsRetainDistinctAndStableIdentities`; `visibleLegacyNotificationCannotBeReusedForNewTransfer`; `corruptIdentityStoreFailsWithoutDeletingItsEvidence`; `collidingTransfersKeepTheirOwnNotificationControls`; `collidingTransfersCannotReplaceEachOthersVisibleNotification`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferRunControlTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferRunControlTest.java)

Declared examples: `oldGenerationCannotSignalReplacementControl`; `foreignOwnerCannotStopActiveRun`; `rejectedDuplicateAcquisitionLeavesOwnerUntouched`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferSchedulerTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferSchedulerTest.java)

Declared examples: `api28To33UsesUniqueConstrainedWorkManagerTransfer`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferStopWorkerTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferStopWorkerTest.java)

Declared examples: `cancelThenLatePauseCannotReviveCancelledTransfer`; `oldCommandCannotCancelResumedTransfer`; `resumedSchedulerWorkSurvivesOlderStopSignal`; `resumedNotificationDoesNotRewriteOlderActionIdentity`; `staleUserAndSystemProjectionsPreserveResumedManifest`; `staleEngineHandoffDoesNotOpenReplacementTransport`; `cancelRetriesWithoutDeletingOwnedPartial`; `missingOrUnsafeIdentityFailsWithoutChangingOwnedData`; `corruptManifestRequiresRetryWithoutDeletingOrReplacingData`; `escapedPartialFailsWithoutDeletingEitherFile`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferStoragePreflightTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferStoragePreflightTest.java)

Declared examples: `backgroundQueryUsesApplicationStorageVolume`; `zeroIsKnownButNegativeIsUnknown`; `mainThreadIsRejectedWithoutQueryingStorage`; `storageFailuresAreRedactedUnknownResults`; `unsupportedCallsDoNotQueryStorage`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferUidtSchedulerTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferUidtSchedulerTest.java)

Declared examples: `olderGenerationCannotCancelReplacementUidtJob`; `distinctTransferIdsCannotReplaceEachOthersScheduledJob`; `api34SchedulesUserInitiatedNetworkJob`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferWorkerTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferWorkerTest.java)

Declared examples: `startupFailuresPersistTypedCodesWithoutChangingPartialBytes`; `latePromotionFailureDoesNotFailResumedTransfer`; `staleWorkerDoesNotPromoteOrStartReplacementTransfer`; `oldWorkerStopProjectionCannotPauseResumedTransfer`; `stopDuringForegroundPromotionDoesNotStartEngine`; `systemStopWakesOwnedReadAndPreservesResumableData`; `missingTransferIdentityFailsWithoutForegroundPromotion`; `absentManifestFailsWithoutCreatingTransferState`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferWriterLeaseTest.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/TransferWriterLeaseTest.java)

Declared examples: `rejectedOverlappingOsLeaseDoesNotPoisonLaterOwnership`; `parentOwnershipRejectsSeparateProcessThenAllowsItAfterClose`; `childOwnershipSurvivesRejectedParentAcquisitionUntilChildStops`.

### [android/app/src/test/java/com/vitalis/vitalis_app/transfer/WriterLeaseProcessProbe.java](../../android/app/src/test/java/com/vitalis/vitalis_app/transfer/WriterLeaseProcessProbe.java)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

## integration_test

### [integration_test/app_test.dart](../../integration_test/app_test.dart)

Declared examples: `Phase 1 - Setup Screen`; `1.1 Setup UI renders with welcome title`; `1.2 Download model button exists`; `1.7 Download blocked by hardware check`; `Phase 8 - Settings Screen`; `8.1 Dark mode toggle`; `8.2 Privacy mode toggle`; `8.3 What is logged expansion`; `8.4 Clear logs button`; `8.6 Model info displayed`; `8.7-8.10 Temperature/TopP/TopK/MaxTokens sliders`; `8.11 Redownload model button`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/constants/app_strings.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_download_service.dart`, `package:vitalis_app/services/model_downloader.dart`, `package:vitalis_app/utils/validation_exception.dart`, `package:vitalis_app/utils/app_logger.dart`, `package:vitalis_app/utils/log_sanitizer.dart`, `package:vitalis_app/utils/memory_monitor.dart`, `package:vitalis_app/utils/async_mutex.dart`, `package:vitalis_app/utils/stream_transformers.dart`

### [integration_test/helpers.dart](../../integration_test/helpers.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.
Local targets: `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/providers/theme_provider.dart`, `package:vitalis_app/services/model_download_service.dart`, `package:vitalis_app/services/model_downloader.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/app_router.dart`

## test

### [test/database/installation_journal_test.dart](../../test/database/installation_journal_test.dart)

Declared examples: `fresh database provides the version-8 installation journal`; `failed version-7 migration rolls back without touching saved data`; `version-7 upgrade preserves saved content and installed identity`.
Local targets: `package:vitalis_app/constants/app_constants.dart`, `package:vitalis_app/database/database_helper.dart`

### [test/database/model_installation_journal_test.dart](../../test/database/model_installation_journal_test.dart)

Declared examples: `intent persists across reopening without changing installed model`; `duplicate owners and stale state revisions are rejected`; `wrong hash or size cannot validate or activate a shard set`; `complete projection atomically installs all shards and retains hash authority`; `stale installed identity blocks projection`; `artifact-write failure rolls back model and journal projection`; `missing shard records cannot be mistaken for a complete set`; `stale artifact changes block projection even when model row is unchanged`.
Local targets: `package:vitalis_app/constants/app_constants.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/database/model_installation_journal.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_installation.dart`

### [test/database/windows_database_test.dart](../../test/database/windows_database_test.dart)

Declared examples: `non-Windows initialization leaves the mobile factory untouched`; `Windows persistence uses support storage and survives reopening`.
Local targets: `package:vitalis_app/database/windows_database.dart`

### [test/database_test.dart](../../test/database_test.dart)

Declared examples: `DatabaseHelper`; `failed or missing persona update cannot publish a committed change`; `committed persona ${deleting ? `; `failed persona deletion preserves its chat assignment`; `failed persona replacement preserves the previous mapping`; `note and persona providers persist edits and reload before deletion`; `model-only assignment preserves settings and rejects missing chats`; `insert and retrieve chats`; `insert and retrieve messages`; `insert and retrieve notes`; `supports complete CRUD and per-chat settings lifecycle`; `default persona is created`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/constants/app_constants.dart`, `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/services/persistent_hub_search_cache.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/generation_provider.dart`

### [test/model_download_test.dart](../../test/model_download_test.dart)

Declared examples: `ModelDownloadService`; `initial state is idle`; `cancel resets state`; `reset clears completed state`; `isModelDownloaded returns false by default`.
Local targets: `package:vitalis_app/services/model_download_service.dart`, `package:vitalis_app/services/model_downloader.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`

### [test/models/device_safety_policy_test.dart](../../test/models/device_safety_policy_test.dart)

Declared examples: `charging bypasses only the low-battery rule`; `unknown telemetry is represented without fake safety values`; `severe thermal and critical memory start cooldown`; `cooldown uses the injected evaluation time`; `unplugged low battery is blocked but unknown charging is not guessed`; `critical memory recognizes platform and trim signals`; `severe thermal and memory return distinct safety reasons`; `expired cooldown does not block`.
Local targets: `package:vitalis_app/models/device_safety_policy.dart`

### [test/models/generation_setting_test.dart](../../test/models/generation_setting_test.dart)

Declared examples: `${entry.key.name} accepts native-compatible $value`; `${entry.key.name} rejects unsupported $value without changing a record`; `repairing one field preserves unrelated stored settings`; `output presets derive from the single default and do not limit custom output`.
Local targets: `package:vitalis_app/models/generation_setting.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/model_defaults.dart`

### [test/models/hub_artifact_uri_policy_test.dart](../../test/models/hub_artifact_uri_policy_test.dart)

Declared examples: `produces the canonical query-free immutable transfer URL`.
Local targets: `package:vitalis_app/models/model_library_policy.dart`

### [test/models/message_test.dart](../../test/models/message_test.dart)

Declared examples: `Message`; `fromMap and toMap round trip`; `copyWith creates a copy with overridden fields`.
Local targets: `package:vitalis_app/models/message.dart`

### [test/models/model_download_job_test.dart](../../test/models/model_download_job_test.dart)

Declared examples: `download job round trips persistent state and progress`; `clearError removes the previous failure code`.
Local targets: `package:vitalis_app/models/model_download_job.dart`

### [test/models/model_settings_test.dart](../../test/models/model_settings_test.dart)

Declared examples: `ModelSettings`; `serialization round trip`; `copyWith preserves unchanged values`; `JSON string round trip`; `default values`; `unknown persisted enum values fall back safely`.
Local targets: `package:vitalis_app/models/model_settings.dart`

### [test/models/runtime_profile_test.dart](../../test/models/runtime_profile_test.dart)

Declared examples: `automatic profile keeps one CPU free and remains bounded`; `advanced overrides are clamped and unavailable GPU stays off`; `compatibility probe is conservative when telemetry is unknown`; `compatibility probe honors model and memory limits`.
Local targets: `package:vitalis_app/constants/app_constants.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`

### [test/models/thinking_capability_test.dart](../../test/models/thinking_capability_test.dart)

Declared examples: `persisted thinking flag cannot authorize an unverified template`.
Local targets: `package:vitalis_app/models/model_descriptor.dart`

### [test/native_asset_manifest_test.dart](../../test/native_asset_manifest_test.dart)

Declared examples: `accepts canonical packaged binding and backend mappings`; `rejects doubled IDs even if the canonical mapping also exists`; `rejects absent primary binding`; `rejects wrong library and non-bundled resolution`; `rejects missing backend and unsupported schema`.
Local targets: `../tool/verify_native_asset_manifest.dart`

### [test/native_asset_registration_test.dart](../../test/native_asset_registration_test.dart)

Declared examples: `primary asset resolves the generated binding canonical ID`; `backend assets have exactly one package prefix`.
Local targets: `../third_party/llm_llamacpp/hook/build.dart`

### [test/provider_test.dart](../../test/provider_test.dart)

Declared examples: `pending completion preserves its chat without stale publication (dispose: $dispose)`; `ChatProvider`; `initial state is empty`; `createChat adds a new chat`; `sendMessage with no current chat does nothing`; `default settings have correct values`; `loads selects renames and deletes persisted chats`; `persists settings persona and multiple note attachments`; `validates message title and system prompt storage bounds`; `sends retries regenerates and pages older messages`; `local updates and no-chat attachment guards are stable`; `generation callbacks persist completion and surface errors`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`

### [test/providers/chat_deletion_persistence_test.dart](../../test/providers/chat_deletion_persistence_test.dart)

Declared examples: `out-of-order saves retain each response render identity`; `saved response keeps its original render identity across delayed persistence`; `a pending deletion rejects newly submitted settings writes`; `an admitted response finishes saving before its chat is deleted`; `deletion waits for already admitted settings persistence`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/generation_provider.dart`

### [test/providers/chat_deletion_test.dart](../../test/providers/chat_deletion_test.dart)

Declared examples: `zero deleted rows preserves the selected chat and reports failure`; `failed refresh reports that deletion already committed`; `acknowledged deletion selects the remaining saved chat`; `preparation must acknowledge Stop before deletion storage`; `disposal during Stop prevents new deletion storage`; `duplicate deletion shares the admitted writer through shutdown`; `late deletion failure remains observable after disposal`; `storage failure preserves the selected chat`; `disposed provider rejects deletion before storage`; `close drains an admitted deletion without post-disposal refresh`; `storage deletion failure propagates a redacted error`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/generation_provider.dart`

### [test/providers/chat_history_status_test.dart](../../test/providers/chat_history_status_test.dart)

Declared examples: `history failures clear independently of unrelated chat errors on retry`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/providers/chat_provider.dart`

### [test/providers/chat_logging_privacy_test.dart](../../test/providers/chat_logging_privacy_test.dart)

Declared examples: `chat $operation excludes exception text privacy=$privacy`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/persistence_policy.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/utils/app_logger.dart`

### [test/providers/chat_selection_persona_test.dart](../../test/providers/chat_selection_persona_test.dart)

Declared examples: `committed persona change supersedes a stale selection read delete=$deleting`; `disposed chat rejects late committed persona publication`; `reopening a chat waits for its pending persona commit`; `chat deletion waits for its admitted persona save`; `failed persona save permits an explicit successful retry`; `persona writes commit in admitted order`; `old-chat persona completion cannot change the new view`; `provider close drains persona save without late publication`; `failed persona replacement preserves committed selection`; `failed persona removal retains committed visible selection`; `pending persona write does not publish uncommitted selection`; `new chat save returns its own identity without replacing a newer selection`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/startup_access_guard.dart`, `package:vitalis_app/services/selected_model_readiness.dart`, `package:vitalis_app/providers/generation_provider.dart`

### [test/providers/chat_settings_persistence_test.dart](../../test/providers/chat_settings_persistence_test.dart)

Declared examples: `overlapping admitted settings writes persist in submission order`; `oversized system prompt is rejected before storage or publication`; `failed settings write is reported and preserves committed settings`; `settings publish only after persistence acknowledges success`; `provider close drains an admitted settings write`; `a completed old-chat settings write cannot replace a new selection`; `failed preview persistence restores the committed settings`; `zero updated rows cannot be reported as a successful settings save`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/constants/app_constants.dart`

### [test/providers/generation_provider_test.dart](../../test/providers/generation_provider_test.dart)

Declared examples: `painted response timing survives completion and rejects old or stopped work`; `generation uses the output allowance left by its context plan`; `readiness signal shares Stop and detaches during pending disposal`; `readiness cancellation failure retains recovery and rejects the next request`; `active readiness revocation suppresses late tokens and retains Stop until acknowledgement`; `revocation at $boundary boundary prevents native generation`; `revoked startup permission stops preparation after tuning acknowledgement`; `read-only startup rejects direct preparation and generation before warmup`; `provider close expiry retains pending preparation until recovery`; `provider close drains preparation and rejects new work immediately`; `provider close retains unacknowledged controller cleanup`; `provider close waits for both controller and preparation actors`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/startup_access_guard.dart`

### [test/providers/generation_recovery_test.dart](../../test/providers/generation_recovery_test.dart)

Declared examples: `healthy provider cannot invoke failed-owner recovery`; `provider recovery deadline retains the unfinished owner`; `late recovery cannot clear a newer expired close`; `shared recovery preserves failure then permits a new request after acknowledgement`; `claimed recovery with retained controller failure remains unavailable`; `recovery drains preparation before clearing failed Stop`; `close during recovery waits for the same attempt and never revives disposal`; `adapter failure retains quarantine without exposing its details`; `failed recovery also fails a concurrent close`; `recovery after failed close does not revive a disposed provider`; `failure without an identifiable owner is not recovery proof`; `model-service cleanup must also acknowledge recovery`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`

### [test/providers/health_provider_test.dart](../../test/providers/health_provider_test.dart)

Declared examples: `HealthProvider`; `initial state reflects sentinel values`; `unsafe sentinel reflects low battery and no connectivity`; `dispose stops timer`; `rssMb is non-negative after construction`.
Local targets: `package:vitalis_app/providers/health_provider.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`

### [test/providers/initial_model_chat_test.dart](../../test/providers/initial_model_chat_test.dart)

Declared examples: `explicit verified model starts the first chat from read-only recovery`; `new chat retains the explicitly selected model across reload`; `new chat reuses established readiness but never bypasses invalidation`; `first model chat requires established safety readiness`; `failed settings persistence rolls back the new chat and readiness`; `recovery creates a new chat without changing saved chat settings`; `duplicate first-model actions cannot create two chats`; `disposal during verification cannot create a chat`; `unverified model cannot unlock recovery mutations`; `revoked commit authorization rolls back both new records`.
Local targets: `package:vitalis_app/constants/app_constants.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/selected_model_readiness.dart`, `package:vitalis_app/services/startup_access_guard.dart`

### [test/providers/model_library_inspection_test.dart](../../test/providers/model_library_inspection_test.dart)

Declared examples: `inspection ${fails ? `; `empty artifact set remains unknown without requesting metadata`.
Local targets: `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/models/model_download_job.dart`, `package:vitalis_app/providers/model_library_provider.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/model_download_manager.dart`, `package:vitalis_app/services/model_hub_client.dart`, `package:vitalis_app/services/remote_gguf_inspector.dart`

### [test/providers/model_library_recovery_test.dart](../../test/providers/model_library_recovery_test.dart)

Declared examples: `failed import clears busy state and permits retry`; `import progress remains visible and prevents a second picker`; `starting the first model chat opens the conversation`; `concurrent import is rejected before opening a second picker`; `late restoration snapshot preserves newer durable progress`; `failed completed-job refresh retains models and reports a redacted error`; `persisted transfer updates expose Pause before completion`; `background completion refreshes models without late disposed publication $dispose`; `late installed snapshot cannot replace a newer completed-job refresh`; `Model Library observes initialization failures (leave: $leaveScreen)`; `library initialization shares pending work and permits retry ($fail)`; `disposed library completion starts no refresh ($action)`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/screens/model_library_screen.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/app_router.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/providers/model_library_provider.dart`, `package:vitalis_app/services/model_recovery_controller.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/model_download_manager.dart`, `package:vitalis_app/services/model_hub_client.dart`, `package:vitalis_app/models/model_download_job.dart`, `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/services/model_update_service.dart`, `package:vitalis_app/models/model_verification_phase.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/selected_model_readiness.dart`

### [test/providers/model_library_search_test.dart](../../test/providers/model_library_search_test.dart)

Declared examples: `pagination deduplicates ${cached ? `; `fresh cache serves results without a Hub request`; `offline search ${cached ? `; `empty Hub results settle loading without an error`; `cache persistence failure does not discard successful Hub results`; `late cache write cannot replace newer query results`; `old pagination failure cannot ${disposed ? `; `old pagination cannot append into a newer search`.
Local targets: `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/models/model_download_job.dart`, `package:vitalis_app/providers/model_library_provider.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/model_download_manager.dart`, `package:vitalis_app/services/model_hub_client.dart`, `package:vitalis_app/services/persistent_hub_search_cache.dart`

### [test/providers/saved_content_logging_privacy_test.dart](../../test/providers/saved_content_logging_privacy_test.dart)

Declared examples: `$kind $operation excludes error payload with privacy=$privacy`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/utils/app_logger.dart`

### [test/providers/startup_access_guard_test.dart](../../test/providers/startup_access_guard_test.dart)

Declared examples: `model switching rejects unavailable prerequisites and disposed owners`; `read-only chat rejects mutations before any persistence or generation`; `guard reads current permission rather than remembered readiness`; `read-only note/persona browsing reaches reads but no writes`; `disposed providers reject new work without touching persistence`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/services/startup_access_guard.dart`

### [test/providers/theme_lifecycle_test.dart](../../test/providers/theme_lifecycle_test.dart)

Declared examples: `theme load failure retains fallback and a later save can recover`; `queued toggle uses committed state after preceding failed save`; `two admitted theme toggles preserve their ordered intent`; `theme publishes only after storage acknowledges the write`; `failed theme acknowledgement preserves committed state`; `theme writer can recover after a redacted storage failure`; `an admitted theme save settles without publishing after disposal`; `theme disposal suppresses the pending initial preference notification`; `disposed theme rejects new writes with a typed lifecycle error`.
Local targets: `package:vitalis_app/providers/theme_provider.dart`

### [test/services/android_durable_transfer_adapter_test.dart](../../test/services/android_durable_transfer_adapter_test.dart)

Declared examples: `active $reason interrupts stalled $stalledMethod without late progress`; `acknowledgement at the elapsed deadline cannot report success`; `active stop deadline rejects a stalled acknowledgement and late output`; `stop expiry cancels the outstanding polling timer`; `stop deadline covers stalled native $stalledMethod and rejects late success`; `terminal native failure ends stop wait without another poll`; `malformed inventory cannot stand for absence of native writers`; `restart control stops every owned shard before polling acknowledgements`; `restart control rejects an absent or foreign acknowledgement: $wrong`; `restart control rejects duplicate native identities before sending stop`; `enqueues immutable transfer and reports native completion`; `projects paused native state as acknowledged cancellation`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/models/model_download_job.dart`, `package:vitalis_app/services/model_download_manager.dart`, `package:vitalis_app/services/native_transfer_stop.dart`

### [test/services/application_error_reporter_test.dart](../../test/services/application_error_reporter_test.dart)

Declared examples: `$boundary diagnostics exclude payload privacy=$privacy`.
Local targets: `package:vitalis_app/services/application_error_reporter.dart`, `package:vitalis_app/utils/app_logger.dart`

### [test/services/application_private_directory_test.dart](../../test/services/application_private_directory_test.dart)

Declared examples: `private storage selects the correct platform adapter: $windows`.
Local targets: `package:vitalis_app/services/application_private_directory.dart`

### [test/services/bundled_install_adapter_test.dart](../../test/services/bundled_install_adapter_test.dart)

Declared examples: `bundled adapter requires a configured installation authority`; `bundled adapter rejects changed manifest $field before authority work`; `bundled adapter waits for authoritative installation acknowledgement`; `bundled adapter propagates rejected authoritative persistence`; `untrusted synthetic GGUF cannot acquire bundled identity`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/services/model_downloader.dart`, `package:vitalis_app/utils/app_logger.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test/services/chat_logging_privacy_test.dart](../../test/services/chat_logging_privacy_test.dart)

Declared examples: `verbose rejected generation never logs private message content`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [test/services/chat_state_controller_test.dart](../../test/services/chat_state_controller_test.dart)

Declared examples: `synchronous watchdog expiry retires its returned timer: $synchronousCall`; `watchdog scheduling failure retains shutdown ownership: $failure`; `lost safety observation cancels generation: $failure`; `health stream error requests acknowledged shutdown without leaking details`; `unacknowledged Stop expires without restarting native shutdown`; `disposed Stop expiry stays failed until explicit recovery`; `stalled owner recovery reuses its actor after deadline`; `native progress cannot extend the maximum request duration`; `retired watchdog callbacks cannot cancel a replacement request`; `native decode progress keeps a text-silent request alive`; `recovery callback failure cannot clear cleanup quarantine`; `healthy controller cannot invoke failed-owner recovery`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/generation_watchdog_policy.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`

### [test/services/chat_state_controller_timeout_test.dart](../../test/services/chat_state_controller_timeout_test.dart)

Declared examples: `ChatStateController timeout`; `transitions to error after timeout override`; `default watchdog leaves an idle controller unchanged`.
Local targets: `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`

### [test/services/context_planner_test.dart](../../test/services/context_planner_test.dart)

Declared examples: `large requested output remains bounded by exact available context`; `failed trailing assistant cannot resurrect an earlier user request`; `history ${barrier.role.name}/${barrier.isError} is a turn boundary`; `reduces output reservation when required input still fits`; `counts the rendered request with the runtime tokenizer adapter`; `keeps only a contiguous newest block of complete turns`; `drops notes from the end before rejecting required content`; `rejects rather than truncating system instructions or current input`.
Local targets: `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/context_planner.dart`

### [test/services/device_fit_estimator_test.dart](../../test/services/device_fit_estimator_test.dart)

Declared examples: `exactly 4B parameters is not the large-model warning boundary`; `more than 4B parameters requires a warning but is not blocked`; `insufficient storage is a hard incompatibility`.
Local targets: `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/services/device_fit_estimator.dart`

### [test/services/gguf_metadata_io_test.dart](../../test/services/gguf_metadata_io_test.dart)

Declared examples: `UTF-8 model metadata survives decoding (sync: $synchronous)`; `invalid UTF-8 metadata is rejected (sync: $synchronous)`; `large vocabulary metadata avoids per-token filesystem round trips`; `metadata strings crossing read windows retain every byte`; `declared metadata past EOF fails before allocating its payload`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [test/services/hardware_sentinel_service_test.dart](../../test/services/hardware_sentinel_service_test.dart)

Declared examples: `initial telemetry permits safe inference and download`; `charging does not clear Battery Saver protection`; `critical memory starts cooldown and blocks heavy work`; `offline connectivity blocks only downloads`; `missing device plugin remains an unknown non-fabricated state`; `dispose is idempotent`; `telemetry failures remain conservative and observable`; `charging refresh failure clears stale battery telemetry`; `periodic refresh publishes updated safety`.
Local targets: `package:vitalis_app/models/device_safety_policy.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/memory_pressure_service.dart`

### [test/services/inference_output_timing_test.dart](../../test/services/inference_output_timing_test.dart)

Declared examples: `sample and buffered emission retain separate first offsets and identity`; `cancel acknowledgement preserves timing and a new request starts empty`.
Local targets: `package:llm_llamacpp/src/inference_output_timing.dart`, `package:llm_llamacpp/src/isolate_messages.dart`

### [test/services/legacy_model_preference_migration_test.dart](../../test/services/legacy_model_preference_migration_test.dart)

Declared examples: `does nothing when no legacy model path exists`; `retains legacy preferences when the file cannot be verified`; `unrecognized content cannot claim bundled identity (hash: $recordedHash)`; `cleanup interruption reuses committed identity and preserves assignments`; `database insertion failure retains file and restart preferences`; `recorded digest mismatch preserves all legacy preferences`; `existing registry identity is protected (conflict: $conflict)`; `missing legacy file prevents startup readiness without clearing preferences`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/legacy_model_preference_migration.dart`, `package:vitalis_app/services/startup_coordinator.dart`

### [test/services/memory_pressure_service_test.dart](../../test/services/memory_pressure_service_test.dart)

Declared examples: `projects trim-memory events and critical threshold`; `ignores unrelated and malformed events`; `stream construction failure is contained`.
Local targets: `package:vitalis_app/models/device_safety_policy.dart`, `package:vitalis_app/services/memory_pressure_service.dart`

### [test/services/model_download_manager_test.dart](../../test/services/model_download_manager_test.dart)

Declared examples: `download again creates a new job after a completed model is uninstalled`; `paused progress includes bytes retained after the last poll`; `enqueue rejects gated, mismatched, incomplete, and disk-risk artifacts`; `enqueue persists immutable model, shards, and job`; `pending native stop rejection retains a hold without Dart cancellation`; `restart reconciliation retains pending native stop holds`; `cancel preserves a legacy partial with unproven ownership`; `active native stop failure preserves its partial and recovery hold`; `cancel during $phase requires its own native acknowledgement`; `restart cancellation preserves partial until native acknowledgement`; `failed native restart cancellation preserves partial and job`; `a new job never adopts an unidentified legacy partial`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_download_job.dart`, `package:vitalis_app/models/model_verification_phase.dart`, `package:vitalis_app/services/model_download_manager.dart`, `package:vitalis_app/services/model_download_staging.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/native_transfer_stop.dart`

### [test/services/model_download_service_lifecycle_test.dart](../../test/services/model_download_service_lifecycle_test.dart)

Declared examples: `download close shares shutdown and waits for writer termination`; `unexpected transport failure remains observed and cleanup settles`; `reentrant disposal at download admission prevents transport start`; `late previous download progress cannot overwrite a new request`; `cancel retains active writer admission until transport settles`; `disposed download service cannot start transport work`; `reset drain remains pending until the owned acknowledgement`; `failed reset stays observable while disposal drains settlement`; `duplicate reset callers share the owned operation`; `an admitted reset settles without notification after disposal`; `disposed download service rejects reset before transport`.
Local targets: `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_download_service.dart`, `package:vitalis_app/services/model_downloader.dart`

### [test/services/model_download_staging_test.dart](../../test/services/model_download_staging_test.dart)

Declared examples: `jobs and same-basename artifacts cannot share writable bytes`; `untrusted identity strings cannot escape the storage root`; `empty identities are rejected before creating staging paths`; `a directory cannot masquerade as a writable partial`.
Local targets: `package:vitalis_app/services/model_download_staging.dart`

### [test/services/model_downloader_test.dart](../../test/services/model_downloader_test.dart)

Declared examples: `DownloadResult`; `success factory creates success result`; `error factory creates error result`; `cancelled factory creates cancelled result`; `ModelDownloader`; `verified existing model is reused without a network request or copy headroom`; `installed model discovery reflects file presence without deleting records`; `HTTP-date Retry-After is bounded for $seconds seconds`; `permanent HTTP rejection removes only its owned partial`; `complete but undersized HTTP body (${body.length} bytes) cannot activate`; `failed new activation rolls back to its valid partial when unowned`; `final installation cannot move into a destination owned by native work`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/model_downloader.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`

### [test/services/model_hub_client_test.dart](../../test/services/model_hub_client_test.dart)

Declared examples: `search returns only public GGUF models with immutable identity`; `search sends an explicit publisher filter`; `repository resolves the latest immutable public revision`; `artifact resolver groups complete split GGUF shards`; `artifact resolver rejects incomplete or duplicate split indices $indices`; `artifact resolver rejects gated repositories`.
Local targets: `package:vitalis_app/services/model_hub_client.dart`

### [test/services/model_installation_promoter_test.dart](../../test/services/model_installation_promoter_test.dart)

Declared examples: `production native file lease blocks a live reader then permits promotion`; `unvalidated operation cannot start file promotion`; `validates and promotes all files before atomic activation`; `restart recovers rename before journal acknowledgement`; `different existing destination is preserved with all staging files`; `missing or changed staging cannot activate partial sets`; `busy native lease does not move files or advance the journal`; `stop after first move retains recoverable projection without activation`; `outside-root journal path is rejected before acquiring a lease`; `path changes while acquiring ownership cannot escape the lease`; `changed same-size bytes cannot reuse previous validation`; `filesystem errors expose no private path and retain recovery intent`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/native_runtime_bridge.dart`, `package:llm_llamacpp/src/loader/loader.dart`, `package:vitalis_app/constants/app_constants.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/database/model_installation_journal.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_installation.dart`, `package:vitalis_app/services/model_installation_promoter.dart`

### [test/services/model_recovery_controller_test.dart](../../test/services/model_recovery_controller_test.dart)

Declared examples: `phase reporter rejects late events from an earlier recovery attempt`; `recovery rejects a different model identity instead of reporting success`; `synchronous failure releases admission for an explicit retry`; `disposal before scheduled verification prevents new underlying work`; `duplicate recovery shares verification and does not activate`; `classifies ${fault.runtimeType} without changing model identity`; `disposal rejects admission but retains pending verification completion`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/services/model_recovery_controller.dart`, `package:vitalis_app/models/model_verification_phase.dart`, `package:vitalis_app/models/model_storage_error.dart`

### [test/services/model_recovery_projection_test.dart](../../test/services/model_recovery_projection_test.dart)

Declared examples: `recovery projection updates both paths without replacing artifact identity`; `stale recovery cannot overwrite changed model $field`; `stale recovery rejects changed artifact ${change.key}`; `artifact write failure rolls back the preceding model projection`; `hash-verified legacy identity may acquire previously unknown byte size`.
Local targets: `package:vitalis_app/database/database_helper.dart`

### [test/services/model_registry_service_test.dart](../../test/services/model_registry_service_test.dart)

Declared examples: `unsafe $reason rejects native verification without changing the model`; `bundled installation rejects non-publisher bytes without changing saved identity`; `disposed bundled installer rejects before file or registry work`; `bundled installation cannot reinterpret a saved different-content identity`; `missing safety authority blocks a default native probe without changing records`; `probe safety $stop retains preparation until shutdown acknowledges`; `unsafe probe decoding preserves records and retains failed cleanup ($cleanupFails)`; `missing-file recovery preserves identity only for exact bytes`; `replacement rejects an oversized stream before accepting later chunks`; `registered single-file Hub model can restore its exact artifact`; `restoration owns the picker until disposal drains it`; `single-file picker cannot restore a registered shard set`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/models/model_verification_phase.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`, `package:vitalis_app/services/runtime_profile_store.dart`

### [test/services/model_registry_uninstall_test.dart](../../test/services/model_registry_uninstall_test.dart)

Declared examples: `uninstall deletes only the selected controlled file and retains row`; `uninstall refuses a registered path outside controlled storage`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/runtime_profile_store.dart`

### [test/services/model_shard_restorer_lifecycle_test.dart](../../test/services/model_shard_restorer_lifecycle_test.dart)

Declared examples: `disposal retains pending selection and rejects its late completion`; `competing registry recovery cannot disturb the admitted picker owner`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/services/model_registry_service.dart`, `../support/shard_restore_fixture.dart`

### [test/services/model_shard_restorer_test.dart](../../test/services/model_shard_restorer_test.dart)

Declared examples: `a durable download owner rejects restoration before the picker opens`; `failed native validation retains staged bytes and retry does not repick`; `registry restores complete split bytes in arbitrary selection order`; `legacy one-based records normalize only after complete validated recovery`; `cancelled selection and incomplete sets leave records untouched`; `wrong bytes retain valid partial staging and correct retry succeeds`; `native close acknowledgement precedes installation projection`; `failed projection resumes after reopen without repicking or reprobe`; `present primary does not prevent recovery of missing secondary shard`.
Local targets: `package:vitalis_app/database/model_installation_journal.dart`, `package:vitalis_app/models/model_installation.dart`, `package:vitalis_app/services/model_registry_service.dart`, `../support/shard_restore_fixture.dart`

### [test/services/model_startup_inspector_test.dart](../../test/services/model_startup_inspector_test.dart)

Declared examples: `verified selected record matches streamed bytes without mutation`; `missing selected identity never selects another model`; `missing file is distinguished from corruption`; `pending compatibility cannot become ready through hash alone`; `hash and size mismatches remain non-destructive`; `bundled identity requires publisher authority`; `malformed stored hash is unknown, not file corruption`; `registry exception remains unknown without raw diagnostics`; `incomplete shard set cannot become ready`; `file-record hash cannot replace selected primary hash`; `single-file I/O failure remains typed unknown`; `primary file rows cannot bypass selected model size`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/model_startup_inspector.dart`

### [test/services/model_storage_preflight_test.dart](../../test/services/model_storage_preflight_test.dart)

Declared examples: `${reader.key} queries allocatable storage instead of telemetry`; `${reader.key} rejects malformed or negative storage values`; `${reader.key} treats platform failure and absence as unknown`.
Local targets: `package:vitalis_app/services/model_download_manager.dart`, `package:vitalis_app/services/model_downloader.dart`

### [test/services/model_update_service_test.dart](../../test/services/model_update_service_test.dart)

Declared examples: `check records a distinct immutable update revision`; `apply downloads the same quantization at the new revision`.
Local targets: `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_download_job.dart`, `package:vitalis_app/services/model_download_manager.dart`, `package:vitalis_app/services/model_hub_client.dart`, `package:vitalis_app/services/model_update_service.dart`

### [test/services/model_verification_runtime_test.dart](../../test/services/model_verification_runtime_test.dart)

Declared examples: `scope close joins active shutdown and drains the remaining actor`; `idle scope shutdown is shared and does not start native work`; `failed scope close stays failed; recovery never revives disposal`; `scope close joins recovery before retiring (outcome: $outcome)`; `active verification rejects competing work through close acknowledgement`; `rejected admission never closes a foreign owner`; `action error still awaits close without quarantining a healthy owner`; `failed close retains owner through shared recovery and confirmed handoff`; `unconfirmed recovery retains verification quarantine (throws: $throws)`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/services/model_verification_runtime.dart`

### [test/services/model_warmup_service_test.dart](../../test/services/model_warmup_service_test.dart)

Declared examples: `warmup skips unsafe devices and missing installed models`; `tuning rejects native prompt-token workload mismatch`; `benchmark budgeting and generation use the same thinking configuration`; `changing only prompt threads replaces the prepared context`; `tuning rejects $mismatch native configuration evidence`; `warmup initializes selected model once and dispose is idempotent`; `explicit missing model never loads an installed substitute`; `missing warmup selection preserves an already loaded model`; `same-model warmup preserves an existing effective profile`; `advanced overrides bypass cache and expose effective values`; `service disposal retains repository until cleanup acknowledges`; `service close shares cleanup and retains failure ($fails)`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`, `package:vitalis_app/services/runtime_profile_store.dart`, `package:vitalis_app/services/runtime_benchmark_workload.dart`

### [test/services/native_template_applier_test.dart](../../test/services/native_template_applier_test.dart)

Declared examples: `legacy failure $responses rejects guessed output`; `legacy mode rejects missing template without choosing ChatML`; `configured mode rejects missing model template before rendering`; `configured mode rejects unverified template without legacy fallback`.
Local targets: `package:llm_llamacpp/src/bindings/llama_bindings.dart`, `package:llm_llamacpp/src/exceptions.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:llm_llamacpp/src/native_template_applier.dart`

### [test/services/native_transfer_stop_test.dart](../../test/services/native_transfer_stop_test.dart)

Declared examples: `recovery completion after the shared deadline cannot finish Stop`; `recovery rejects unconfirmed or foreign response: $invalid`; `explicit cancellation recovers advertised quarantine before completion`; `one elapsed budget spans inventory, stop command and acknowledgement`; `elapsed budget prevents even the first native action`; `invalid waiting policy starts no native work: $policy`; `unidentified inventory fails closed: $inventory`; `missing transfer identity fails before any stop command`; `no matching native job finishes without cancelling a foreign job`; `late native error is observed without reopening an expired operation`; `error arriving at the elapsed limit remains a deadline failure`.
Local targets: `package:vitalis_app/services/native_transfer_stop.dart`

### [test/services/notification_permission_service_test.dart](../../test/services/notification_permission_service_test.dart)

Declared examples: `maps native granted status`.
Local targets: `package:vitalis_app/services/notification_permission_service.dart`

### [test/services/remote_gguf_inspector_test.dart](../../test/services/remote_gguf_inspector_test.dart)

Declared examples: `HTTP reader bounds streamed ignored-Range responses before buffering`; `HTTP reader accepts exactly bounded data`; `parses bounded text-model metadata`; `reports an incomplete range without guessing`; `rejects excessive metadata counts before allocating`; `range inspector expands exponentially only when incomplete`.
Local targets: `package:vitalis_app/services/remote_gguf_inspector.dart`

### [test/services/response_frame_timing_test.dart](../../test/services/response_frame_timing_test.dart)

Declared examples: `only a response frame after received text records submission latency`; `cancelled and replaced responses reject stale frame callbacks`; `backward clock cannot invent a rendered frame`.
Local targets: `package:vitalis_app/services/response_frame_timing.dart`

### [test/services/runtime_auto_tuner_test.dart](../../test/services/runtime_auto_tuner_test.dart)

Declared examples: `automatic tuner evaluates no more than six bounded candidates`; `automatic tuner selects the fastest safe weighted candidate`; `unknown telemetry keeps only the conservative profile`; `benchmark result cannot exceed the fixed generation workload`; `cancelled tuning stops before benchmarking`; `rejects invalid conservative $field rate $rate`; `stops when conservative baseline is $failure`; `rejects invalid and mismatched candidates after a valid baseline`; `accepts an equivalent copied configuration`; `cancellation during benchmark $cancelledCall rejects its result`; `Vulkan self-test probes bounded layer counts and retains best`.
Local targets: `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/backend_self_test.dart`, `package:vitalis_app/services/runtime_auto_tuner.dart`

### [test/services/runtime_benchmark_workload_test.dart](../../test/services/runtime_benchmark_workload_test.dart)

Declared examples: `complete template token count reaches exactly the fixed workload`; `non-monotonic tokenizer uses bounded exhaustive fallback`; `unreachable exact count fails instead of rounding or estimating`; `template changes between construction and verification are rejected`; `invalid native token count is rejected`; `context includes the fixed reserved output before tokenizing`; `cancellation after asynchronous tokenization stops further requests`; `cancellation after final token verification rejects the workload`.
Local targets: `package:vitalis_app/services/runtime_auto_tuner.dart`, `package:vitalis_app/services/runtime_benchmark_workload.dart`

### [test/services/runtime_cancellation_control_test.dart](../../test/services/runtime_cancellation_control_test.dart)

Declared examples: `Stop before handle is replayed through native control`; `normal or error terminal outcome retires Stop timing state`; `repeated Stop retains its first monotonic deadline`; `completed and unknown requests cannot recreate Stop intent`; `duplicate transferred references cannot replace the owned handle`; `null handles never enter native control`; `tagged arm64 handle preserves Stop and release bits `; `late tagged handle releases its transferred reference`; `duplicate or invalid request identity is rejected`; `bridge request failure retains Stop intent for retry`; `reference release failure does not forget the retained owner`; `final cleanup retires all request and handle state`.
Local targets: `package:llm_llamacpp/src/runtime_cancellation_control.dart`

### [test/services/runtime_capabilities_provider_test.dart](../../test/services/runtime_capabilities_provider_test.dart)

Declared examples: `Android snapshot parser preserves explicit capabilities`; `Android parser uses conservative missing-value defaults`; `desktop provider returns conservative capabilities`; `Android provider maps a platform snapshot`; `Android provider falls back on null and platform failures`.
Local targets: `package:vitalis_app/services/runtime_capabilities_provider.dart`

### [test/services/runtime_cleanup_fault_test.dart](../../test/services/runtime_cleanup_fault_test.dart)

Declared examples: `ordinary builds reject fault dispatch before claiming a context`; `ordinary cleanup has no injected faults`.
Local targets: `package:llm_llamacpp/src/runtime_cleanup_fault.dart`, `package:llm_llamacpp/src/runtime_request_finalizer.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:llm_llamacpp/src/generation_options.dart`

### [test/services/runtime_cleanup_quarantine_test.dart](../../test/services/runtime_cleanup_quarantine_test.dart)

Declared examples: `owner acknowledgement retires only its own retained requests`; `identity cannot be reassigned and null owner is not a wildcard`; `failed handle retirement retains identity for another acknowledged retry`; `cleanup failure retains reservation and control until owner recovery acknowledges`.
Local targets: `package:llm_llamacpp/src/runtime_cleanup_quarantine.dart`, `package:llm_llamacpp/src/runtime_cancellation_control.dart`, `package:llm_llamacpp/src/runtime_request_finalizer.dart`, `package:llm_llamacpp/src/runtime_session_reservation.dart`

### [test/services/runtime_exclusive_session_test.dart](../../test/services/runtime_exclusive_session_test.dart)

Declared examples: `target leases deduplicate aliases and release after failure`; `multi-target contention releases already acquired leases`; `file mutation reservation rejects preparation until it settles`; `file mutation error releases only its finished reservation`; `invalid repository shutdown policy fails the shared close future`; `repository close deadline retains unacknowledged shutdown`; `close shares acknowledgement and rejects new work immediately`; `failed disposal stays observable through close`; `disposed repository cannot acquire a new session`; `reserved context rejects competing operations without native loading`; `failed action with no native requests releases the reservation`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [test/services/runtime_initialization_guard_test.dart](../../test/services/runtime_initialization_guard_test.dart)

Declared examples: `progress resets inactivity without changing the maximum deadline`; `duplicate progress cannot postpone inactivity expiry`; `early and retired callbacks cannot expire completed work`; `recovery hook failure remains quarantined and does not rerun`; `scheduler failure retains the already-started operation`; `clock setup failure never starts an unowned initialization`; `progress adapter failure retains native ownership ($failClock)`; `negative deadline policy is rejected`; `pending initialization recognizes actual native progress`; `initialization callers share one operation`; `timeout retains late native result (failure: $fails)`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/runtime_initialization_guard.dart`

### [test/services/runtime_native_termination_test.dart](../../test/services/runtime_native_termination_test.dart)

Declared examples: `expired receipt retains owner and late acknowledgement ($owner)`; `concurrent cancellation observers share one acknowledgement`; `competing observer cannot quarantine another request`; `native acknowledgement does not await paused stream delivery`; `owner drain excludes another owner and waits for native receipt`; `rejected waiter cannot disturb its owner`; `unconfirmed cleanup fails both cancellation and owned drain`; `late duplicate acknowledgement cannot change recorded metrics`; `observer failure is typed and cannot strand acknowledgement`; `reentrant observer cannot acknowledge twice or reuse its identity`; `invalid unknown and duplicate identities are rejected`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/runtime_native_termination.dart`

### [test/services/runtime_owner_recovery_guard_test.dart](../../test/services/runtime_owner_recovery_guard_test.dart)

Declared examples: `recovery guard rejects ineligible work without executing cleanup`; `reentrant callers share a single owned attempt`; `unconfirmed outcome permits a later acknowledged attempt (throws: $throws)`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/runtime_owner_recovery_guard.dart`

### [test/services/runtime_profile_store_test.dart](../../test/services/runtime_profile_store_test.dart)

Declared examples: `another store cannot read a profile before write acknowledgement`; `profile round-trips and invalidates by complete key`; `rejected save restores previous profile before readers resume`; `rejected first save leaves no candidate in the cache`; `cancelled commit restores old profile before another store reads`; `already cancelled commit does not touch preferences`; `failed rollback quarantines candidate until acknowledged invalidation`; `model invalidation removes every backend profile for only that hash`.
Local targets: `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/runtime_profile_store.dart`

### [test/services/runtime_progress_test.dart](../../test/services/runtime_progress_test.dart)

Declared examples: `native progress rejects invalid identity units and clock`; `progress chunks carry no response content or token metrics`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [test/services/runtime_request_finalizer_test.dart](../../test/services/runtime_request_finalizer_test.dart)

Declared examples: `unstarted retry and duplicate registration are rejected`; `publication failure retries without repeating released resources`; `reentrant cleanup cannot publish or release resources twice`; `retains failed ${failingStep.name} and later steps for recovery`; `terminal publication follows every successful cleanup step`; `failed cleanup retains unpublished outcome and remaining resources`.
Local targets: `package:llm_llamacpp/src/runtime_request_finalizer.dart`

### [test/services/runtime_session_recovery_test.dart](../../test/services/runtime_session_recovery_test.dart)

Declared examples: `recovery retains an enclosing session until its action finishes`; `session exit during recovery does not retain an abandoned lease`; `failed idle context cleanup can be recovered only by its owner`; `snapshot separates retained context from a reserved operation`; `snapshot classifies owner-scoped native activity`; `snapshot distinguishes initialization wait and quarantine`; `anonymous legacy context is retained, not falsely unowned`; `snapshot preserves recovery outcome and never exposes owner objects`; `context survives request lease and blocks other owners until release`; `normal completion releases identity and operation kind`; `competing finish cannot release another owner`; `unconfirmed termination blocks every new reservation`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/runtime_session_reservation.dart`

### [test/services/runtime_shutdown_waiter_test.dart](../../test/services/runtime_shutdown_waiter_test.dart)

Declared examples: `reentrant and concurrent waiters share the owned operation`; `expired wait retains late result ($lateFailure)`; `failed shutdown starts another actor only on explicit retry`; `scheduler failure keeps started shutdown and retires old deadlines`; `broken clock cannot start an unowned shutdown`; `negative wait policy is rejected before shutdown`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/runtime_shutdown_waiter.dart`

### [test/services/runtime_watchdog_policy_test.dart](../../test/services/runtime_watchdog_policy_test.dart)

Declared examples: `preparation derives the existing generation deadline values`; `negative override values are rejected`; `zero deadlines are explicit valid fault-test overrides`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/generation_watchdog_policy.dart`

### [test/services/safety_logging_privacy_test.dart](../../test/services/safety_logging_privacy_test.dart)

Declared examples: `$failure logs exclude payload privacy=$privacy`.
Local targets: `package:vitalis_app/models/device_safety_policy.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/memory_pressure_service.dart`, `package:vitalis_app/utils/app_logger.dart`

### [test/services/sampling_input_validation_test.dart](../../test/services/sampling_input_validation_test.dart)

Declared examples: `invalid ${entry.key} rejected before touching another owner`; `native representable signed penalties and defaults remain valid`; `native sampler boundary modes remain usable without narrowing ABI`.
Local targets: `package:llm_llamacpp/src/generation_options.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`

### [test/services/selected_model_readiness_test.dart](../../test/services/selected_model_readiness_test.dart)

Declared examples: `late bootstrap result cannot publish readiness or overlap selection`; `bootstrap assessment alone never selects or enables a model`; `invalidation retains reader ownership and rejects its stale result`; `late prior assessment cannot unlock a different selected model`; `same selection shares work and explicit refresh rechecks`; `assessment errors and disposed completions never grant readiness`.
Local targets: `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/selected_model_readiness.dart`

### [test/services/startup_capabilities_test.dart](../../test/services/startup_capabilities_test.dart)

Declared examples: `owned assessment publishes $readiness without substitution`; `late assessment cannot unlock inference or overlap retry`; `assessment failure remains recoverable and read-only`; `disposed assessment rejects late readiness`; `permissions: database=$database migration=$migration `; `disposal revokes every permission`; `successful bootstrap does not assume a model was verified`.
Local targets: `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/startup_coordinator.dart`

### [test/services/startup_capability_source_test.dart](../../test/services/startup_capability_source_test.dart)

Declared examples: `timed-out bootstrap completion cannot enable inference`; `current chat model readiness controls inference without changing browse`.
Local targets: `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/selected_model_readiness.dart`, `package:vitalis_app/services/startup_capability_source.dart`, `package:vitalis_app/services/startup_coordinator.dart`

### [test/services/startup_coordinator_test.dart](../../test/services/startup_coordinator_test.dart)

Declared examples: `reaches ready after ordered bootstrap tasks complete`; `database timeout fails without allowing the application to start`; `optional task failures produce a usable degraded state`; `concurrent starts share one active bootstrap attempt`; `reentrant listener shares the already-owned startup operation`; `$phase failure blocks dependent app initialization`; `timeout retries cannot overlap unfinished database writes`; `disposed startup never enters later phases or notifies`.
Local targets: `package:vitalis_app/services/startup_coordinator.dart`

### [test/services/stop_sequence_prefix_test.dart](../../test/services/stop_sequence_prefix_test.dart)

Declared examples: `ordinary output is not delayed by an unrelated stop marker`; `retains only the actual split-marker prefix`; `uses longest matching prefix across overlapping markers`; `empty text and absent stop markers retain nothing`; `Unicode marker prefixes use the actual text boundary`; `every split of a marker retains exactly the unfinished suffix`.
Local targets: `package:llm_llamacpp/src/stop_sequence_prefix.dart`

### [test/services/unsupported_embedding_test.dart](../../test/services/unsupported_embedding_test.dart)

Declared examples: `unsupported embedding operation is explicit (batch: $batch)`; `disposed embedding caller remains rejected as disposed`; `unsupported embedding path has no independent native worker`; `obsolete standalone worker cannot bypass persistent runtime`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [test/stress/chat_state_controller_stress_test.dart](../../test/stress/chat_state_controller_stress_test.dart)

Declared examples: `ChatStateController stress (tier 2)`; `100 generation/completion and acknowledged Stop cycles (seed $seed)`; `10K idle cancels do not start work and shutdown settles`; `repeated dispose shares acknowledged shutdown`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`

### [test/stress/database_stress_test.dart](../../test/stress/database_stress_test.dart)

Declared examples: `Database stress (tier 3)`; `2000 sequential chat insert and retrieve`; `1000 messages in one chat`.
Local targets: `package:vitalis_app/database/database_helper.dart`

### [test/support/shard_restore_fixture.dart](../../test/support/shard_restore_fixture.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/constants/app_constants.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`

### [test/tool/bundled_model_ci_test.dart](../../test/tool/bundled_model_ci_test.dart)

Declared examples: `CI fixture export uses the application manifest authority`; `CI derives fixture identity instead of duplicating pinned values`; `every native model gate receives the mandatory manifest fixture`.
Local targets: `package:vitalis_app/models/bundled_model_manifest.dart`, `../../tool/export_bundled_model_manifest.dart`

### [test/tool/ci_workflow_gate_test.dart](../../test/tool/ci_workflow_gate_test.dart)

Declared examples: `maintained CI satisfies local evidence and dependency contracts`; `Android emulator gate requires support-floor and UIDT coverage`; `Android emulator results must be retained per API on failure`; `Android build cannot omit measured transfer recovery coverage`; `Android transfer coverage evidence must survive failed gates`; `malformed nested safety step is rejected`; `missing native coverage cannot fall back to root-only gate`; `normal matrix cannot accidentally enable fault mode`; `native text gate cannot omit manifest hash authority`; `coverage must wait for its native producer`; `coverage must download its native artifact`; `missing coverage package scope is rejected`. Additional declared cases are in the linked source.
Local targets: `../../tool/verify_ci_workflow.dart`

### [test/tool/clean_outputs_test.dart](../../test/tool/clean_outputs_test.dart)

Declared examples: `clean checkout passes without deleting retained source or cache`; `leftover $name rejects clean success without deleting it`.
Local targets: `../../tool/verify_clean_outputs.dart`

### [test/tool/coverage_gate_test.dart](../../test/tool/coverage_gate_test.dart)

Declared examples: `configured template components cannot evade native coverage gate`; `storage preflight requires measured coverage and rejects missing data`; `installation recovery components require measured 90 percent coverage`; `native lifecycle scope is explicit and adds no duplicate requirements`; `supporting preference and download lifecycle components cannot be missing`; `native lifecycle gate requires 90 percent in every component`; `multiple reports union line hits without double counting`; `summary totals cannot substitute for missing merge line identities`; `merge rejects invalid line records and unfinished records`; `coverage parser normalizes paths and records line totals`; `single report rejects missing identities and contradictory summaries`; `coverage gate reports missing and below-threshold files`.
Local targets: `../../tool/verify_coverage.dart`

### [test/tool/flutter_selection_test.dart](../../test/tool/flutter_selection_test.dart)

Declared examples: `accepts matching effective selections with spaces`; `rejects effective $key override despite correct environment`; `rejects missing effective $key`; `rejects malformed or non-object configuration`; `rejects nonexistent selected directory`.
Local targets: `../../tool/verify_flutter_selection.dart`

### [test/tool/flutter_version_gate_test.dart](../../test/tool/flutter_version_gate_test.dart)

Declared examples: `accepts compact and pretty machine JSON in any key order`; `rejects malformed and missing version data`; `rejects wrong SDKs, prefix matches, prereleases and wrong types`.
Local targets: `../../tool/validate_flutter_version.dart`

### [test/tool/gate_argument_forwarding_test.dart](../../test/tool/gate_argument_forwarding_test.dart)

Declared examples: `launcher preserves build mode, verbosity and spaced arguments`; `complete native handoff preserves exact arguments encoded=$encodedEntry`; `encoded transport rejects non-string-array input $invalid`; `encoded transport rejects malformed Base64 and mixed arguments`; `encoded transport rejects invalid UTF8 without replacing argument data`; `rejects implicit tool flags before launching a child`; `final Flutter invocation preserves regex pipe as one argument`; `PowerShell launcher also preserves its named argument array`.

### [test/tool/gate_safety_test.dart](../../test/tool/gate_safety_test.dart)

Declared examples: `exclusive acquisition rejects competing writer; owner can release`; `incomplete interrupted lock stays blocked, never automatically stolen`; `installed matching SDK and in-workspace caches pass`; `equivalent cache path spellings do not conflict`; `directory comparison preserves distinct paths and spaces`; `equivalent parent-traversal override remains rejected`; `rejects SDK environment and local-properties conflicts`; `rejects cache escape and conflicting override`; `rejects parent traversal and checkout root as cache`; `rejects missing platform and mismatched installed NDK`.
Local targets: `../../tool/generation_lock.dart`, `../../tool/verify_gate_environment.dart`

### [test/tool/hardcode_verifier_test.dart](../../test/tool/hardcode_verifier_test.dart)

Declared examples: `accepts a registered behavioral constant`; `rejects unclassified and unknown constants`; `rejects an explicitly required source that is missing`; `discovery includes app vendor and native build-hook sources`; `discovery rejects absent source roots and build hook`; `empty source roots do not satisfy discovery`; `generated-only vendor sources cannot masquerade as maintained coverage`; `removing a previously verified source cannot produce a pass`; `rejects malformed duplicate and incomplete register rows`; `Java policy classes and arithmetic constants are not exempt`; `Java parser rejects unknown IDs but ignores commented declarations`; `Java strings cannot forge a trailing disposition comment`. Additional declared cases are in the linked source.
Local targets: `../../tool/verify_hardcode_register.dart`

### [test/tool/native_fixture_verification_test.dart](../../test/tool/native_fixture_verification_test.dart)

Declared examples: `missing fixture path fails rather than skipping`; `missing expected authority fails rather than trusting the file`; `malformed expected authority fails`; `unreadable fixture fails with a redacted diagnostic`; `mismatched content cannot become an accepted fixture`; `matching content passes with case-insensitive supplied hash`.
Local targets: `../../third_party/llm_llamacpp/test/verified_model_fixture.dart`

### [test/tool/native_provenance_test.dart](../../test/tool/native_provenance_test.dart)

Declared examples: `Android C and C++ diagnostics do not embed the build checkout`; `native configure cannot inherit the surrounding app revision`.
Local targets: `../../third_party/llm_llamacpp/hook/native_provenance.dart`

### [test/tool/split_fixture_options_test.dart](../../test/tool/split_fixture_options_test.dart)

Declared examples: `fixture options preserve spaces without invoking a shell`; `fixture rejects invalid split limit $size`; `fixture rejects missing duplicate unknown and control-character options`.
Local targets: `../../tool/prepare_split_fixture.dart`

### [test/tool/toolchain_policy_test.dart](../../test/tool/toolchain_policy_test.dart)

Declared examples: `checked-in Android declarations agree with central policy`; `rejects drift in $key`; `rejects extra ABI and duplicate SDK declarations`; `rejects alternate wrapper source even with matching version`; `accepts one matching publisher checksum`; `rejects ${invalid.key} distribution checksum`; `rejects missing or malformed publisher checksum authority`; `rejects an absent bootstrap network deadline`; `rejects invalid bootstrap deadline authority`; `checked-in bootstrap matches publisher authority`; `checkout retains all wrapper entrypoints and executable Unix mode`; `Unix wrapper checkout enforces LF independently of host Git defaults`. Additional declared cases are in the linked source.
Local targets: `../../tool/verify_toolchain_policy.dart`

### [test/utils/app_logger_test.dart](../../test/utils/app_logger_test.dart)

Declared examples: `typed $mode failure never formats payload privacy=$privacy throws=$throwsOnString`; `loads privacy state and suppresses informational disk writes`; `writes sanitized entries, rotates, prunes, and clears`; `synchronous facade records bounded local diagnostics`; `partial log cleanup reports retained files rather than success`; `unavailable log storage reports failure without hiding retained memory`; `synchronous informational logs obey privacy mode`; `flush waits for slow storage and every queued write`; `privacy disabling waits for persistence acknowledgement`; `failed privacy enable keeps runtime protection without durable success`; `failed privacy write does not poison a subsequent acknowledged retry`; `privacy writes serialize and stale disable cannot undo protection`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/utils/app_logger.dart`

### [test/utils/date_formatter_test.dart](../../test/utils/date_formatter_test.dart)

Declared examples: `DateFormatter`; `formatRelative returns justNow for recent timestamps`; `formatRelative returns minutes ago for timestamps within an hour`; `formatRelative returns hours ago for timestamps within a day`; `formatRelative returns date for older timestamps`; `formatChatDate returns justNow for very recent timestamps`; `formatChatDate returns minutes ago`; `formatChatDate returns hours ago`; `formatChatDate returns days ago`.
Local targets: `package:vitalis_app/utils/date_formatter.dart`

### [test/widget_test.dart](../../test/widget_test.dart)

Declared examples: `ProgressBar`; `renders with label`; `renders without label`; `F4C Defect Closures (DEF_01, DEF_02, DEF_03)`; `DEF_01: pubspec is the only literal package version authority`; `DEF_02: Database error UX copy contains non-destructive messaging without overclaiming`; `DEF_03: GGUF magic header validation rejects empty, small, or non-GGUF bytes`; `ConfirmDialog displays title, message, and buttons with semantics`.
Local targets: `package:vitalis_app/widgets/progress_bar.dart`, `package:vitalis_app/widgets/confirm_dialog.dart`, `package:vitalis_app/constants/app_strings.dart`

### [test/widgets/chat_history_read_only_test.dart](../../test/widgets/chat_history_read_only_test.dart)

Declared examples: `history reports committed deletion without suggesting retry`; `history never displays arbitrary private failure text`; `history rejects repeated delete confirmation actions`; `read-only history disables deletion but keeps browsing`; `open history follows live mutation permission changes`; `permission revoked during confirmation preserves the chat`.
Local targets: `package:vitalis_app/constants/app_strings.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/chat_deletion_error.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/screens/modals/chat_history_modal.dart`, `package:vitalis_app/services/startup_access_guard.dart`

### [test/widgets/chat_response_frame_test.dart](../../test/widgets/chat_response_frame_test.dart)

Declared examples: `pending prompt save cannot affect a newly selected chat failure=$fails`; `composer retains unsaved input when provider reports a storage failure`; `selected persona stays visible and can be removed without detaching notes`; `conversation fits a narrow screen with large text and RTL`; `device details show memory as a value instead of a provider object`; `header names the assigned model and follows chat selection`; `header does not keep a previous model after a missing selection`; `late name lookup cannot replace the newly selected model`; `long model names fit a narrow chat header`; `delayed attachment removal cannot change a newly selected chat`; `failed attachment removal preserves both notes and reports a redacted error`; `failed export does not replace the clipboard or report success`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/providers/health_provider.dart`, `package:vitalis_app/providers/theme_provider.dart`, `package:vitalis_app/screens/chat_screen.dart`, `package:vitalis_app/theme/app_theme.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/services/response_frame_timing.dart`, `package:vitalis_app/services/selected_model_readiness.dart`, `package:vitalis_app/services/startup_access_guard.dart`, `package:vitalis_app/widgets/message_bubble.dart`, `package:vitalis_app/constants/app_strings.dart`

### [test/widgets/conversation_design_test.dart](../../test/widgets/conversation_design_test.dart)

Declared examples: `unknown device measurements stay unknown and errors retain Retry`; `conversation colour pairs remain readable in ${theme.brightness}`; `conversation messages use theme surfaces without repeated avatars`; `assistant copy action is visible and uses the original message`; `empty composer disables Send and a failed submission keeps its draft`; `Stop stays reachable while native cancellation is pending`.
Local targets: `package:vitalis_app/models/message.dart`, `package:vitalis_app/theme/app_theme.dart`, `package:vitalis_app/widgets/conversation_status_bar.dart`, `package:vitalis_app/constants/app_strings.dart`, `package:vitalis_app/widgets/message_bubble.dart`, `package:vitalis_app/widgets/chat_input_field.dart`, `package:vitalis_app/services/chat_state_controller.dart`

### [test/widgets/home_screen_test.dart](../../test/widgets/home_screen_test.dart)

Declared examples: `home lazily mounts destinations and retains conversation search`; `read-only overview opens existing chat without creating or selecting a different model`; `delayed selection rejects duplicate opens and cannot navigate after dismissal`; `load failure remains recoverable and does not disclose exception text`; `an unrelated conversation error does not mark history loading failed`; `compact home supports large text and RTL without overflow`; `a selected chat with a generation error remains openable for recovery`; `home route resolves to the conversation overview shell`.
Local targets: `package:vitalis_app/models/chat.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/screens/home_screen.dart`, `package:vitalis_app/screens/chats_overview_screen.dart`, `package:vitalis_app/services/startup_access_guard.dart`, `package:vitalis_app/app_router.dart`

### [test/widgets/message_bubble_test.dart](../../test/widgets/message_bubble_test.dart)

Declared examples: `announces an assistant reply once`.
Local targets: `package:vitalis_app/models/message.dart`, `package:vitalis_app/widgets/message_bubble.dart`

### [test/widgets/model_library_screen_states_test.dart](../../test/widgets/model_library_screen_states_test.dart)

Declared examples: `browse keeps every section visible and hides advanced filters`; `filters commit on Apply and dismiss without changing active search`; `large text section selector navigates without clipping`; `accepted download opens progress before transfer completion`; `search keyboard closes on $action`; `Hub search renders $state without losing navigation`; `loading indicator clears when Hub results arrive`; `search controls remain usable in landscape with keyboard space`.
Local targets: `package:vitalis_app/models/hub_model.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_download_job.dart`, `package:vitalis_app/providers/model_library_provider.dart`, `package:vitalis_app/screens/model_library_screen.dart`, `package:vitalis_app/services/remote_gguf_inspector.dart`

### [test/widgets/model_recovery_status_label_test.dart](../../test/widgets/model_recovery_status_label_test.dart)

Declared examples: `recovery status wraps in $brightness at $width with large text`.
Local targets: `package:vitalis_app/models/model_verification_phase.dart`, `package:vitalis_app/services/model_recovery_controller.dart`, `package:vitalis_app/widgets/model_recovery_status_label.dart`

### [test/widgets/persona_selection_persistence_test.dart](../../test/widgets/persona_selection_persistence_test.dart)

Declared examples: `persona deletion reports acknowledged result=$succeeds`; `$action save result=$succeeds controls modal closure`; `$action rejects duplicate submission while saving`; `$action completion after dismissal cannot pop another page`.
Local targets: `package:vitalis_app/constants/app_strings.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/screens/modals/persona_selection_modal.dart`, `package:vitalis_app/services/startup_access_guard.dart`

### [test/widgets/response_frame_observer_test.dart](../../test/widgets/response_frame_observer_test.dart)

Declared examples: `reports after paint once per response, not every rebuild`.
Local targets: `package:vitalis_app/widgets/response_frame_observer.dart`

### [test/widgets/saved_content_read_only_test.dart](../../test/widgets/saved_content_read_only_test.dart)

Declared examples: `read-only ${personas ? `; `open note editor retains its draft while readiness changes`; `a stale Save callback rechecks current permissions`; `permission evidence ${missing ? `; `saved-note collection remains scrollable in read-only mode`; `saved-persona collection remains scrollable in read-only mode`; `persona submission rejects duplicate actions while persistence is pending`; `saved-content failure presents a redacted ${denied ? `; `retired saved-content context does not receive failure UI`.
Local targets: `package:vitalis_app/constants/app_strings.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/screens/modals/note_edit_modal.dart`, `package:vitalis_app/screens/modals/notes_list_selection_modal.dart`, `package:vitalis_app/screens/modals/persona_selection_modal.dart`, `package:vitalis_app/services/startup_access_guard.dart`, `package:vitalis_app/widgets/startup_mutation_access.dart`

### [test/widgets/saved_screen_test.dart](../../test/widgets/saved_screen_test.dart)

Declared examples: `$section opens a preview without selecting content (writable: $writable)`; `creating a persona from Saved keeps the management page open`.
Local targets: `package:vitalis_app/constants/app_strings.dart`, `package:vitalis_app/models/note.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/screens/saved_screen.dart`, `package:vitalis_app/screens/modals/persona_selection_modal.dart`, `package:vitalis_app/services/startup_access_guard.dart`

### [test/widgets/settings_auto_reset_recovery_cases.dart](../../test/widgets/settings_auto_reset_recovery_cases.dart)

Declared examples: `pending Auto reset preserves newer same-chat settings`; `pending Auto reset rejects repeated stale actions`; `disposed Auto reset cannot start a settings write`; `failed Auto reset retains settings and redacts diagnostics`.

### [test/widgets/settings_dialog_recovery_cases.dart](../../test/widgets/settings_dialog_recovery_cases.dart)

Declared examples: `pending system-prompt Save rejects a repeated stale action`; `disposed prompt editor rejects late save failure feedback`; `empty prompt stays editable without starting persistence`; `changed chat selection cannot receive an old prompt draft`; `system-prompt draft survives live readiness revocation`; `stale system-prompt Save rechecks access without losing the draft`; `failed system-prompt save retains draft and allows retry`; `disposed Settings cannot activate a pending import`.

### [test/widgets/settings_log_recovery_cases.dart](../../test/widgets/settings_log_recovery_cases.dart)

Declared examples: `repeated log-clear actions open one confirmation`; `failed log cleanup never reports success`.

### [test/widgets/settings_model_reset_recovery_cases.dart](../../test/widgets/settings_model_reset_recovery_cases.dart)

Declared examples: `reset readiness is identity-scoped: $scenario`; `completed reset invalidates readiness after Settings navigation`; `model reset rejects repeated confirmation actions`; `model reset rechecks readiness after confirmation`; `model reset errors remain observable and redacted`; `retired Settings cannot open reset confirmation`.

### [test/widgets/settings_mutation_recovery_cases.dart](../../test/widgets/settings_mutation_recovery_cases.dart)

Declared examples: `slider preview and commit preserve the selected settings owner`; `settings callbacks after disposal cannot start writes`; `settings save failure after navigation has no late UI error`; `thinking-mode save failure produces redacted feedback`; `stale slider preview handles readiness loss`; `old slider persistence cannot modify a newly selected chat`.

### [test/widgets/settings_preference_recovery_cases.dart](../../test/widgets/settings_preference_recovery_cases.dart)

Declared examples: `pending privacy save rejects repeated stale actions`; `privacy persistence can retry after a redacted failure`; `privacy failure after navigation has no late UI publication`; `failed privacy persistence retains protection and reports failure`; `read-only Settings disables persistent preferences and log deletion`; `failed Settings theme action produces redacted feedback`; `stale theme action rechecks readiness before persistence`; `retired Settings cannot submit a theme change`.

### [test/widgets/settings_recovery_test.dart](../../test/widgets/settings_recovery_test.dart)

Declared examples: `privacy policy distinguishes local conversations from model networking`; `app Settings hides controls that would edit the current conversation`; `chat Settings excludes app preferences and global model reset`; `changing model cannot borrow the previous template thinking capability`; `chat Settings without a selected conversation cannot edit defaults`; `chat Settings supports narrow large-text layouts without truncating metadata`; `stored ${entry.key} remains visible and editable`; `numeric editor retains rejected input then commits only the selected setting`; `numeric presets only fill a draft and Cancel preserves saved values`; `numeric save failure keeps the draft for a redacted retry`; `an old numeric editor cannot save into a different chat`; `a stale $label action cannot open an editor for a newly selected chat`. Additional declared cases are in the linked source.
Local targets: `package:vitalis_app/utils/app_logger.dart`, `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/selected_model_readiness.dart`, `package:vitalis_app/constants/app_strings.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/theme_provider.dart`, `package:vitalis_app/screens/settings_screen.dart`, `package:vitalis_app/services/model_download_service.dart`, `package:vitalis_app/services/model_downloader.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/startup_access_guard.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/models/chat.dart`

### [test/widgets/startup_shell_test.dart](../../test/widgets/startup_shell_test.dart)

Declared examples: `renders a visible boot frame while database opening is pending`; `shows retry UI after non-destructive database failure`.
Local targets: `package:vitalis_app/services/startup_coordinator.dart`, `package:vitalis_app/widgets/startup_shell.dart`

### [test/widgets/vitalis_dependencies_test.dart](../../test/widgets/vitalis_dependencies_test.dart)

Declared examples: `dependency graph forwards committed persona changes to chat`; `dependency graph exposes the selected model and live guard`; `dependency graph forwards current startup permissions to all content providers`; `unused scope does not create runtime dependencies`; `rebuild keeps one runtime service and controller`; `removing scope starts owned runtime cleanup`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/widgets/vitalis_dependencies.dart`, `package:vitalis_app/providers/chat_provider.dart`, `package:vitalis_app/providers/note_provider.dart`, `package:vitalis_app/providers/persona_provider.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/persona.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/startup_access_guard.dart`, `package:vitalis_app/services/selected_model_readiness.dart`

## test_native

### [test_native/async_disposal_recovery_test.dart](../../test_native/async_disposal_recovery_test.dart)

Declared examples: `asynchronous disposal retains a failed control operation until owner recovery`; `owned legacy handle is retained after failed disposal and freed on recovery`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/benchmark_workload_test.dart](../../test_native/benchmark_workload_test.dart)

Declared examples: `native benchmark counts and evaluates exactly 256 prompt tokens (control: $supportsThinkingControl)`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/runtime_benchmark_workload.dart`

### [test_native/borrowed_model_lifecycle_test.dart](../../test_native/borrowed_model_lifecycle_test.dart)

Declared examples: `uninstall unrelated model preserves an externally loaded model`; `borrowed model survives repository close and acknowledged handoff`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/bundled_install_projection_test.dart](../../test_native/bundled_install_projection_test.dart)

Declared examples: `real bundled install preserves its old record on projection failure and retries`.
Local targets: `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`

### [test_native/cold_generation_loading_cancellation_test.dart](../../test_native/cold_generation_loading_cancellation_test.dart)

Declared examples: `cold generation exposes cancellation before native model loading`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/cold_tokenization_cancellation_test.dart](../../test_native/cold_tokenization_cancellation_test.dart)

Declared examples: `cold tokenization Stop waits for helper and allows a later tokenization`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/helper_cleanup_fault_test.dart](../../test_native/helper_cleanup_fault_test.dart)

Declared examples: `explicit fault mode rejects nonpositive failure counts`; `abandoned text stream acknowledges native cancellation before reuse`; `failed terminal observer retains real owner until acknowledged recovery`; `failed native unload is typed and retains its context owner`; `actual helper retains ${step.name} cleanup until owner retry`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:llm_llamacpp/src/runtime_cleanup_fault.dart`, `package:llm_llamacpp/src/runtime_request_finalizer.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/legacy_reset_ownership_test.dart](../../test_native/legacy_reset_ownership_test.dart)

Declared examples: `reset preserves another installed model sharing the bundled file`; `failed reset lookup is redacted and leaves files untouched`; `legacy reset cannot delete a file owned by another native writer`; `legacy reset reports registry projection failure instead of success`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_downloader.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/model_registry_service.dart`

### [test_native/model_registry_probe_test.dart](../../test_native/model_registry_probe_test.dart)

Declared examples: `verified bundled fixture passes actual registry inference probe`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`

### [test_native/model_wrapper_contract_test.dart](../../test_native/model_wrapper_contract_test.dart)

Declared examples: `native params apply mmap=$mapped mlock=$locked`; `unsupported $capability is rejected before native loading`; `pooled model rejects changed options without changing references`; `missing and empty files never enter native loading`; `file writer prevents model loading without affecting its lease`; `malformed native model releases its file lease`; `real model accessors reject use after idempotent disposal`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/bindings/llama_bindings.dart`, `package:llm_llamacpp/src/loader/loader.dart`, `package:llm_llamacpp/src/native_runtime_bridge.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/native_response_frame_test.dart](../../test_native/native_response_frame_test.dart)

Declared examples: `real native response identity reaches a painted MessageBubble`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/widgets/message_bubble.dart`, `package:vitalis_app/widgets/response_frame_observer.dart`

### [test_native/output_timing_contract_test.dart](../../test_native/output_timing_contract_test.dart)

Declared examples: `helper first-output latency includes model context and prompt work`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/owner_close_recovery_test.dart](../../test_native/owner_close_recovery_test.dart)

Declared examples: `readiness revocation stops real generation before safe followup admission`; `legacy backend and loader cannot bypass another context owner`; `oversized native prompt fails before decode and permits owner reuse`; `unprepared tokenization and missing model retain owner until cleanup`; `helper shutdown rejects owned context and restarts after acknowledged unload`; `revoked context owner cannot start work but can finish cleanup`; `repository close expiry retains real context until explicit recovery`; `cached warmup restores context unloaded by owner recovery`; `expired controller Stop retains real owner until explicit recovery`; `packaged bridge retains the receiver token after helper release`; `preparation deadline retains real native work until owner unload acknowledges`; `Stop at first native progress aborts subsequent decoding`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/native_runtime_bridge.dart`, `package:llm_llamacpp/src/loader/loader.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/models/generation_watchdog_policy.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/startup_access_guard.dart`

### [test_native/preparation_cancellation_cases.dart](../../test_native/preparation_cancellation_cases.dart)

Declared examples: `Stop during backend initialization prevents model preparation`; `explicit Stop after preparation handle publication terminates loading`; `Stop addresses retained native preparation`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/prompt_thread_configuration_test.dart](../../test_native/prompt_thread_configuration_test.dart)

Declared examples: `native context applies independent generation and prompt threads`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/qwen_thinking_control_test.dart](../../test_native/qwen_thinking_control_test.dart)

Declared examples: `Qwen3.5 thinking $thinking counts and decodes its branch: $content`; `Qwen3.5 thinking $thinking renders history without mutating replies`; `template ABI reports size without overwriting an insufficient buffer`; `locked legacy API rejects unknown templates without output`; `template ABI contains malformed input failures without output`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/bindings/llama_bindings.dart`, `package:llm_llamacpp/src/loader/loader.dart`, `package:llm_llamacpp/src/third_party/vitalis_chat_template.g.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/model_descriptor.dart`

### [test_native/registry_probe_cleanup_test.dart](../../test_native/registry_probe_cleanup_test.dart)

Declared examples: `verification retains failed cleanup around a real context until recovery`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/model_verification_runtime.dart`

### [test_native/registry_probe_safety_test.dart](../../test_native/registry_probe_safety_test.dart)

Declared examples: `registry health revocation preserves records (preparation: $duringPreparation)`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`

### [test_native/safety_telemetry_shutdown_test.dart](../../test_native/safety_telemetry_shutdown_test.dart)

Declared examples: `failed watchdog stops native decoding (during text: $failDuringText)`; `lost telemetry stops native decoding (stream closes: $streamCloses)`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`

### [test_native/same_owner_admission_test.dart](../../test_native/same_owner_admission_test.dart)

Declared examples: `same owner cannot admit overlapping native work or replace request identity`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/sampler_history_contract_test.dart](../../test_native/sampler_history_contract_test.dart)

Declared examples: `native sample accepts exactly once; extra accept doubles frequency`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/bindings/llama_bindings.dart`, `package:llm_llamacpp/src/loader/loader.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/split_model_restoration_test.dart](../../test_native/split_model_restoration_test.dart)

Declared examples: `real split GGUF restores with acknowledged probe cleanup and subsequent inference`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/database/database_helper.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_verification_phase.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/startup_capabilities.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/model_startup_inspector.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`

### [test_native/stop_sequence_streaming_test.dart](../../test_native/stop_sequence_streaming_test.dart)

Declared examples: `unrelated stop marker preserves native output without batching it all`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/isolate_messages.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

### [test_native/tuning_preemption_test.dart](../../test_native/tuning_preemption_test.dart)

Declared examples: `cold inference has request identity and Stop waits for helper readiness`; `native tuning Stop during preparation is cancelled and yields to chat`; `native tuning yields after emitted text and permits user inference (safety: $safetyStop)${scenario.streamClosed ? `.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/model_descriptor.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/providers/generation_provider.dart`, `package:vitalis_app/services/chat_state_controller.dart`, `package:vitalis_app/models/runtime_capabilities.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/hardware_sentinel_service.dart`, `package:vitalis_app/services/model_registry_service.dart`, `package:vitalis_app/services/model_warmup_service.dart`, `package:vitalis_app/services/runtime_capabilities_provider.dart`, `package:vitalis_app/services/runtime_profile_store.dart`

### [test_native/unicode_tokenization_test.dart](../../test_native/unicode_tokenization_test.dart)

Declared examples: `planner caps output using the real multilingual template count`; `chat token count includes the complete ${entry.key} template`; `generation evaluates every UTF-8 byte of an above-batch prompt`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:llm_llamacpp/src/bindings/llama_bindings.dart`, `package:llm_llamacpp/src/loader/loader.dart`, `package:llm_llamacpp/src/persistent_inference_isolate.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`, `package:vitalis_app/models/message.dart`, `package:vitalis_app/models/model_settings.dart`, `package:vitalis_app/models/runtime_profile.dart`, `package:vitalis_app/services/context_planner.dart`

### [test_native/unsupported_embedding_ownership_test.dart](../../test_native/unsupported_embedding_ownership_test.dart)

Declared examples: `embedding rejection leaves active real-model generation untouched`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`, `package:vitalis_app/models/bundled_model_manifest.dart`

## Native C++ fixtures

### [third_party/llm_llamacpp/native/tests/CMakeLists.txt](../../third_party/llm_llamacpp/native/tests/CMakeLists.txt)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [third_party/llm_llamacpp/native/tests/allocation_failure.cpp](../../third_party/llm_llamacpp/native/tests/allocation_failure.cpp)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [third_party/llm_llamacpp/native/tests/cancel_lifetime.cpp](../../third_party/llm_llamacpp/native/tests/cancel_lifetime.cpp)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

## Vendored Dart tests

### [third_party/llm_llamacpp/test/README.md](../../third_party/llm_llamacpp/test/README.md)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [third_party/llm_llamacpp/test/all_tests.dart](../../third_party/llm_llamacpp/test/all_tests.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [third_party/llm_llamacpp/test/integration/chat_history_test.dart](../../third_party/llm_llamacpp/test/integration/chat_history_test.dart)

Declared examples: `Chat History`; `two-turn conversation`; `three-turn conversation`; `context preservation across multiple turns`; `mixed roles in conversation`; `long conversation history`; `context window limits`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/integration/edge_cases_test.dart](../../third_party/llm_llamacpp/test/integration/edge_cases_test.dart)

Declared examples: `Edge Cases`; `handles empty message content`; `handles very long single message`; `handles unicode edge cases`; `handles JSON-like content`; `handles code-like content`; `handles concurrent requests`; `handles extremely long prompts`; `handles rapid successive requests`; `handles special characters in prompts`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/integration/embeddings_test.dart](../../third_party/llm_llamacpp/test/integration/embeddings_test.dart)

Declared examples: `Embeddings`; `generates single text embedding`; `generates batch embeddings`; `batchEmbed returns same length and dimensions as embed`; `embedding dimensions consistency`; `embedding similarity - similar texts`; `embedding consistency - same text`; `handles empty string embedding`; `handles very long text embedding`; `handles special characters in embedding`; `throws when no model loaded`; `throws on empty messages`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/integration/error_handling_test.dart](../../third_party/llm_llamacpp/test/integration/error_handling_test.dart)

Declared examples: `Error Handling`; `throws on invalid model path`; `throws on invalid file format`; `throws when streaming without model`; `throws when embedding without model`; `throws on empty messages array`; `handles unload errors gracefully`; `handles dispose when model not loaded`; `handles dispose when model is loaded`; `handles invalid context size`; `handles concurrent model loads`; `handles embedding with empty messages`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/integration/model_loading_test.dart](../../third_party/llm_llamacpp/test/integration/model_loading_test.dart)

Declared examples: `Model Loading`; `initializes backend without model`; `loads valid GGUF model`; `loads model with GPU offloading`; `loads model with memory mapping disabled`; `throws on invalid model path`; `throws on invalid file format`; `can unload and reload model`; `replaces model when loading new one`; `model reports correct special tokens`; `Model Metadata`; `exposes vocabulary size`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/integration/streaming_test.dart](../../third_party/llm_llamacpp/test/integration/streaming_test.dart)

Declared examples: `Streaming Behavior`; `chunk ordering`; `done flag on final chunk`; `partial content accumulation`; `chunk metadata`; `token counting`; `stream interruption handling`; `multiple chunks for longer responses`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/integration/test_config.dart](../../third_party/llm_llamacpp/test/integration/test_config.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [third_party/llm_llamacpp/test/integration/text_generation_test.dart](../../third_party/llm_llamacpp/test/integration/text_generation_test.dart)

Declared examples: `Text Generation`; `generates response to simple prompt`; `generates streaming tokens`; `handles system prompt`; `maintains conversation context`; `respects max tokens limit`; `handles empty message list gracefully`; `throws when no model loaded`; `Prompt Templates`; `auto-detects template from model name`; `formats messages with ChatML template`; `formats messages with Llama3 template`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/integration/tool_use_test.dart](../../third_party/llm_llamacpp/test/integration/tool_use_test.dart)

Declared examples: `Tool Definition`; `creates tool with parameters`; `tool execution returns result`; `tool serializes to JSON schema`; `Tool Calling with Model`; `parses JSON tool call from model output`; `executes tool and returns result`; `handles multiple tools`; `Tool Call Parsing`; `parses standard JSON format`; `parses XML-wrapped JSON format`; `parses multiple tool calls`. Additional declared cases are in the linked source.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/unit/empty_think_envelope_filter_test.dart](../../third_party/llm_llamacpp/test/unit/empty_think_envelope_filter_test.dart)

Declared examples: `EmptyThinkEnvelopeFilter`; `removes an empty envelope split over streamed chunks`; `preserves a non-empty think block instead of hiding it`; `does not delay a normal response`.
Local targets: `package:llm_llamacpp/src/empty_think_envelope_filter.dart`

### [third_party/llm_llamacpp/test/unit/native_log_test.dart](../../third_party/llm_llamacpp/test/unit/native_log_test.dart)

Declared examples: `is silent until a structured sink is injected`; `redacts paths credentials query values and native addresses`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

### [third_party/llm_llamacpp/test/unit/prompt_batching_test.dart](../../third_party/llm_llamacpp/test/unit/prompt_batching_test.dart)

Declared examples: `promptDecodeChunks`; `does not create a decode request for an empty prompt`; `keeps an exact native batch intact`; `splits the 256-token tuning workload at the 128-token boundary`; `rejects invalid native batch sizes`.
Local targets: `package:llm_llamacpp/src/prompt_batching.dart`

### [third_party/llm_llamacpp/test/unit/tool_call_parser_test.dart](../../third_party/llm_llamacpp/test/unit/tool_call_parser_test.dart)

Declared examples: `ToolCallParser`; `parseToolCalls assigns non-empty ids for JSON format`; `parseToolCalls assigns non-empty ids for function-style format`.
Local targets: `package:llm_llamacpp/src/tool_call_parser.dart`

### [third_party/llm_llamacpp/test/verified_model_fixture.dart](../../third_party/llm_llamacpp/test/verified_model_fixture.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [third_party/llm_llamacpp/test/vitalis_text_runtime_gate_test.dart](../../third_party/llm_llamacpp/test/vitalis_text_runtime_gate_test.dart)

Declared examples: `tokenizes through the prepared native text context`; `reuses process backend across 25 model load and unload cycles`; `generates visible text and authoritative completion metrics`; `acknowledged cancellation returns ready for the next request`.
Local targets: `package:llm_llamacpp/llm_llamacpp.dart`

## tool

### [tool/TransferCoverageGateTest.java](../../tool/TransferCoverageGateTest.java)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/VerifyAndroidNativeInventoryTest.java](../../tool/VerifyAndroidNativeInventoryTest.java)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/VerifyFlutterNoticesTest.java](../../tool/VerifyFlutterNoticesTest.java)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/VerifyUnsignedArtifactsTest.java](../../tool/VerifyUnsignedArtifactsTest.java)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_android_dependency_policy.dart](../../tool/test_android_dependency_policy.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_ci_acceptance.js](../../tool/test_ci_acceptance.js)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_ci_workflow.dart](../../tool/test_ci_workflow.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_coverage_integrity.dart](../../tool/test_coverage_integrity.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_generation_lock.dart](../../tool/test_generation_lock.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_generation_lock_termination.dart](../../tool/test_generation_lock_termination.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_gradle_wrapper_timeout.dart](../../tool/test_gradle_wrapper_timeout.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_java_socket_policy.dart](../../tool/test_java_socket_policy.dart)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.

### [tool/test_split_fixture_builder.js](../../tool/test_split_fixture_builder.js)

Test support/fixture or standalone regression entry point. Read the linked source for the exact assertions and prerequisites.
