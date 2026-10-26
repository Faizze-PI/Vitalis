package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.core.app.ApplicationProvider;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.file.Files;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Queue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class TransferEngineTest {
    private Context context;
    private TransferManifestStore store;
    private File partial;

    @Before
    public void setUp() throws Exception {
        context = ApplicationProvider.getApplicationContext();
        store = new TransferManifestStore(context);
        partial = new File(context.getFilesDir(), "models/engine-test.gguf.part");
        if (partial.isFile()) assertTrue(partial.delete());
        store.delete("engine-test");
    }

    @Test
    public void recoveryRejectsAnotherJobWithoutChangingStopStateOrPartial() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        TransferManifest before = store.write(manifest(3L, null).withStopRequest(true));
        try {
            new TransferController(context).recoverStop("engine-test", "another-job");
            org.junit.Assert.fail("recovery must verify the durable job owner");
        } catch (SecurityException expected) {
            // Rejection must precede cleanup or manifest projection.
        }
        assertEquals(before.stateRevision, store.read("engine-test").stateRevision);
        assertTrue(partial.isFile());
        org.junit.Assert.assertFalse(store.read("engine-test").stopAcknowledged);
    }

    @Test
    public void failedExplicitRecoveryPreservesPartialAndRuntimeQuarantine() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        store.write(manifest(3L, null));
        AtomicInteger closeAttempts = new AtomicInteger();
        TransferEngine engine = new TransferEngine(context, store, ignored ->
                new HttpURLConnection(new URL("https://huggingface.co/test")) {
                    @Override public int getResponseCode() { return 503; }
                    @Override public void disconnect() {
                        closeAttempts.incrementAndGet();
                        throw new IllegalStateException("close still failed");
                    }
                    @Override public boolean usingProxy() { return false; }
                    @Override public void connect() {}
                }, ignored -> {}, () -> 1_000L);
        engine.run("engine-test", ignored -> {});
        TransferController controller = new TransferController(context);
        controller.stop("engine-test", true);
        try {
            controller.recoverStop("engine-test", "job");
            org.junit.Assert.fail("failed cleanup must not report recovery success");
        } catch (java.util.concurrent.ExecutionException expected) {
            assertTrue(expected.getCause() != null);
        }
        assertEquals(2, closeAttempts.get());
        assertTrue(partial.isFile());
        org.junit.Assert.assertFalse(store.read("engine-test").stopAcknowledged);
        assertEquals(TransferExecutionResult.RETRY,
                engine.run("engine-test", ignored -> {}));
        assertEquals(2, closeAttempts.get());
    }

    @Test
    public void explicitChannelRecoveryClosesQuarantinedConnectionBeforeCancelCleanup() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        store.write(manifest(3L, null));
        AtomicInteger closeAttempts = new AtomicInteger();
        TransferEngine engine = new TransferEngine(context, store, ignored ->
                new HttpURLConnection(new URL("https://huggingface.co/test")) {
                    @Override public int getResponseCode() { return 503; }
                    @Override public void disconnect() {
                        if (closeAttempts.incrementAndGet() == 1) {
                            throw new IllegalStateException("first close failed");
                        }
                    }
                    @Override public boolean usingProxy() { return false; }
                    @Override public void connect() {}
                }, ignored -> {}, () -> 1_000L);
        engine.run("engine-test", ignored -> {});
        TransferController controller = new TransferController(context);
        controller.stop("engine-test", true);
        org.junit.Assert.assertFalse(store.read("engine-test").stopAcknowledged);
        assertEquals("quarantined cleanup must be exposed to the recovery client",
                true, controller.status("engine-test").get("recoveryRequired"));
        TransferChannelTest.Messenger messenger = new TransferChannelTest.Messenger();
        controller.register(messenger);
        java.util.Map<String, Object> arguments = new java.util.HashMap<>();
        arguments.put("transferId", "engine-test");
        arguments.put("jobId", "job");
        java.nio.ByteBuffer request = io.flutter.plugin.common.StandardMethodCodec.INSTANCE
                .encodeMethodCall(new io.flutter.plugin.common.MethodCall("recoverStop", arguments));
        request.flip();
        Object[] response = {null};
        messenger.handler.onMessage(request, reply -> {
            if (reply == null) return;
            reply.flip();
            response[0] = io.flutter.plugin.common.StandardMethodCodec.INSTANCE.decodeEnvelope(reply);
        });
        assertTrue("explicit recovery must return a checked transfer record",
                response[0] instanceof java.util.Map);
        assertEquals(2, closeAttempts.get());
        assertTrue(store.read("engine-test").stopAcknowledged);
        assertEquals(false, ((java.util.Map<?, ?>) response[0]).get("recoveryRequired"));
        org.junit.Assert.assertFalse(partial.exists());
        assertEquals(TransferExecutionResult.CANCELLED,
                engine.run("engine-test", ignored -> {}));
    }

    @Test
    public void pauseAcknowledgementWaitsForEngineWriterLeaseRelease() throws Exception {
        assertStopAtWriterRelease(false);
    }

    @Test
    public void pauseEscalatesToCancelAtEngineWriterReleaseBoundary() throws Exception {
        assertStopAtWriterRelease(true);
    }

    private void assertStopAtWriterRelease(boolean escalate) throws Exception {
        store.write(manifest(3L, null));
        CountDownLatch progressEntered = new CountDownLatch(1);
        CountDownLatch continueRun = new CountDownLatch(1);
        TransferEngine engine = new TransferEngine(context, store,
                ignored -> { throw new AssertionError("paused transfer must not open transport"); },
                ignored -> {}, () -> 1_000L);
        java.util.concurrent.CompletableFuture<TransferExecutionResult> result =
                new java.util.concurrent.CompletableFuture<>();
        Thread worker = new Thread(() -> {
            try {
                result.complete(engine.run("engine-test", ignored -> {
                    progressEntered.countDown();
                    try {
                        continueRun.await();
                    } catch (InterruptedException unexpected) {
                        throw new AssertionError(unexpected);
                    }
                }));
            } catch (Throwable failure) {
                result.completeExceptionally(failure);
            }
        });
        worker.start();
        try {
            assertTrue(progressEntered.await(10, TimeUnit.SECONDS));
            synchronized (TransferWriterLease.class) {
                store.update("engine-test", current -> current.withStopRequest(false));
                continueRun.countDown();
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
                while (worker.getState() != Thread.State.BLOCKED
                        && worker.isAlive() && System.nanoTime() < deadline) {
                    Thread.sleep(1);
                }
                assertEquals("engine must reach the held lease-release boundary",
                        Thread.State.BLOCKED, worker.getState());
                org.junit.Assert.assertFalse("pause acknowledged before writer lease release",
                        store.read("engine-test").stopAcknowledged);
                if (escalate) {
                    new TransferController(context).stop("engine-test", true);
                    assertEquals(TransferManifest.CANCELLED, store.read("engine-test").state);
                    org.junit.Assert.assertFalse(store.read("engine-test").stopAcknowledged);
                }
            }
        } finally {
            continueRun.countDown();
            worker.join(10_000);
            assertTrue("test worker must terminate", !worker.isAlive());
        }
        assertEquals(escalate ? TransferExecutionResult.CANCELLED : TransferExecutionResult.PAUSED,
                result.get(10, TimeUnit.SECONDS));
        assertTrue(store.read("engine-test").stopAcknowledged);
    }

    @Test
    public void quarantinedTransferDoesNotInterruptFormerWorkerDoingUnrelatedWork() throws Exception {
        store.write(manifest(3L, null));
        TransferEngine engine = new TransferEngine(context, store, ignored ->
                new HttpURLConnection(new URL("https://huggingface.co/test")) {
                    @Override public int getResponseCode() { return 503; }
                    @Override public void disconnect() { throw new IllegalStateException("close failed"); }
                    @Override public boolean usingProxy() { return false; }
                    @Override public void connect() {}
                }, ignored -> {}, () -> 1_000L);
        ExecutorService executor = Executors.newSingleThreadExecutor();
        CountDownLatch unrelatedStarted = new CountDownLatch(1);
        CountDownLatch unrelatedRelease = new CountDownLatch(1);
        CountDownLatch unrelatedInterrupted = new CountDownLatch(1);
        try {
            executor.submit(() -> engine.run("engine-test", ignored -> {})).get(10, TimeUnit.SECONDS);
            Future<?> unrelated = executor.submit(() -> {
                unrelatedStarted.countDown();
                try {
                    unrelatedRelease.await();
                } catch (InterruptedException unexpected) {
                    unrelatedInterrupted.countDown();
                }
            });
            assertTrue(unrelatedStarted.await(10, TimeUnit.SECONDS));
            new TransferController(context).stop("engine-test", true);
            org.junit.Assert.assertFalse("stop interrupted work no longer owned by this transfer",
                    unrelatedInterrupted.await(200, TimeUnit.MILLISECONDS));
            unrelatedRelease.countDown();
            unrelated.get(10, TimeUnit.SECONDS);
        } finally {
            unrelatedRelease.countDown();
            executor.shutdownNow();
            assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS));
        }
    }

    @Test
    public void cancellationAfterFailedCloseKeepsPartialAndAcknowledgementPending() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] { 112 });
        store.write(manifest(3L, null));
        TransferEngine engine = new TransferEngine(context, store, ignored ->
                new HttpURLConnection(new URL("https://huggingface.co/test")) {
                    @Override public int getResponseCode() { return 503; }
                    @Override public void disconnect() { throw new IllegalStateException("close failed"); }
                    @Override public boolean usingProxy() { return false; }
                    @Override public void connect() {}
                }, ignored -> {}, () -> 1_000L);
        engine.run("engine-test", ignored -> {});

        new TransferController(context).stop("engine-test", true);

        org.junit.Assert.assertFalse("failed cleanup is not cancellation acknowledgement",
                store.read("engine-test").stopAcknowledged);
        assertTrue("unconfirmed close must preserve the job partial", partial.isFile());
    }

    @Test
    public void failedConnectionCleanupDoesNotOpenAnotherTransport() throws Exception {
        store.write(manifest(3L, null));
        AtomicInteger opened = new AtomicInteger();
        TransferEngine engine = new TransferEngine(context, store, ignored -> {
            opened.incrementAndGet();
            return new HttpURLConnection(new URL("https://huggingface.co/test")) {
                @Override public int getResponseCode() { return 503; }
                @Override public void disconnect() { throw new IllegalStateException("close failed"); }
                @Override public boolean usingProxy() { return false; }
                @Override public void connect() {}
            };
        }, ignored -> {}, () -> 1_000L);

        engine.run("engine-test", ignored -> {});

        assertEquals("unconfirmed cleanup must block new connection allocation", 1, opened.get());
    }

    @Test
    public void repeatedNativeCancelDoesNotInterruptCleanupOrAcknowledgeEarly() throws Exception {
        assertSharedStopDuringCleanup(true);
    }

    @Test
    public void nativePauseEscalatesToCancelDuringCleanupWithoutAnotherInterrupt() throws Exception {
        assertSharedStopDuringCleanup(false);
    }

    @Test
    public void recoveryCannotReplaceActiveCleanupOwner() throws Exception {
        assertSharedStopDuringCleanup(true, true);
    }

    private void assertSharedStopDuringCleanup(boolean initiallyCancel) throws Exception {
        assertSharedStopDuringCleanup(initiallyCancel, false);
    }

    private void assertSharedStopDuringCleanup(boolean initiallyCancel, boolean tryRecovery) throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "p".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        BlockingReadConnection connection = new BlockingReadConnection();
        connection.holdCleanup = true;
        store.write(manifest(3L, null));
        TransferEngine engine = new TransferEngine(context, store, ignored -> connection,
                ignored -> {}, () -> 1_000L);
        ExecutorService executor = Executors.newSingleThreadExecutor();
        Future<TransferExecutionResult> result = executor.submit(() -> {
            try {
                return engine.run("engine-test", ignored -> {});
            } finally {
                Thread.interrupted();
            }
        });
        try {
            assertTrue(connection.readEntered.await(10, TimeUnit.SECONDS));
            TransferController controller = new TransferController(context);
            controller.stop("engine-test", initiallyCancel);
            assertTrue(connection.cleanupEntered.await(10, TimeUnit.SECONDS));
            org.junit.Assert.assertFalse(store.read("engine-test").stopAcknowledged);
            assertTrue(partial.isFile());
            if (tryRecovery) {
                assertEquals(false, controller.status("engine-test").get("recoveryRequired"));
                try {
                    controller.recoverStop("engine-test", "job");
                    org.junit.Assert.fail("recovery must not replace a live cleanup owner");
                } catch (IllegalStateException expected) {
                    // Busy recovery must leave the original writer in control.
                }
                assertEquals(1, connection.disconnectCalls.get());
                org.junit.Assert.assertFalse(result.isDone());
                org.junit.Assert.assertFalse(store.read("engine-test").stopAcknowledged);
                assertTrue(partial.isFile());
            }
            controller.stop("engine-test", true);
            org.junit.Assert.assertFalse("repeated Cancel interrupted owned cleanup",
                    connection.cleanupInterrupted.await(200, TimeUnit.MILLISECONDS));
            org.junit.Assert.assertFalse(result.isDone());
            assertEquals(1, connection.disconnectCalls.get());
        } finally {
            connection.release.countDown();
            connection.cleanupRelease.countDown();
            try {
                assertEquals(TransferExecutionResult.CANCELLED, result.get(10, TimeUnit.SECONDS));
            } finally {
                executor.shutdownNow();
                executor.awaitTermination(10, TimeUnit.SECONDS);
            }
        }
        assertTrue(store.read("engine-test").stopAcknowledged);
        assertTrue(!partial.exists());
    }

    @Test
    public void nativeCancelWakesAnUninterruptibleReadBeforeAcknowledgingCleanup() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "p".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        BlockingReadConnection connection = new BlockingReadConnection();
        store.write(manifest(3L, null));
        TransferEngine engine = new TransferEngine(context, store, ignored -> connection,
                ignored -> {}, () -> 1_000L);
        ExecutorService executor = Executors.newSingleThreadExecutor();
        Future<TransferExecutionResult> result = executor.submit(() -> {
            try {
                return engine.run("engine-test", ignored -> {});
            } finally {
                Thread.interrupted();
            }
        });
        try {
            assertTrue(connection.readEntered.await(10, TimeUnit.SECONDS));
            new TransferController(context).stop("engine-test", true);
            try {
                assertEquals(TransferExecutionResult.CANCELLED, result.get(1, TimeUnit.SECONDS));
            } catch (TimeoutException blocked) {
                org.junit.Assert.fail("native Cancel did not wake the blocked transport");
            }
            assertTrue(connection.disconnected);
            assertTrue(store.read("engine-test").stopAcknowledged);
            assertEquals(TransferManifest.CANCELLED, store.read("engine-test").state);
            assertTrue(!partial.exists());
            try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
                org.junit.Assert.assertNotNull(lease);
            }
        } finally {
            // Only the disposable transport fixture is released after a failure.
            connection.release.countDown();
            try {
                result.get(10, TimeUnit.SECONDS);
            } finally {
                executor.shutdownNow();
                executor.awaitTermination(10, TimeUnit.SECONDS);
            }
        }
    }

    @Test
    public void interruptedTransportRemainsResumableAndReleasesWriterOwnership() throws Exception {
        assertInterruptedTransportCleanup(0);
    }

    @Test
    public void interruptedInitialHeadersDisconnectBeforeReturningRetry() throws Exception {
        assertInterruptedTransportCleanup(1);
    }

    @Test
    public void interruptedHeadersAfterConnectionHandoffDisconnectBeforeRetry() throws Exception {
        assertInterruptedTransportCleanup(2);
    }

    private void assertInterruptedTransportCleanup(int failResponseCall) throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "p".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, null, null, "ok".getBytes());
        FakeConnection connection = factory.responses.peek();
        connection.onStatus = () -> Thread.currentThread().interrupt();
        connection.failResponseCall = failResponseCall;
        store.write(manifest(3L, null));
        TransferEngine engine = new TransferEngine(context, store, factory,
                ignored -> {}, () -> 1_000L);
        ExecutorService executor = Executors.newSingleThreadExecutor();
        boolean[] retainedInterrupt = {false};
        try {
            Future<TransferExecutionResult> result = executor.submit(() -> {
                try {
                    return engine.run("engine-test", ignored -> {});
                } finally {
                    retainedInterrupt[0] = Thread.currentThread().isInterrupted();
                    Thread.interrupted(); // Do not contaminate the host test executor.
                }
            });
            assertEquals(TransferExecutionResult.RETRY, result.get(10, TimeUnit.SECONDS));
            assertTrue(retainedInterrupt[0]);
            assertEquals(TransferManifest.RUNNING, store.read("engine-test").state);
            assertEquals("p", new String(Files.readAllBytes(partial.toPath()),
                    java.nio.charset.StandardCharsets.UTF_8));
            assertEquals(1, factory.opened);
            assertTrue("interrupted transport must disconnect before releasing ownership", connection.disconnected);
            try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
                org.junit.Assert.assertNotNull("interrupted engine must release its own writer lease", lease);
            }
        } finally {
            executor.shutdownNow();
            executor.awaitTermination(10, TimeUnit.SECONDS);
        }
    }

    @Test
    public void schedulerReplayCannotRestartDownloadedArtifact() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "ok".getBytes());
        TransferManifest completed = store.write(manifest(2L, null).withProgress(
                TransferManifest.DOWNLOADED, 2L, 0, null, "\"stable\""));
        QueueConnectionFactory factory = new QueueConnectionFactory();
        TransferEngine engine = new TransferEngine(context, store, factory,
                ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(0, factory.opened);
        assertEquals(completed.stateRevision, store.read("engine-test").stateRevision);
        assertEquals("ok", new String(Files.readAllBytes(partial.toPath()),
                java.nio.charset.StandardCharsets.UTF_8));
    }

    @Test
    public void schedulerReplayCannotRetryPermanentFailure() throws Exception {
        TransferManifest failed = store.write(manifest(2L, null).withFailure(
                TransferFailureCode.SECURITY_REJECTED, "security_rejected"));
        QueueConnectionFactory factory = new QueueConnectionFactory();
        TransferEngine engine = new TransferEngine(context, store, factory,
                ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        assertEquals(0, factory.opened);
        assertEquals(failed.stateRevision, store.read("engine-test").stateRevision);
        assertEquals(TransferFailureCode.SECURITY_REJECTED.wireName(),
                store.read("engine-test").failureCode);
    }

    @Test
    public void systemStopCannotBeConsumedAsAnOrdinaryQueuedRetry() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(429, null, "1", new byte[0]);
        factory.responses.peek().onStatus = () -> {
            try {
                store.update("engine-test", current -> current.withSystemStop(7));
            } catch (Exception failure) {
                throw new AssertionError(failure);
            }
        };
        store.write(manifest(2L, null));
        List<Long> sleeps = new ArrayList<>();
        TransferEngine engine = new TransferEngine(context, store, factory, sleeps::add, () -> 1_000L);

        assertEquals(TransferExecutionResult.RETRY, engine.run("engine-test", ignored -> {}));
        assertTrue("system stop must not enter HTTP retry backoff", sleeps.isEmpty());
        assertEquals(1, factory.opened);
        assertTrue(store.read("engine-test").shouldReschedule());
    }

    @Test
    public void stopAtEndOfResponseCannotBeOverwrittenByFinalProgress() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(200, null, null, "ok".getBytes());
        factory.responses.peek().onEof = () -> {
            try {
                new TransferController(context).stop("engine-test", true);
            } catch (Exception failure) {
                throw new AssertionError(failure);
            }
        };
        store.write(manifest(2L, null));
        TransferEngine engine = new TransferEngine(context, store, factory,
                ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.CANCELLED,
                engine.run("engine-test", ignored -> {}));
        assertEquals(TransferManifest.CANCELLED, store.read("engine-test").state);
        assertTrue(store.read("engine-test").stopAcknowledged);
        assertTrue(!partial.exists());
    }

    @Test
    public void cancelDuringRetryCannotAcknowledgeWhileEngineOwnsPartial() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "p".getBytes());
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(429, null, "1", new byte[0]);
        store.write(manifest(20L, null));
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {
            try {
                new TransferController(context).stop("engine-test", true);
                assertTrue("active engine must retain partial until it stops", partial.isFile());
                assertTrue("state alone cannot prove termination",
                        !store.read("engine-test").stopAcknowledged);
            } catch (Exception failure) {
                throw new AssertionError(failure);
            }
        }, () -> 1_000L);

        assertEquals(TransferExecutionResult.CANCELLED, engine.run("engine-test", ignored -> {}));
        assertTrue(store.read("engine-test").stopAcknowledged);
        assertTrue(!partial.exists());
    }

    @Test
    public void secondEngineCannotOpenTransportForOwnedPartial() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(200, null, null, "ok".getBytes());
        store.write(manifest(2L, null));
        TransferEngine competitor = new TransferEngine(context, store,
                ignored -> { throw new AssertionError("duplicate engine opened transport"); },
                ignored -> {}, () -> 1_000L);
        TransferEngine engine = new TransferEngine(context, store, factory,
                ignored -> {}, () -> 1_000L);
        boolean[] attempted = {false};

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", progress -> {
            if (!attempted[0]) {
                attempted[0] = true;
                assertEquals(TransferExecutionResult.RETRY,
                        competitor.run("engine-test", ignored -> {}));
            }
        }));
        assertTrue(attempted[0]);
        assertEquals(TransferManifest.DOWNLOADED, store.read("engine-test").state);
    }

    @Test
    public void downloadsHashesAndPersistsDownloadedState() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(200, "\"stable\"", null, "hello".getBytes());
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"));
        List<TransferManifest> progress = new ArrayList<>();

        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L
        );

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", progress::add));
        TransferManifest result = store.read("engine-test");
        assertEquals(TransferManifest.DOWNLOADED, result.state);
        assertEquals(5L, result.downloadedBytes);
        assertEquals("\"stable\"", result.entityTag);
        assertTrue(progress.size() >= 2);
    }

    @Test
    public void rejectsWrongResumeOffsetWithoutAppendingOrDeletingPartial() throws Exception {
        assertRejectedResume("bytes 0-2/5");
    }

    @Test
    public void rejectsMissingResumeRangeWithoutAppendingOrDeletingPartial() throws Exception {
        assertRejectedResume(null);
    }

    @Test
    public void rejectsMalformedAndInconsistentResumeRangesWithoutMutation() throws Exception {
        for (String range : new String[] {
                "bytes 2-4/6", "bytes 2-5/5", "bytes 3-2/5",
                "bytes 2-4/*", "items 2-4/5", "bytes -1-4/5",
                "bytes 2-9223372036854775808/5", "bytes 2-4/5, 0-1/5"
        }) {
            store.delete("engine-test");
            assertRejectedResume(range);
        }
    }

    @Test
    public void segmentedResponseCannotWriteBeyondItsDeclaredRange() throws Exception {
        assertSegmentBoundaryFailure(new byte[] {108, 108, 111}, "oversized_content", new byte[] {104, 101});
    }

    @Test
    public void incompleteSegmentCannotBecomeACompletedRange() throws Exception {
        assertSegmentBoundaryFailure(new byte[] {108}, "truncated_content", new byte[] {104, 101, 108});
    }

    private void assertSegmentBoundaryFailure(byte[] body, String failureCode, byte[] retained) throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, "\"stable\"", null, body);
        factory.responses.peek().contentRange = "bytes 2-3/5";
        store.write(manifest(5L, null).withProgress(
                TransferManifest.QUEUED, 2L, 0, null, "\"stable\""));
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        assertEquals(failureCode, store.read("engine-test").failureCode);
        assertEquals(1, factory.opened);
        org.junit.Assert.assertArrayEquals(retained, Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void pauseBetweenSegmentsDoesNotOpenAnotherConnection() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, "\"stable\"", null, new byte[] {108, 108});
        factory.responses.peek().contentRange = "bytes 2-3/5";
        factory.add(206, "\"stable\"", null, new byte[] {111});
        factory.responses.toArray(new FakeConnection[0])[1].contentRange = "bytes 4-4/5";
        store.write(manifest(5L, null).withProgress(
                TransferManifest.QUEUED, 2L, 0, null, "\"stable\""));
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.PAUSED, engine.run("engine-test", progress -> {
            if (progress.downloadedBytes == 4L) {
                try {
                    store.update("engine-test", current -> current.withStopRequest(false));
                } catch (Exception failure) {
                    throw new AssertionError("Unable to request test pause", failure);
                }
            }
        }));
        assertEquals(1, factory.opened);
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void validPartialSuffixContinuesAtItsReturnedBoundary() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, "\"stable\"", null, new byte[] {108, 108});
        FakeConnection first = factory.responses.peek();
        first.contentRange = "bytes 2-3/5";
        first.contentLength = 2L;
        factory.add(206, "\"stable\"", null, new byte[] {111});
        FakeConnection last = factory.responses.toArray(new FakeConnection[0])[1];
        last.contentRange = "bytes 4-4/5";
        last.contentLength = 1L;
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
                .withProgress(TransferManifest.QUEUED, 2L, 0, null, "\"stable\""));
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals("bytes=2-", first.getRequestProperty("Range"));
        assertEquals("bytes=4-", last.getRequestProperty("Range"));
        assertEquals("\"stable\"", last.getRequestProperty("If-Range"));
        assertEquals(TransferManifest.DOWNLOADED, store.read("engine-test").state);
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 111},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void validResumeAppendsOnlyTheRequestedSuffixAndVerifiesHash() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, "\"stable\"", null, new byte[] {108, 108, 111});
        FakeConnection response = factory.responses.peek();
        response.contentRange = "bytes 2-4/5";
        response.contentLength = 3L;
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 111},
                Files.readAllBytes(partial.toPath()));
        assertEquals("bytes=2-", response.getRequestProperty("Range"));
        assertEquals(TransferManifest.DOWNLOADED, store.read("engine-test").state);
        assertEquals(1, factory.opened);
    }

    @Test
    public void rejectsRangeLengthDisagreementBeforeOpeningPartialForAppend() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, null, null, new byte[] {108, 108, 111});
        factory.responses.peek().contentRange = "bytes 2-4/5";
        factory.responses.peek().contentLength = 4L;
        store.write(manifest(5L, null));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101}, Files.readAllBytes(partial.toPath()));
        assertEquals("invalid_content_range", store.read("engine-test").failureCode);
    }

    @Test
    public void rejectsOversizedChunkBeforeAppendingToExistingPartial() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, null, null, new byte[] {108, 108, 111});
        factory.responses.peek().contentRange = "bytes 2-2/3";
        store.write(manifest(3L, null));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101}, Files.readAllBytes(partial.toPath()));
        assertEquals("oversized_content", store.read("engine-test").failureCode);
        assertEquals(1, factory.opened);
    }

    @Test
    public void rejectsOversizedFreshResponseBeforeWritingExcessBytes() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(200, null, null, new byte[] {104, 101, 108, 108, 111});
        store.write(manifest(3L, null));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        assertEquals(0L, partial.length());
        assertEquals("oversized_content", store.read("engine-test").failureCode);
        assertEquals(1, factory.opened);
    }

    @Test
    public void resumeSendsStrongValidatorAlongsideItsRange() throws Exception {
        assertResumeValidator("\"stable\"", "\"stable\"");
    }

    @Test
    public void weakValidatorIsNeverSentAsIfRange() throws Exception {
        assertResumeValidator("W/\"stable\"", null);
    }

    @Test
    public void interruptedConditionalResumeRetainsPriorValidatorWhenResponseOmitsIt() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, null, null, new byte[] {108});
        FakeConnection interrupted = factory.responses.peek();
        interrupted.contentRange = "bytes 2-4/5";
        interrupted.failAtEof = true;
        factory.add(206, "\"stable\"", null, new byte[] {108, 111});
        FakeConnection resumed = factory.responses.toArray(new FakeConnection[0])[1];
        resumed.contentRange = "bytes 3-4/5";
        store.write(manifest(5L, null).withProgress(
                TransferManifest.QUEUED, 2L, 0, null, "\"stable\""));
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals("\"stable\"", interrupted.getRequestProperty("If-Range"));
        assertEquals("bytes=3-", resumed.getRequestProperty("Range"));
        assertEquals("\"stable\"", resumed.getRequestProperty("If-Range"));
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 111},
                Files.readAllBytes(partial.toPath()));
    }

    private void assertResumeValidator(String savedTag, String expectedHeader) throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, savedTag, null, new byte[] {108, 108, 111});
        FakeConnection response = factory.responses.peek();
        response.contentRange = "bytes 2-4/5";
        store.write(manifest(5L, null).withProgress(
                TransferManifest.QUEUED, 2L, 0, null, savedTag));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals("bytes=2-", response.getRequestProperty("Range"));
        assertEquals(expectedHeader, response.getRequestProperty("If-Range"));
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 111},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void rateLimitResponseCannotReplaceThePartialFilesValidator() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(429, "\"error-page\"", "1", new byte[0]);
        factory.add(206, "\"stable\"", null, new byte[] {108, 108, 111});
        FakeConnection resumed = factory.responses.toArray(new FakeConnection[0])[1];
        resumed.contentRange = "bytes 2-4/5";
        store.write(manifest(5L, null).withProgress(
                TransferManifest.QUEUED, 2L, 0, null, "\"stable\""));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(2, factory.opened);
        assertEquals("\"stable\"", store.read("engine-test").entityTag);
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 111},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void truncatedFailureRetainsTheValidatorAlreadyBoundToPartialBytes() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(200, "\"stable\"", null, new byte[] {104, 101});
        store.write(manifest(5L, null));
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        TransferManifest failed = store.read("engine-test");
        assertEquals("truncated_content", failed.failureCode);
        assertEquals("\"stable\"", failed.entityTag);
        assertEquals(2L, failed.downloadedBytes);
        assertEquals(TransferManifest.FAILED, failed.state);
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101}, Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void hashFailureRetainsTheValidatorOfTheDownloadedRepresentation() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(200, "\"received\"", null, new byte[] {104, 101, 108, 108, 79});
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"));
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        TransferManifest failed = store.read("engine-test");
        assertEquals("hash_mismatch", failed.failureCode);
        assertEquals("\"received\"", failed.entityTag);
        assertEquals(5L, failed.downloadedBytes);
        assertEquals(TransferManifest.FAILED, failed.state);
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 79},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void interruptedResponsePersistsValidatorBeforeFirstByteCheckpoint() throws Exception {
        assertInterruptedResponseKeepsValidator(2);
    }

    @Test
    public void retryCannotOverwriteValidatorFromAnAlreadyPersistedByteCheckpoint() throws Exception {
        assertInterruptedResponseKeepsValidator(1024 * 1024);
    }

    @Test
    public void completeHashVerifiedPartialFinishesWithoutOpeningNetwork() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101, 108, 108, 111});
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"));
        AtomicInteger requests = new AtomicInteger();
        TransferEngine engine = new TransferEngine(context, store, ignored -> {
            requests.incrementAndGet();
            throw new java.io.IOException("fixture is offline");
        }, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(0, requests.get());
        assertEquals(TransferManifest.DOWNLOADED, store.read("engine-test").state);
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 111},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void completeHashVerifiedPartialRecoversAfterNetworkRetryBudgetIsExhausted() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101, 108, 108, 111});
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
                .withProgress(TransferManifest.QUEUED, 5L, TransferPolicy.MAX_RETRIES,
                        "transient_network", null));
        AtomicInteger requests = new AtomicInteger();
        TransferEngine engine = new TransferEngine(context, store, ignored -> {
            requests.incrementAndGet();
            throw new java.io.IOException("fixture is offline");
        }, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(0, requests.get());
        assertEquals(TransferManifest.DOWNLOADED, store.read("engine-test").state);
        assertEquals(TransferPolicy.MAX_RETRIES, store.read("engine-test").retryCount);
    }

    @Test
    public void exhaustedRetryBudgetNeverOpensNetworkForAnIncompletePartial() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
                .withProgress(TransferManifest.QUEUED, 2L, TransferPolicy.MAX_RETRIES,
                        "transient_network", null));
        AtomicInteger requests = new AtomicInteger();
        TransferEngine engine = new TransferEngine(context, store, ignored -> {
            requests.incrementAndGet();
            throw new java.io.IOException("retry budget must remain enforced");
        }, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        assertEquals(0, requests.get());
        assertEquals("retry_exhausted", store.read("engine-test").failureCode);
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101}, Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void corruptCompletePartialFailsHashValidationWithoutNetwork() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101, 108, 108, 79});
        store.write(manifest(5L, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"));
        AtomicInteger requests = new AtomicInteger();
        TransferEngine engine = new TransferEngine(context, store, ignored -> {
            requests.incrementAndGet();
            throw new java.io.IOException("fixture is offline");
        }, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        assertEquals("hash_mismatch", store.read("engine-test").failureCode);
        assertEquals(0, requests.get());
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 79},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void completePartialAccepts416OnlyWithMatchingSizeAndStrongValidator() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101, 108, 108, 111});
        store.write(manifest(5L, null).withProgress(
                TransferManifest.QUEUED, 5L, 0, null, "\"stable\""));
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(416, "\"stable\"", null, new byte[0]);
        FakeConnection response = factory.responses.peek();
        response.contentRange = "bytes */5";
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(TransferManifest.DOWNLOADED, store.read("engine-test").state);
        assertEquals(1, factory.opened);
        assertEquals("bytes=5-", response.getRequestProperty("Range"));
        assertEquals("\"stable\"", response.getRequestProperty("If-Range"));
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101, 108, 108, 111},
                Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void contradictory416CannotDeleteOrCompleteAnIncompletePartial() throws Exception {
        assertInvalid416PreservesPartial(new byte[] {104, 101}, "bytes */5");
    }

    @Test
    public void wrong416LengthCannotDeleteOrCompleteAnExistingPartial() throws Exception {
        assertInvalid416PreservesPartial(new byte[] {104, 101, 108, 108, 111}, "bytes */6");
    }

    @Test
    public void malformed416RangesPreserveTheCompletePartial() throws Exception {
        for (String range : new String[] {
                null, "bytes */*", "bytes */9223372036854775808", "items */5", "bytes 0-4/5"
        }) {
            store.delete("engine-test");
            assertInvalid416PreservesPartial(new byte[] {104, 101, 108, 108, 111}, range);
        }
    }

    @Test
    public void untrusted416ValidatorsRestartInsteadOfCompletingOldBytes() throws Exception {
        for (String[] tags : new String[][] {
                {null, "\"stable\""}, {"W/\"stable\"", "W/\"stable\""},
                {"\"stable\"", "\"changed\""}, {"\"stable\"", null}
        }) {
            store.delete("engine-test");
            Files.createDirectories(partial.getParentFile().toPath());
            Files.write(partial.toPath(), new byte[] {104, 101, 108, 108, 111});
            store.write(manifest(5L, null).withProgress(
                    TransferManifest.QUEUED, 5L, 0, null, tags[0]));
            QueueConnectionFactory factory = new QueueConnectionFactory();
            factory.add(416, tags[1], null, new byte[0]);
            factory.responses.peek().contentRange = "bytes */5";
            factory.add(200, "\"new\"", null, new byte[] {119, 111, 114, 108, 100});
            FakeConnection fresh = factory.responses.toArray(new FakeConnection[0])[1];
            TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

            assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
            assertEquals(2, factory.opened);
            assertEquals(null, fresh.getRequestProperty("Range"));
            assertEquals(null, fresh.getRequestProperty("If-Range"));
            assertEquals("\"new\"", store.read("engine-test").entityTag);
            org.junit.Assert.assertArrayEquals(new byte[] {119, 111, 114, 108, 100},
                    Files.readAllBytes(partial.toPath()));
        }
    }

    private void assertInvalid416PreservesPartial(byte[] existingBytes, String range) throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), existingBytes);
        store.write(manifest(5L, null).withProgress(
                TransferManifest.QUEUED, existingBytes.length, 0, null, "\"stable\""));
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(416, "\"stable\"", null, new byte[0]);
        factory.responses.peek().contentRange = range;
        TransferEngine engine = new TransferEngine(context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        org.junit.Assert.assertArrayEquals(existingBytes, Files.readAllBytes(partial.toPath()));
        assertEquals("invalid_content_range", store.read("engine-test").failureCode);
        assertEquals(1, factory.opened);
    }

    private void assertInterruptedResponseKeepsValidator(int prefixBytes) throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(200, "\"stable\"", null, new byte[prefixBytes]);
        FakeConnection interrupted = factory.responses.peek();
        interrupted.failAtEof = true;
        List<String> validatorsAtInterruption = new ArrayList<>();
        interrupted.onEof = () -> {
            try {
                validatorsAtInterruption.add(store.read("engine-test").entityTag);
            } catch (Exception failure) {
                throw new AssertionError(failure);
            }
        };
        factory.add(206, "\"stable\"", null, new byte[] {1, 2, 3});
        FakeConnection resumed = factory.responses.toArray(new FakeConnection[0])[1];
        resumed.contentRange = "bytes " + prefixBytes + "-" + (prefixBytes + 2) + "/" + (prefixBytes + 3);
        store.write(manifest(prefixBytes + 3L, null));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(java.util.Collections.singletonList("\"stable\""), validatorsAtInterruption);
        assertEquals("\"stable\"", resumed.getRequestProperty("If-Range"));
        assertEquals("bytes=" + prefixBytes + "-", resumed.getRequestProperty("Range"));
        assertEquals(2, factory.opened);
        byte[] installedBytes = Files.readAllBytes(partial.toPath());
        assertEquals(prefixBytes + 3, installedBytes.length);
        org.junit.Assert.assertArrayEquals(new byte[] {1, 2, 3},
                java.util.Arrays.copyOfRange(installedBytes, prefixBytes, installedBytes.length));
    }

    private void assertRejectedResume(String range) throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {104, 101});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(206, null, null, new byte[] {108, 108, 111});
        factory.responses.peek().contentRange = range;
        store.write(manifest(5L, null));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L);

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        org.junit.Assert.assertArrayEquals(new byte[] {104, 101}, Files.readAllBytes(partial.toPath()));
        assertEquals(TransferManifest.FAILED, store.read("engine-test").state);
        assertEquals("invalid_content_range", store.read("engine-test").failureCode);
        assertEquals(1, factory.opened);
    }

    @Test
    public void honorsRetryAfterThroughInjectedSleeper() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(429, null, "7", new byte[0]);
        factory.add(200, null, null, "ok".getBytes());
        store.write(manifest(2L, null));
        List<Long> sleeps = new ArrayList<>();
        TransferEngine engine = new TransferEngine(
                context, store, factory, sleeps::add, () -> 1_000L
        );

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(1, sleeps.size());
        assertEquals(Long.valueOf(7_000L), sleeps.get(0));
        assertEquals(2, factory.opened);
    }

    @Test
    public void hugeRetryAfterCannotOverflowIntoImmediateRetry() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(429, null, "9223372036854775807", new byte[0]);
        factory.add(200, null, null, new byte[] {111, 107});
        store.write(manifest(2L, null));
        List<Long> sleeps = new ArrayList<>();
        TransferEngine engine = new TransferEngine(context, store, factory, sleeps::add, () -> 1_000L);

        assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
        assertEquals(java.util.Collections.singletonList(60_000L), sleeps);
        assertEquals(2, factory.opened);
    }

    @Test
    public void rejectsRedirectOutsideAllowlist() throws Exception {
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(302, null, null, new byte[0], "https://evil.example/model.gguf");
        store.write(manifest(2L, null));
        TransferEngine engine = new TransferEngine(
                context, store, factory, ignored -> {}, () -> 1_000L
        );

        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        assertEquals(TransferManifest.FAILED, store.read("engine-test").state);
    }

    @Test
    public void retryHeadersUseBoundedDateAndMalformedFallbacks() throws Exception {
        String[] headers = {null, "invalid", "Thu, 1 Jan 1970 00:00:08 GMT",
                "Thu, 1 Jan 1970 00:00:00 GMT", "Thu, 1 Jan 1970 00:02:00 GMT"};
        long[] expected = {1_000L, 1_000L, 7_000L, 1_000L, 60_000L};
        for (int index = 0; index < headers.length; index++) {
            store.delete("engine-test");
            if (partial.exists()) assertTrue(partial.delete());
            QueueConnectionFactory factory = new QueueConnectionFactory();
            factory.add(503, null, headers[index], new byte[0]);
            factory.add(200, null, null, new byte[] {111, 107});
            store.write(manifest(2L, null));
            List<Long> sleeps = new ArrayList<>();
            TransferEngine engine = new TransferEngine(context, store, factory, sleeps::add, () -> 1_000L);
            assertEquals(TransferExecutionResult.SUCCESS, engine.run("engine-test", ignored -> {}));
            assertEquals(java.util.Collections.singletonList(expected[index]), sleeps);
            assertEquals(TransferManifest.DOWNLOADED, store.read("engine-test").state);
            assertEquals(2, factory.opened);
        }
    }

    @Test
    public void redirectWithoutDestinationFailsWithoutTouchingPartial() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {112});
        QueueConnectionFactory factory = new QueueConnectionFactory();
        factory.add(302, null, null, new byte[0]);
        store.write(manifest(2L, null));
        TransferEngine engine = new TransferEngine(context, store, factory,
                ignored -> { throw new AssertionError("permanent redirect failure must not retry"); }, () -> 1_000L);
        assertEquals(TransferExecutionResult.FAILURE, engine.run("engine-test", ignored -> {}));
        assertEquals("security_rejected", store.read("engine-test").failureCode);
        org.junit.Assert.assertArrayEquals(new byte[] {112}, Files.readAllBytes(partial.toPath()));
        assertEquals(1, factory.opened);
    }

    @Test
    public void acknowledgesPauseOnlyAfterEngineObservesRequest() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "partial".getBytes());
        store.write(manifest(20L, null).withStopRequest(false));
        TransferEngine engine = new TransferEngine(
                context, store, ignored -> { throw new AssertionError("network must not open"); },
                ignored -> {}, () -> 1_000L
        );

        assertEquals(TransferExecutionResult.PAUSED, engine.run("engine-test", ignored -> {}));
        TransferManifest result = store.read("engine-test");
        assertTrue(result.stopAcknowledged);
        assertEquals(7L, result.downloadedBytes);
        assertTrue(partial.isFile());
    }

    @Test
    public void deletesOnlyCancelledJobPartialWhenAcknowledged() throws Exception {
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), "partial".getBytes());
        store.write(manifest(20L, null).withStopRequest(true));
        TransferEngine engine = new TransferEngine(
                context, store, ignored -> { throw new AssertionError("network must not open"); },
                ignored -> {}, () -> 1_000L
        );

        assertEquals(TransferExecutionResult.CANCELLED, engine.run("engine-test", ignored -> {}));
        TransferManifest result = store.read("engine-test");
        assertTrue(result.stopAcknowledged);
        assertEquals(0L, result.downloadedBytes);
        assertTrue(!partial.exists());
    }

    private TransferManifest manifest(long expectedBytes, String hash) {
        return new TransferManifest(
                "engine-test", "job", "model", "owner/model",
                "0123456789abcdef0123456789abcdef01234567",
                "https://huggingface.co/owner/model/resolve/0123456789abcdef0123456789abcdef01234567/model.gguf",
                partial.getAbsolutePath(), expectedBytes, hash, 0L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L
        );
    }

    private static final class QueueConnectionFactory implements TransferEngine.ConnectionFactory {
        final Queue<FakeConnection> responses = new ArrayDeque<>();
        int opened;

        void add(int status, String etag, String retryAfter, byte[] body) throws Exception {
            add(status, etag, retryAfter, body, null);
        }

        void add(int status, String etag, String retryAfter, byte[] body, String location)
                throws Exception {
            responses.add(new FakeConnection(status, etag, retryAfter, body, location));
        }

        @Override
        public HttpURLConnection open(URI ignored) {
            opened++;
            return responses.remove();
        }
    }

    static final class BlockingReadConnection extends HttpURLConnection {
        final CountDownLatch readEntered = new CountDownLatch(1);
        final CountDownLatch release = new CountDownLatch(1);
        final CountDownLatch cleanupEntered = new CountDownLatch(1);
        final CountDownLatch cleanupRelease = new CountDownLatch(1);
        final CountDownLatch cleanupInterrupted = new CountDownLatch(1);
        final AtomicInteger disconnectCalls = new AtomicInteger();
        boolean holdCleanup;
        volatile boolean disconnected;

        BlockingReadConnection() throws Exception {
            super(new URL("https://huggingface.co/fixture"));
        }

        @Override public int getResponseCode() { return 206; }
        @Override public String getHeaderField(String name) {
            return "Content-Range".equalsIgnoreCase(name) ? "bytes 1-2/3" : null;
        }
        @Override public InputStream getInputStream() {
            return new InputStream() {
                @Override public int read() throws java.io.IOException {
                    return read(new byte[1], 0, 1);
                }
                @Override public int read(byte[] bytes, int offset, int length) throws java.io.IOException {
                    readEntered.countDown();
                    boolean interrupted = false;
                    for (;;) {
                        try {
                            release.await();
                            break;
                        } catch (InterruptedException ignored) {
                            interrupted = true; // Simulates a socket that ignores interruption.
                        }
                    }
                    if (interrupted) Thread.currentThread().interrupt();
                    throw new java.io.InterruptedIOException("fixture connection closed");
                }
                @Override public void close() {
                    if (!holdCleanup) return;
                    Thread.interrupted(); // Models cleanup consuming the initial interrupt.
                    cleanupEntered.countDown();
                    boolean interrupted = false;
                    for (;;) {
                        try {
                            cleanupRelease.await();
                            break;
                        } catch (InterruptedException repeated) {
                            cleanupInterrupted.countDown();
                            interrupted = true;
                        }
                    }
                    if (interrupted) Thread.currentThread().interrupt();
                }
            };
        }
        @Override public void disconnect() {
            disconnectCalls.incrementAndGet();
            disconnected = true;
            release.countDown();
        }
        @Override public boolean usingProxy() { return false; }
        @Override public void connect() {}
    }

    private static final class FakeConnection extends HttpURLConnection {
        private final int status;
        private final String etag;
        private final String retryAfter;
        private final byte[] body;
        private final String location;
        String contentRange;
        long contentLength = -1L;
        boolean failAtEof;
        Runnable onEof;
        Runnable onStatus;
        int failResponseCall;
        int responseCalls;
        boolean disconnected;

        FakeConnection(int status, String etag, String retryAfter, byte[] body, String location)
                throws Exception {
            super(new URL("https://huggingface.co/test"));
            this.status = status;
            this.etag = etag;
            this.retryAfter = retryAfter;
            this.body = body;
            this.location = location;
        }

        @Override public int getResponseCode() throws java.io.IOException {
            responseCalls++;
            if (onStatus != null) {
                Runnable action = onStatus;
                onStatus = null;
                action.run();
            }
            if (responseCalls == failResponseCall) {
                throw new java.io.InterruptedIOException("fixture interrupted headers");
            }
            return status;
        }
        @Override public InputStream getInputStream() {
            return new java.io.FilterInputStream(new ByteArrayInputStream(body)) {
                @Override public synchronized int read(byte[] bytes, int offset, int length)
                        throws java.io.IOException {
                    int result = super.read(bytes, offset, length);
                    if (result < 0 && onEof != null) {
                        Runnable action = onEof;
                        onEof = null;
                        action.run();
                    }
                    if (result < 0 && failAtEof) throw new java.io.IOException("fixture stream dropped");
                    return result;
                }
            };
        }
        @Override public long getContentLengthLong() { return contentLength; }
        @Override public String getHeaderField(String name) {
            if ("Content-Range".equalsIgnoreCase(name)) return contentRange;
            if ("ETag".equalsIgnoreCase(name)) return etag;
            if ("Retry-After".equalsIgnoreCase(name)) return retryAfter;
            if ("Location".equalsIgnoreCase(name)) return location;
            return null;
        }
        @Override public void disconnect() { disconnected = true; }
        @Override public boolean usingProxy() { return false; }
        @Override public void connect() {}
    }
}
