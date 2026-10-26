package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import androidx.work.Data;
import androidx.work.Worker;
import androidx.work.testing.TestWorkerBuilder;
import androidx.work.testing.WorkManagerTestInitHelper;
import java.io.File;
import java.nio.file.Files;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public final class TransferStopWorkerTest {
    @org.junit.After public void closeWorkDatabase() {
        WorkManagerTestInitHelper.closeWorkDatabase();
    }

    private Context context;
    private TransferManifestStore store;
    private File partial;
    private static final String ID = "notification-stop-worker";

    @Before public void prepare() throws Exception {
        context = ApplicationProvider.getApplicationContext();
        WorkManagerTestInitHelper.initializeTestWorkManager(context);
        store = new TransferManifestStore(context);
        partial = new File(context.getFilesDir(), "models/stop-worker.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        store.write(new TransferManifest(ID, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
    }

    private Worker.Result stop(String identity, boolean cancel) {
        return stop(identity, cancel, 0L);
    }

    private Worker.Result stop(String identity, boolean cancel, long generation) {
        return TestWorkerBuilder.from(context, TransferStopWorker.class, Runnable::run)
                .setInputData(new Data.Builder()
                        .putString(TransferScheduler.INPUT_TRANSFER_ID, identity)
                        .putLong(TransferStopWorker.INPUT_GENERATION, generation)
                        .putBoolean(TransferStopWorker.INPUT_CANCEL, cancel).build())
                .build().doWork();
    }

    @Test public void cancelThenLatePauseCannotReviveCancelledTransfer() throws Exception {
        File unrelated = new File(partial.getParentFile(), "unrelated.gguf.part");
        Files.write(unrelated.toPath(), new byte[] { 114 });
        assertEquals(Worker.Result.success(), stop(ID, true));
        assertFalse(partial.exists());
        long revision = store.read(ID).stateRevision;
        assertEquals(Worker.Result.success(), stop(ID, false));
        assertEquals(TransferManifest.CANCELLED, store.read(ID).state);
        assertTrue(store.read(ID).stopAcknowledged);
        assertEquals(revision, store.read(ID).stateRevision);
        assertEquals(1L, unrelated.length());
    }

    @Test public void oldCommandCannotCancelResumedTransfer() throws Exception {
        assertEquals(Worker.Result.success(), stop(ID, false));
        TransferManifest paused = store.read(ID);
        TransferManifest resumed = store.write(paused.withProgress(
                TransferManifest.QUEUED, partial.length(), paused.retryCount, null, paused.entityTag));
        assertEquals(Worker.Result.success(), stop(ID, true));
        assertEquals(TransferManifest.QUEUED, store.read(ID).state);
        assertEquals(resumed.stateRevision, store.read(ID).stateRevision);
        assertEquals(1L, partial.length());
        assertEquals(1L, new TransferManifestStore(context).read(ID).controlGeneration);
        assertEquals(Worker.Result.success(), stop(ID, false, resumed.controlGeneration));
        assertEquals(TransferManifest.PAUSED, store.read(ID).state);
        assertTrue(store.read(ID).stopAcknowledged);
    }

    @Test public void resumedSchedulerWorkSurvivesOlderStopSignal() throws Exception {
        java.util.concurrent.atomic.AtomicBoolean resumeAtSignal = new java.util.concurrent.atomic.AtomicBoolean();
        Context crossing = new android.content.ContextWrapper(context) {
            @Override public Context getApplicationContext() { return this; }
            @Override public File getFilesDir() {
                if (resumeAtSignal.compareAndSet(true, false)) {
                    try {
                        new TransferController(context).acknowledgeStop(ID);
                        TransferManifest paused = store.read(ID);
                        assertTrue(paused.stopAcknowledged);
                        TransferManifest replacement = store.write(paused.withProgress(
                                TransferManifest.QUEUED, partial.length(), paused.retryCount, null, paused.entityTag));
                        assertTrue(TransferScheduler.schedule(context, replacement));
                    } catch (Exception failure) { throw new AssertionError(failure); }
                }
                return context.getFilesDir();
            }
        };
        TransferController controller = new TransferController(crossing);
        resumeAtSignal.set(true);
        assertTrue(controller.stopForGeneration(ID, false, 0L));
        java.util.List<androidx.work.WorkInfo> jobs = androidx.work.WorkManager.getInstance(context)
                .getWorkInfosByTag(ID).get(10, java.util.concurrent.TimeUnit.SECONDS);
        assertEquals(1, jobs.size());
        assertEquals("old Stop must not cancel the newly scheduled replacement",
                androidx.work.WorkInfo.State.ENQUEUED, jobs.get(0).getState());
        assertEquals(TransferManifest.QUEUED, store.read(ID).state);
    }

    @Test public void resumedNotificationDoesNotRewriteOlderActionIdentity() throws Exception {
        TransferManifest first = store.read(ID);
        android.app.Notification original = TransferNotifications.build(context, first);
        assertEquals(Worker.Result.success(), stop(ID, false));
        TransferManifest paused = store.read(ID);
        TransferManifest resumed = store.write(paused.withProgress(
                TransferManifest.QUEUED, partial.length(), paused.retryCount, null, paused.entityTag));
        android.app.Notification replacement = TransferNotifications.build(context, resumed);
        android.content.Intent oldAction = org.robolectric.Shadows.shadowOf(
                original.actions[0].actionIntent).getSavedIntent();
        android.content.Intent newAction = org.robolectric.Shadows.shadowOf(
                replacement.actions[0].actionIntent).getSavedIntent();
        assertEquals(0L, oldAction.getLongExtra(TransferNotifications.EXTRA_CONTROL_GENERATION, -1L));
        assertEquals(1L, newAction.getLongExtra(TransferNotifications.EXTRA_CONTROL_GENERATION, -1L));
        assertNotEquals(oldAction.getData(), newAction.getData());
        org.json.JSONObject legacy = first.toJson();
        legacy.remove("controlGeneration");
        assertEquals(0L, TransferManifest.fromJson(legacy).controlGeneration);
        legacy.put("controlGeneration", -1L);
        try {
            TransferManifest.fromJson(legacy);
            fail("negative generation must not be accepted");
        } catch (org.json.JSONException expected) {
            // Invalid durable generation fails closed.
        }
    }

    @Test public void staleUserAndSystemProjectionsPreserveResumedManifest() throws Exception {
        assertEquals(Worker.Result.success(), stop(ID, false));
        TransferManifest paused = store.read(ID);
        TransferManifest resumed = store.write(paused.withProgress(
                TransferManifest.QUEUED, partial.length(), 0, null, null));
        TransferController controller = new TransferController(context);
        for (int reason : new int[] { androidx.work.WorkInfo.STOP_REASON_USER,
                androidx.work.WorkInfo.STOP_REASON_CONSTRAINT_CONNECTIVITY }) {
            assertTrue(controller.recordSchedulerStop(ID, reason, 0L));
            assertEquals(resumed.stateRevision, store.read(ID).stateRevision);
            assertEquals(TransferManifest.QUEUED, store.read(ID).state);
            assertFalse(store.read(ID).shouldReschedule());
        }
        assertFalse(controller.recordSchedulerStop(ID, androidx.work.WorkInfo.STOP_REASON_USER, -1L));
        assertEquals(resumed.stateRevision, store.read(ID).stateRevision);
        assertTrue(controller.recordSchedulerStop(ID,
                androidx.work.WorkInfo.STOP_REASON_USER, resumed.controlGeneration));
        assertEquals(TransferManifest.PAUSED, store.read(ID).state);
        assertTrue(store.read(ID).stopAcknowledged);
        assertEquals(1L, partial.length());
    }

    @Test public void staleEngineHandoffDoesNotOpenReplacementTransport() throws Exception {
        assertEquals(Worker.Result.success(), stop(ID, false));
        TransferManifest paused = store.read(ID);
        TransferManifest resumed = store.write(paused.withProgress(
                TransferManifest.QUEUED, partial.length(), 0, null, null));
        TransferEngine engine = new TransferEngine(context, store,
                ignored -> { throw new AssertionError("obsolete handoff opened transport"); },
                ignored -> {}, () -> 1_000L);
        assertEquals(TransferExecutionResult.SUCCESS, engine.run(ID, 0L,
                ignored -> fail("obsolete handoff must not publish progress")));
        assertEquals(resumed.stateRevision, store.read(ID).stateRevision);
        assertEquals(1L, partial.length());
        TransferRunControl next = TransferRunControl.begin(context, ID);
        assertNotNull("obsolete handoff must release only its own empty reservation", next);
        next.finish();
    }

    @Test public void cancelRetriesWithoutDeletingOwnedPartial() throws Exception {
        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
            assertNotNull(lease);
            assertEquals(Worker.Result.retry(), stop(ID, true));
            assertFalse(store.read(ID).stopAcknowledged);
            assertEquals(1L, partial.length());
        }
        assertEquals(Worker.Result.success(), stop(ID, true));
        assertTrue(store.read(ID).stopAcknowledged);
        assertFalse(partial.exists());
    }

    @Test public void missingOrUnsafeIdentityFailsWithoutChangingOwnedData() throws Exception {
        long revision = store.read(ID).stateRevision;
        assertEquals(Worker.Result.failure(), stop("missing-notification-job", true));
        assertEquals(Worker.Result.failure(), stop("../escape", true));
        assertEquals(revision, store.read(ID).stateRevision);
        assertEquals(1L, partial.length());
    }

    @Test public void corruptManifestRequiresRetryWithoutDeletingOrReplacingData() throws Exception {
        File manifestFile = new File(context.getFilesDir(), "transfers/" + ID + ".json");
        byte[] corrupt = "{invalid-manifest".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        Files.write(manifestFile.toPath(), corrupt);

        assertEquals(Worker.Result.retry(), stop(ID, true));
        assertArrayEquals(corrupt, Files.readAllBytes(manifestFile.toPath()));
        assertArrayEquals(new byte[] {112}, Files.readAllBytes(partial.toPath()));
    }

    @Test public void escapedPartialFailsWithoutDeletingEitherFile() throws Exception {
        File outside = new File(context.getCacheDir(), "stop-worker-outside.part");
        Files.write(outside.toPath(), new byte[] {115});
        try {
            store.delete(ID);
            store.write(new TransferManifest(ID, "job", "model", "owner/model",
                    "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                    outside.getAbsolutePath(), 3L, null, 1L, 0,
                    TransferManifest.QUEUED, null, null, 1L, 1L));

            assertEquals(Worker.Result.failure(), stop(ID, true));
            assertArrayEquals(new byte[] {115}, Files.readAllBytes(outside.toPath()));
            assertArrayEquals(new byte[] {112}, Files.readAllBytes(partial.toPath()));
            assertFalse(store.read(ID).stopAcknowledged);
        } finally {
            Files.deleteIfExists(outside.toPath());
        }
    }
}
