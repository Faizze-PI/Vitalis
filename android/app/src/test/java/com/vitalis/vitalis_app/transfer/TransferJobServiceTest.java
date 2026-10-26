package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.app.Notification;
import android.content.ClipData;
import android.net.Network;
import android.net.Uri;
import android.os.Bundle;
import android.os.IBinder;
import android.os.PersistableBundle;

import org.junit.Test;
import org.junit.Before;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ServiceController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.Implementation;
import org.robolectric.shadows.ShadowJobService;
import org.robolectric.util.ReflectionHelpers;

import java.io.File;
import java.nio.file.Files;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicLong;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class TransferJobServiceTest {
    @Test
    @Config(shadows = RecordingNotificationService.class)
    public void staleStopCallbackCannotStopResumedOwner() throws Exception {
        assertObsoleteStop(false);
    }

    @Test
    @Config(shadows = RecordingNotificationService.class)
    public void foreignTransferStopCallbackCannotStopOwner() throws Exception {
        assertObsoleteStop(true);
    }

    private void assertObsoleteStop(boolean foreignTransfer) throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-stale-stop";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        TransferManifestStore store = new TransferManifestStore(service);
        TransferManifest initial = new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 0L, 0, TransferManifest.PAUSED, null, null, 1L, 1L);
        TransferManifest resumed = initial.withProgress(TransferManifest.QUEUED, 0L, 0, null, null)
                .withStopRequest(false);
        store.write(resumed);
        JobParameters old = parameters(service, foreignTransfer ? identity + "-other" : identity);
        if (foreignTransfer) old.getExtras().putLong(
                TransferNotifications.EXTRA_CONTROL_GENERATION, resumed.controlGeneration);
        JobParameters current = parameters(service, identity);
        current.getExtras().putLong(TransferNotifications.EXTRA_CONTROL_GENERATION,
                resumed.controlGeneration);
        java.util.concurrent.atomic.AtomicBoolean obsoleteStopRejected =
                new java.util.concurrent.atomic.AtomicBoolean();
        RecordingNotificationService.beforeFirst = () ->
                obsoleteStopRejected.set(!service.onStopJob(old));
        try {
            assertTrue(service.onStartJob(current));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            for (Thread worker : active.values().toArray(new Thread[0])) {
                worker.join(10_000L);
                assertFalse(worker.isAlive());
            }
            assertTrue("obsolete scheduler stop must not address replacement owner",
                    obsoleteStopRejected.get());
            org.junit.Assert.assertEquals(resumed.controlGeneration,
                    store.read(identity).controlGeneration);
            assertTrue(active.isEmpty());
        } finally {
            RecordingNotificationService.beforeFirst = null;
            controller.destroy();
        }
    }

    @Test
    @Config(shadows = RecordingNotificationService.class)
    public void destructionDuringPublicationSettlesUnstartedOwnerWithoutEngine() throws Exception {
        assertInitializationWithoutEngine(true);
    }

    @Test
    public void staleServiceAdmissionDoesNotConstructEngine() throws Exception {
        assertInitializationWithoutEngine(false);
    }

    private void assertInitializationWithoutEngine(boolean destroyDuringPublication) throws Exception {
        java.util.concurrent.atomic.AtomicInteger engines = new java.util.concurrent.atomic.AtomicInteger();
        TransferJobService instance = new TransferJobService(context -> {
            engines.incrementAndGet();
            return new TransferEngine(context);
        });
        ServiceController<TransferJobService> controller = ServiceController.of(instance, null).create();
        TransferJobService service = controller.get();
        String identity = "service-initialization-boundary";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifestStore store = new TransferManifestStore(service);
        TransferManifest initial = new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.PAUSED, null, null, 1L, 1L);
        TransferManifest queued = destroyDuringPublication
                ? new TransferManifest(identity, "job", "model", "owner/model",
                        initial.revision, initial.sourceUrl, partial.getPath(), 3L, null,
                        1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L)
                : initial.withProgress(TransferManifest.QUEUED, 1L, 0, null, null);
        TransferManifest saved = store.write(queued);
        JobParameters params = parameters(service, identity);
        if (destroyDuringPublication) RecordingNotificationService.beforeFirst = controller::destroy;
        try {
            org.junit.Assert.assertEquals(!destroyDuringPublication, service.onStartJob(params));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            for (Thread worker : active.values().toArray(new Thread[0])) {
                worker.join(10_000L);
                assertFalse("initialization owner must settle", worker.isAlive());
            }
            assertTrue(active.isEmpty());
            org.junit.Assert.assertEquals(0, engines.get());
            org.junit.Assert.assertEquals(1L, partial.length());
            if (destroyDuringPublication) {
                assertTrue(store.read(identity).shouldReschedule());
                assertFalse(org.robolectric.Shadows.shadowOf(service).getIsJobFinished());
                assertFalse(service.onStartJob(params));
            } else {
                org.junit.Assert.assertEquals(saved.stateRevision, store.read(identity).stateRevision);
                org.junit.Assert.assertEquals(TransferManifest.QUEUED, store.read(identity).state);
                assertTrue(org.robolectric.Shadows.shadowOf(service).getIsJobFinished());
            }
        } finally {
            RecordingNotificationService.beforeFirst = null;
            if (!destroyDuringPublication) controller.destroy();
        }
    }

    @Test
    @Config(shadows = RecordingNotificationService.class)
    public void publicationReentryCannotAcquireUnstartedOwner() throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-notification-reentry";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 0L, 0, TransferManifest.PAUSED, null, null, 1L, 1L));
        JobParameters params = parameters(service, identity);
        RecordingNotificationService.beforeFirst = () -> assertFalse(service.onStartJob(params));
        try {
            assertTrue(service.onStartJob(params));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            for (Thread worker : active.values().toArray(new Thread[0])) {
                worker.join(10_000L);
                assertFalse("owned initialization must settle", worker.isAlive());
            }
            org.junit.Assert.assertEquals(1, RecordingNotificationService.calls.get());
            assertTrue(active.isEmpty());
            org.junit.Assert.assertEquals(TransferManifest.PAUSED, store.read(identity).state);
        } finally {
            RecordingNotificationService.beforeFirst = null;
            controller.destroy();
        }
    }

    @Test
    @Config(shadows = RejectingNotificationService.class)
    public void lateNotificationFailureCannotFailResumedGeneration() throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-rejection-resumed";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        AtomicLong replacementRevision = new AtomicLong();
        RejectingNotificationService.beforeReject = () -> {
            try {
                new TransferController(service).stop(identity, false);
                TransferManifest paused = store.read(identity);
                TransferManifest replacement = store.write(paused.withProgress(
                        TransferManifest.QUEUED, partial.length(), 0, null, null));
                replacementRevision.set(replacement.stateRevision);
            } catch (Exception failure) { throw new AssertionError(failure); }
        };
        try {
            assertFalse(service.onStartJob(parameters(service, identity)));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            for (Thread worker : active.values().toArray(new Thread[0])) {
                worker.join(10_000L);
                assertFalse(worker.isAlive());
            }
            org.junit.Assert.assertEquals(TransferManifest.QUEUED, store.read(identity).state);
            org.junit.Assert.assertEquals(replacementRevision.get(), store.read(identity).stateRevision);
            org.junit.Assert.assertEquals(1L, partial.length());
        } finally {
            RejectingNotificationService.beforeReject = null;
            controller.destroy();
        }
    }

    @Test
    public void destructionDuringPausedCleanupRetainsOwnerAndStopIntent() throws Exception {
        TransferEngineTest.BlockingReadConnection connection = new TransferEngineTest.BlockingReadConnection();
        connection.holdCleanup = true;
        TransferJobService instance = new TransferJobService(context -> new TransferEngine(
                context, new TransferManifestStore(context), ignored -> connection,
                ignored -> {}, () -> 1_000L));
        ServiceController<TransferJobService> controller = ServiceController.of(instance, null).create();
        TransferJobService service = controller.get();
        String identity = "service-destroy-cleanup";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        JobParameters params = parameters(service, identity);
        ReflectionHelpers.setField(params, "mStopReason", JobParameters.STOP_REASON_USER);
        Thread worker = null;
        boolean destroyed = false;
        try {
            assertTrue(service.onStartJob(params));
            assertTrue(connection.readEntered.await(10, TimeUnit.SECONDS));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            worker = active.get(params.getJobId());
            org.junit.Assert.assertNotNull(worker);
            assertFalse(service.onStopJob(params));
            assertTrue(connection.cleanupEntered.await(10, TimeUnit.SECONDS));
            controller.destroy();
            destroyed = true;
            org.junit.Assert.assertSame(worker, active.get(params.getJobId()));
            assertTrue(worker.isAlive());
            assertFalse(store.read(identity).stopAcknowledged);
            assertTrue(partial.isFile());
            assertFalse(service.onStartJob(params));
            assertFalse("destruction must not interrupt cleanup a second time",
                    connection.cleanupInterrupted.await(200, TimeUnit.MILLISECONDS));
            org.junit.Assert.assertEquals(1, connection.disconnectCalls.get());
            assertFalse(org.robolectric.Shadows.shadowOf(service).getIsJobFinished());
        } finally {
            connection.release.countDown();
            connection.cleanupRelease.countDown();
            if (worker != null) {
                worker.join(10_000L);
                assertFalse("fixture worker must terminate", worker.isAlive());
            }
            if (!destroyed) controller.destroy();
        }
        TransferManifest stopped = store.read(identity);
        org.junit.Assert.assertEquals(TransferManifest.PAUSED, stopped.state);
        assertTrue(stopped.stopAcknowledged);
        assertFalse(stopped.shouldReschedule());
        org.junit.Assert.assertEquals(1L, partial.length());
        Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
        assertTrue(active.isEmpty());
    }

    @Test
    public void userJobStopWakesUninterruptibleReadAndAcknowledgesPause() throws Exception {
        assertJobStopWakesRead(JobParameters.STOP_REASON_USER, false);
    }

    @Test
    public void systemJobStopWakesUninterruptibleReadAndKeepsResumablePartial() throws Exception {
        assertJobStopWakesRead(JobParameters.STOP_REASON_UNDEFINED, true);
    }

    @Test
    public void serviceDestructionStopsOwnedReadAndKeepsResumablePartial() throws Exception {
        assertJobStopWakesRead(JobParameters.STOP_REASON_UNDEFINED, true, true);
    }

    @Test
    @Config(shadows = RecordingNotificationService.class)
    public void rejectedDuplicateDoesNotReplaceOwnersNotification() throws Exception {
        assertJobStopWakesRead(JobParameters.STOP_REASON_USER, false, false, true);
    }

    private void assertJobStopWakesRead(int reason, boolean expectedRetry) throws Exception {
        assertJobStopWakesRead(reason, expectedRetry, false);
    }

    private void assertJobStopWakesRead(int reason, boolean expectedRetry, boolean destroy) throws Exception {
        assertJobStopWakesRead(reason, expectedRetry, destroy, false);
    }

    private void assertJobStopWakesRead(int reason, boolean expectedRetry, boolean destroy,
                                       boolean tryDuplicate) throws Exception {
        TransferEngineTest.BlockingReadConnection connection =
                new TransferEngineTest.BlockingReadConnection();
        TransferJobService instance = new TransferJobService(context -> new TransferEngine(
                context, new TransferManifestStore(context), ignored -> connection,
                ignored -> {}, () -> 1_000L));
        ServiceController<TransferJobService> controller = ServiceController.of(instance, null).create();
        TransferJobService service = controller.get();
        String identity = "service-blocked-read";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 1L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        JobParameters params = parameters(service, identity);
        ReflectionHelpers.setField(params, "mStopReason", reason);
        Thread worker = null;
        boolean destroyed = false;
        try {
            assertTrue(service.onStartJob(params));
            assertTrue(connection.readEntered.await(10, TimeUnit.SECONDS));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            worker = active.get(params.getJobId());
            org.junit.Assert.assertNotNull(worker);
            if (tryDuplicate) {
                int calls = RecordingNotificationService.calls.get();
                assertFalse(service.onStartJob(params));
                org.junit.Assert.assertEquals("rejected callback must not publish a notification",
                        calls, RecordingNotificationService.calls.get());
                org.junit.Assert.assertSame(worker, active.get(params.getJobId()));
                assertFalse(connection.disconnected);
            }
            if (destroy) {
                controller.destroy();
                destroyed = true;
            } else {
                org.junit.Assert.assertEquals(expectedRetry, service.onStopJob(params));
            }
            worker.join(1_000L);
            assertFalse("job stop did not wake the owned transport", worker.isAlive());
            assertTrue(connection.disconnected);
            if (destroy) assertFalse("destroyed service must reject new jobs", service.onStartJob(params));
        } finally {
            connection.release.countDown();
            connection.cleanupRelease.countDown();
            if (worker != null) {
                worker.join(10_000L);
                assertFalse("fixture worker must terminate", worker.isAlive());
            }
            if (!destroyed) controller.destroy();
        }
        TransferManifest stopped = store.read(identity);
        org.junit.Assert.assertEquals(expectedRetry, stopped.shouldReschedule());
        if (!expectedRetry) {
            org.junit.Assert.assertEquals(TransferManifest.PAUSED, stopped.state);
            assertTrue(stopped.stopAcknowledged);
        }
        org.junit.Assert.assertEquals(1L, partial.length());
        assertFalse(org.robolectric.Shadows.shadowOf(service).getIsJobFinished());
    }

    @Test
    public void stopDuringBlockedInitializationReturnsBeforeStorageAndCannotFinishLate() throws Exception {
        assertStopDuringBlockedInitialization(JobParameters.STOP_REASON_CONSTRAINT_CONNECTIVITY, true);
    }

    @Test
    public void userStopDuringBlockedInitializationPausesWithoutReschedule() throws Exception {
        assertStopDuringBlockedInitialization(JobParameters.STOP_REASON_USER, false);
    }

    @Test
    public void appStopDuringBlockedInitializationPausesWithoutReschedule() throws Exception {
        assertStopDuringBlockedInitialization(JobParameters.STOP_REASON_CANCELLED_BY_APP, false);
    }

    private void assertStopDuringBlockedInitialization(int reason, boolean expectedRetry) throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-stop-storage";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "ok".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 2L, null, 0L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        JobParameters params = parameters(service, identity);
        ReflectionHelpers.setField(params, "mStopReason", reason);
        CountDownLatch locked = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<?> holder = executor.submit(() -> {
            try {
                store.update(identity, current -> {
                    locked.countDown();
                    if (!release.await(10, TimeUnit.SECONDS)) throw new AssertionError("fixture release missing");
                    return current;
                });
            } catch (Exception failure) {
                throw new AssertionError(failure);
            }
        });
        Future<Boolean> stop = null;
        Thread worker = null;
        try {
            assertTrue(locked.await(10, TimeUnit.SECONDS));
            assertTrue(service.onStartJob(params));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            worker = active.get(params.getJobId());
            org.junit.Assert.assertNotNull(worker);
            stop = executor.submit(() -> service.onStopJob(params));
            try {
                org.junit.Assert.assertEquals(expectedRetry, stop.get(1, TimeUnit.SECONDS));
                org.junit.Assert.assertSame(worker, active.get(params.getJobId()));
                org.junit.Assert.assertEquals(expectedRetry, service.onStopJob(params));
                assertFalse("competing startup must not replace cleanup owner", service.onStartJob(params));
                org.junit.Assert.assertSame(worker, active.get(params.getJobId()));
            } catch (TimeoutException blocked) {
                fail("job stop callback waited for manifest storage ownership");
            }
        } finally {
            release.countDown();
            try {
                holder.get(10, TimeUnit.SECONDS);
                if (stop != null) stop.get(10, TimeUnit.SECONDS);
                if (worker != null) {
                    worker.join(10_000L);
                    assertFalse("stopped initialization must terminate", worker.isAlive());
                }
                org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle();
            } finally {
                executor.shutdownNow();
                executor.awaitTermination(10, TimeUnit.SECONDS);
                controller.destroy();
            }
        }
        TransferManifest stopped = store.read(identity);
        org.junit.Assert.assertEquals(expectedRetry, stopped.shouldReschedule());
        if (!expectedRetry) {
            org.junit.Assert.assertEquals(TransferManifest.PAUSED, stopped.state);
            assertTrue(stopped.stopAcknowledged);
        }
        org.junit.Assert.assertEquals("ok", new String(Files.readAllBytes(partial.toPath()),
                java.nio.charset.StandardCharsets.UTF_8));
        assertFalse(org.robolectric.Shadows.shadowOf(service).getIsJobFinished());
    }

    @Before
    public void resetPlatformFaults() {
        RejectingNotificationService.beforeReject = null;
        RecordingNotificationService.first = null;
        RecordingNotificationService.calls.set(0);
        RecordingNotificationService.beforeFirst = null;
    }

    @Implements(JobService.class)
    public static class RecordingNotificationService extends ShadowJobService {
        static volatile Notification first;
        static final java.util.concurrent.atomic.AtomicInteger calls = new java.util.concurrent.atomic.AtomicInteger();
        static Runnable beforeFirst;

        @Implementation
        protected void setNotification(JobParameters parameters, int id,
                                       Notification notification, int policy) {
            if (calls.incrementAndGet() == 1 && beforeFirst != null) beforeFirst.run();
            if (first == null) first = notification;
        }
    }

    @Implements(JobService.class)
    public static class RejectingNotificationService extends ShadowJobService {
        static Runnable beforeReject;

        @Implementation
        protected void setNotification(JobParameters parameters, int id,
                                       Notification notification, int policy) {
            if (beforeReject != null) beforeReject.run();
            throw new SecurityException("fixture notification rejected");
        }
    }

    @Test
    @Config(shadows = RejectingNotificationService.class)
    public void lateNotificationFailureCannotOverwriteAcknowledgedCancellation() throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-rejection-cancel";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "ok".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 2L, null, 2L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        AtomicLong cancellationRevision = new AtomicLong();
        RejectingNotificationService.beforeReject = () -> {
            try {
                new TransferController(service).stop(identity, true);
                cancellationRevision.set(store.read(identity).stateRevision);
            } catch (Exception failure) {
                throw new AssertionError(failure);
            }
        };
        try {
            assertFalse(service.onStartJob(parameters(service, identity)));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            for (Thread worker : active.values().toArray(new Thread[0])) {
                worker.join(10_000L);
                assertFalse("failure projection must finish", worker.isAlive());
            }
            TransferManifest cancelled = store.read(identity);
            org.junit.Assert.assertEquals(TransferManifest.CANCELLED, cancelled.state);
            assertTrue(cancelled.stopAcknowledged);
            org.junit.Assert.assertEquals("none", cancelled.failureCode);
            org.junit.Assert.assertEquals(cancellationRevision.get(), cancelled.stateRevision);
            assertFalse(partial.exists());
        } finally {
            RejectingNotificationService.beforeReject = null;
            controller.destroy();
        }
    }

    @Test
    @Config(shadows = RejectingNotificationService.class)
    public void rejectedInitialNotificationPersistsTypedFailureAndPreservesPartial() throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-notification-rejected";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "ok".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 2L, null, 2L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        try {
            assertFalse(service.onStartJob(parameters(service, identity)));
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            for (Thread worker : active.values().toArray(new Thread[0])) {
                worker.join(10_000L);
                assertFalse("failure projection must finish", worker.isAlive());
            }
            org.junit.Assert.assertEquals(TransferManifest.FAILED, store.read(identity).state);
            org.junit.Assert.assertEquals("foreground_promotion_failed", store.read(identity).failureCode);
            org.junit.Assert.assertEquals("ok", new String(Files.readAllBytes(partial.toPath()),
                    java.nio.charset.StandardCharsets.UTF_8));
        } finally {
            controller.destroy();
        }
    }

    @Test
    public void legacyJobWithoutNotificationIdentityKeepsItsResumableManifestAndPartial() throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-legacy";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "ok".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        TransferManifestStore store = new TransferManifestStore(service);
        TransferManifest queued = store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 2L, null, 2L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
        JobParameters params = parameters(service, identity);
        params.getExtras().remove(TransferScheduler.INPUT_NOTIFICATION_ID);
        try {
            assertFalse(service.onStartJob(params));
            org.junit.Assert.assertEquals(queued.stateRevision, store.read(identity).stateRevision);
            org.junit.Assert.assertEquals(TransferManifest.QUEUED, store.read(identity).state);
            org.junit.Assert.assertEquals("ok", new String(Files.readAllBytes(partial.toPath()),
                    java.nio.charset.StandardCharsets.UTF_8));
        } finally {
            controller.destroy();
        }
    }

    @Test
    @Config(shadows = RecordingNotificationService.class)
    public void startupCallbackDoesNotWaitForManifestStorageOwnership() throws Exception {
        assertStartupReturnsWhileStorageHeld(true);
    }

    @Test
    @Config(shadows = RejectingNotificationService.class)
    public void rejectedNotificationCallbackDoesNotWaitForFailureProjectionStorage() throws Exception {
        assertStartupReturnsWhileStorageHeld(false);
    }

    private void assertStartupReturnsWhileStorageHeld(boolean expectedActive) throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        String identity = "service-start-storage";
        File partial = new File(service.getFilesDir(), "models/" + identity + ".gguf.part");
        TransferManifestStore store = new TransferManifestStore(service);
        TransferManifest initial = new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 2L, null, 0L, 0, TransferManifest.QUEUED, null, null, 1L, 1L);
        store.write(expectedActive ? initial.withStopRequest(true) : initial);
        CountDownLatch locked = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<?> holder = executor.submit(() -> {
            try {
                store.update(identity, current -> {
                    locked.countDown();
                    if (!release.await(10, TimeUnit.SECONDS)) {
                        throw new AssertionError("fixture storage release missing");
                    }
                    return current;
                });
            } catch (Exception failure) {
                throw new AssertionError(failure);
            }
        });
        Future<Boolean> startup = null;
        try {
            assertTrue(locked.await(10, TimeUnit.SECONDS));
            JobParameters params = parameters(service, identity);
            startup = executor.submit(() -> service.onStartJob(params));
            try {
                org.junit.Assert.assertEquals(expectedActive, startup.get(1, TimeUnit.SECONDS));
                if (expectedActive) {
                    org.junit.Assert.assertNotNull(RecordingNotificationService.first);
                    assertTrue(RecordingNotificationService.first.extras.getBoolean(
                            Notification.EXTRA_PROGRESS_INDETERMINATE));
                    org.junit.Assert.assertEquals(identity, org.robolectric.Shadows.shadowOf(
                            RecordingNotificationService.first.actions[1].actionIntent)
                            .getSavedIntent().getStringExtra(TransferNotifications.EXTRA_TRANSFER_ID));
                }
            } catch (TimeoutException blocked) {
                fail("job startup callback waited for manifest storage ownership");
            }
        } finally {
            release.countDown();
            try {
                holder.get(10, TimeUnit.SECONDS);
                if (startup != null) startup.get(10, TimeUnit.SECONDS);
                Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
                for (Thread worker : active.values().toArray(new Thread[0])) {
                    worker.join(10_000L);
                    assertFalse("test-owned worker must terminate", worker.isAlive());
                }
            } finally {
                executor.shutdownNow();
                executor.awaitTermination(10, TimeUnit.SECONDS);
                controller.destroy();
            }
        }
        if (!expectedActive) {
            org.junit.Assert.assertEquals(TransferManifest.FAILED, store.read(identity).state);
            org.junit.Assert.assertEquals("foreground_promotion_failed", store.read(identity).failureCode);
        }
    }

    @Test
    public void asynchronousCancellationCleanupReportsActiveJobNotReschedulePolicy() throws Exception {
        ServiceController<TransferJobService> controller =
                Robolectric.buildService(TransferJobService.class).create();
        TransferJobService service = controller.get();
        File partial = new File(service.getFilesDir(), "models/service-cancel.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "ok".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        TransferManifestStore store = new TransferManifestStore(service);
        store.write(new TransferManifest("service-cancel", "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 2L, null, 2L, 0, TransferManifest.QUEUED, null, null, 1L, 1L)
                .withStopRequest(true));
        try {
            assertTrue("starting asynchronous cleanup must keep the job active",
                    service.onStartJob(parameters(service, "service-cancel")));
        } finally {
            Map<Integer, Thread> active = ReflectionHelpers.getField(service, "active");
            for (Thread worker : active.values().toArray(new Thread[0])) {
                worker.join(10_000L);
                assertFalse("test-owned worker must terminate", worker.isAlive());
            }
            controller.destroy();
        }
        assertTrue(store.read("service-cancel").stopAcknowledged);
        assertFalse(partial.exists());
    }

    private JobParameters parameters(TransferJobService service, String transferId) throws Exception {
        PersistableBundle extras = new PersistableBundle();
        extras.putString(TransferScheduler.INPUT_TRANSFER_ID, transferId);
        extras.putInt(TransferScheduler.INPUT_NOTIFICATION_ID,
                TransferNotifications.id(service, transferId));
        return JobParameters.class.getDeclaredConstructor(IBinder.class, String.class, int.class,
                PersistableBundle.class, Bundle.class, ClipData.class, int.class,
                boolean.class, boolean.class, boolean.class, Uri[].class, String[].class, Network.class)
                .newInstance(null, "vitalis_model_transfers", 7001, extras, Bundle.EMPTY,
                        null, 0, false, false, true, null, null, null);
    }
}
