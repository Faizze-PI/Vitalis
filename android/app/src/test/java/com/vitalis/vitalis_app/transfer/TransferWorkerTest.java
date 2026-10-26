package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import androidx.work.Data;
import androidx.work.Worker;
import androidx.work.testing.TestWorkerBuilder;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public final class TransferWorkerTest {
    @org.junit.After public void closeWorkDatabase() {
        androidx.work.testing.WorkManagerTestInitHelper.closeWorkDatabase();
    }

    @Test
    @Config(sdk = 34)
    public void startupFailuresPersistTypedCodesWithoutChangingPartialBytes() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferManifestStore store = new TransferManifestStore(context);
        for (boolean security : new boolean[] {true, false}) {
            String identity = security ? "worker-security-failure" : "worker-initialization-failure";
            java.io.File partial = new java.io.File(context.getFilesDir(), "models/" + identity + ".part");
            java.nio.file.Files.createDirectories(partial.getParentFile().toPath());
            java.nio.file.Files.write(partial.toPath(), new byte[] {112});
            store.write(new TransferManifest(identity, "job", "model", "owner/model",
                    "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                    partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
            TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                    .setInputData(new Data.Builder().putString(TransferScheduler.INPUT_TRANSFER_ID, identity).build())
                    .setWorkerFactory(new androidx.work.WorkerFactory() {
                        @Override public androidx.work.ListenableWorker createWorker(
                                Context app, String name, androidx.work.WorkerParameters parameters) {
                            return new TransferWorker(app, parameters, ignored -> {
                                if (security) throw new SecurityException("private fixture detail");
                                throw new IllegalStateException("private fixture detail");
                            });
                        }
                    })
                    .setForegroundUpdater((ignored, id, info) ->
                            com.google.common.util.concurrent.Futures.immediateFuture(null)).build();

            assertEquals(Worker.Result.failure(), worker.doWork());
            assertEquals(security ? "security_rejected" : "transfer_exception", store.read(identity).failureCode);
            assertEquals(TransferManifest.FAILED, store.read(identity).state);
            org.junit.Assert.assertArrayEquals(new byte[] {112}, java.nio.file.Files.readAllBytes(partial.toPath()));
            org.junit.Assert.assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("VitalisTransfer").stream()
                    .noneMatch(entry -> entry.msg.contains("private fixture detail")));
        }
    }

    @Test
    public void latePromotionFailureDoesNotFailResumedTransfer() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(context);
        String identity = "worker-stale-failure";
        java.io.File partial = new java.io.File(context.getFilesDir(), "models/stale-failure.gguf.part");
        TransferManifestStore store = new TransferManifestStore(context);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 0L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        java.util.concurrent.atomic.AtomicLong replacementRevision = new java.util.concurrent.atomic.AtomicLong();
        TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                .setInputData(new Data.Builder().putString(TransferScheduler.INPUT_TRANSFER_ID, identity).build())
                .setForegroundUpdater((ignored, id, info) -> {
                    try {
                        new TransferController(context).stop(identity, false);
                        TransferManifest paused = store.read(identity);
                        TransferManifest resumed = store.write(paused.withProgress(
                                TransferManifest.QUEUED, 0L, 0, null, null));
                        replacementRevision.set(resumed.stateRevision);
                    } catch (Exception failure) { throw new AssertionError(failure); }
                    return com.google.common.util.concurrent.Futures.immediateFailedFuture(
                            new SecurityException("fixture promotion denied"));
                }).build();
        assertEquals(Worker.Result.failure(), worker.doWork());
        assertEquals(TransferManifest.QUEUED, store.read(identity).state);
        assertEquals(replacementRevision.get(), store.read(identity).stateRevision);
    }

    @Test
    public void staleWorkerDoesNotPromoteOrStartReplacementTransfer() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        String identity = "worker-stale-admission";
        java.io.File partial = new java.io.File(context.getFilesDir(), "models/stale-admission.gguf.part");
        TransferManifestStore store = new TransferManifestStore(context);
        TransferManifest paused = new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 0L, 0, TransferManifest.PAUSED, null, null, 1L, 1L);
        TransferManifest resumed = store.write(paused.withProgress(TransferManifest.QUEUED, 0L, 0, null, null));
        TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                .setInputData(new Data.Builder().putString(TransferScheduler.INPUT_TRANSFER_ID, identity)
                        .putLong(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L).build())
                .setForegroundUpdater((ignored, id, info) -> {
                    org.junit.Assert.fail("obsolete Worker must not promote replacement work");
                    return com.google.common.util.concurrent.Futures.immediateFuture(null);
                }).build();
        assertEquals(Worker.Result.success(), worker.doWork());
        assertEquals(resumed.stateRevision, store.read(identity).stateRevision);
        assertEquals(TransferManifest.QUEUED, store.read(identity).state);
    }

    @Test
    public void oldWorkerStopProjectionCannotPauseResumedTransfer() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(context);
        String identity = "worker-stale-projection";
        java.io.File partial = new java.io.File(context.getFilesDir(), "models/stale-projection.gguf.part");
        java.nio.file.Files.createDirectories(partial.getParentFile().toPath());
        java.nio.file.Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifestStore store = new TransferManifestStore(context);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        java.util.concurrent.atomic.AtomicReference<TransferWorker> owner = new java.util.concurrent.atomic.AtomicReference<>();
        java.util.concurrent.atomic.AtomicLong resumedRevision = new java.util.concurrent.atomic.AtomicLong();
        TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                .setInputData(new Data.Builder().putString(TransferScheduler.INPUT_TRANSFER_ID, identity)
                        .putLong(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L).build())
                .setForegroundUpdater((ignored, id, info) -> {
                    owner.get().stop(androidx.work.WorkInfo.STOP_REASON_USER);
                    Thread.interrupted(); // Consume the fixture's self-interrupt before durable setup.
                    try {
                        new TransferController(context).stop(identity, false);
                        TransferManifest paused = store.read(identity);
                        assertEquals(true, paused.stopAcknowledged);
                        TransferManifest resumed = store.write(paused.withProgress(
                                TransferManifest.QUEUED, partial.length(), 0, null, null));
                        resumedRevision.set(resumed.stateRevision);
                    } catch (Exception failure) { throw new AssertionError(failure); }
                    return com.google.common.util.concurrent.Futures.immediateFuture(null);
                }).build();
        owner.set(worker);
        assertEquals(Worker.Result.retry(), worker.doWork());
        assertEquals(TransferManifest.QUEUED, store.read(identity).state);
        assertEquals(resumedRevision.get(), store.read(identity).stateRevision);
        assertEquals(1L, partial.length());
    }

    @Test
    public void stopDuringForegroundPromotionDoesNotStartEngine() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        String identity = "worker-promotion-stop";
        java.io.File partial = new java.io.File(context.getFilesDir(), "models/worker-promotion.gguf.part");
        java.nio.file.Files.createDirectories(partial.getParentFile().toPath());
        java.nio.file.Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifestStore store = new TransferManifestStore(context);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        java.util.concurrent.CountDownLatch promotionEntered = new java.util.concurrent.CountDownLatch(1);
        com.google.common.util.concurrent.SettableFuture<Void> promotion =
                com.google.common.util.concurrent.SettableFuture.create();
        TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                .setInputData(new Data.Builder().putString(TransferScheduler.INPUT_TRANSFER_ID, identity).build())
                .setWorkerFactory(new androidx.work.WorkerFactory() {
                    @Override public androidx.work.ListenableWorker createWorker(
                            Context app, String name, androidx.work.WorkerParameters parameters) {
                        return new TransferWorker(app, parameters, ignored -> {
                            throw new AssertionError("stopped promotion must not start the engine");
                        });
                    }
                })
                .setForegroundUpdater((ignored, id, info) -> {
                    promotionEntered.countDown();
                    return promotion;
                })
                .build();
        java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newSingleThreadExecutor();
        java.util.concurrent.Future<Worker.Result> result = executor.submit(() -> {
            try { return worker.doWork(); }
            finally { Thread.interrupted(); }
        });
        try {
            org.junit.Assert.assertTrue(promotionEntered.await(10, java.util.concurrent.TimeUnit.SECONDS));
            worker.stop(androidx.work.WorkInfo.STOP_REASON_CONSTRAINT_CONNECTIVITY);
            assertEquals(Worker.Result.retry(), result.get(1, java.util.concurrent.TimeUnit.SECONDS));
            org.junit.Assert.assertTrue(store.read(identity).shouldReschedule());
            assertEquals("system_stop_" + androidx.work.WorkInfo.STOP_REASON_UNKNOWN,
                    store.read(identity).stopReason);
            assertEquals(1L, partial.length());
        } finally {
            promotion.set(null);
            executor.shutdownNow();
            org.junit.Assert.assertTrue(executor.awaitTermination(10, java.util.concurrent.TimeUnit.SECONDS));
        }
    }

    @Test
    public void systemStopWakesOwnedReadAndPreservesResumableData() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        String identity = "worker-blocked-read";
        java.io.File partial = new java.io.File(context.getFilesDir(), "models/worker-blocked.gguf.part");
        java.nio.file.Files.createDirectories(partial.getParentFile().toPath());
        java.nio.file.Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifestStore store = new TransferManifestStore(context);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        TransferEngineTest.BlockingReadConnection connection = new TransferEngineTest.BlockingReadConnection();
        TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                .setInputData(new Data.Builder().putString(TransferScheduler.INPUT_TRANSFER_ID, identity).build())
                .setWorkerFactory(new androidx.work.WorkerFactory() {
                    @Override public androidx.work.ListenableWorker createWorker(
                            Context app, String name, androidx.work.WorkerParameters parameters) {
                        return new TransferWorker(app, parameters, current -> new TransferEngine(
                                current, new TransferManifestStore(current), ignored -> connection,
                                ignored -> {}, () -> 1_000L));
                    }
                })
                .setForegroundUpdater((ignored, id, info) ->
                        com.google.common.util.concurrent.Futures.immediateFuture(null))
                .build();
        java.util.concurrent.ExecutorService executor = java.util.concurrent.Executors.newSingleThreadExecutor();
        java.util.concurrent.Future<Worker.Result> result = executor.submit(() -> {
            try { return worker.doWork(); }
            finally { Thread.interrupted(); }
        });
        try {
            org.junit.Assert.assertTrue(connection.readEntered.await(10, java.util.concurrent.TimeUnit.SECONDS));
            worker.stop(androidx.work.WorkInfo.STOP_REASON_CONSTRAINT_CONNECTIVITY);
            try {
                assertEquals(Worker.Result.retry(), result.get(1, java.util.concurrent.TimeUnit.SECONDS));
            } catch (java.util.concurrent.TimeoutException blocked) {
                org.junit.Assert.fail("Worker stop did not wake its owned transport");
            }
            org.junit.Assert.assertTrue(connection.disconnected);
        } finally {
            connection.release.countDown();
            connection.cleanupRelease.countDown();
            try { result.get(10, java.util.concurrent.TimeUnit.SECONDS); }
            finally {
                executor.shutdownNow();
                org.junit.Assert.assertTrue(executor.awaitTermination(10, java.util.concurrent.TimeUnit.SECONDS));
            }
        }
        org.junit.Assert.assertTrue(store.read(identity).shouldReschedule());
        assertEquals(1L, partial.length());
    }

    @Test
    public void missingTransferIdentityFailsWithoutForegroundPromotion() {
        Context context = ApplicationProvider.getApplicationContext();
        TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                .setForegroundUpdater((ignored, id, info) -> {
                    throw new AssertionError("missing identity must not promote foreground work");
                })
                .build();
        assertEquals(Worker.Result.failure(), worker.doWork());
    }

    @Test
    public void absentManifestFailsWithoutCreatingTransferState() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        String identity = "worker-missing-record";
        TransferManifestStore store = new TransferManifestStore(context);
        store.delete(identity);
        TransferWorker worker = TestWorkerBuilder.from(context, TransferWorker.class, Runnable::run)
                .setInputData(new Data.Builder().putString(TransferScheduler.INPUT_TRANSFER_ID, identity).build())
                .setForegroundUpdater((ignored, id, info) -> {
                    throw new AssertionError("missing manifest must not promote foreground work");
                })
                .build();
        assertEquals(Worker.Result.failure(), worker.doWork());
        org.junit.Assert.assertNull(store.read(identity));
    }
}
