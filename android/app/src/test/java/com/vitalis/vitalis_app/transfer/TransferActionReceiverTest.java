package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.Intent;
import androidx.test.core.app.ApplicationProvider;
import java.io.File;
import java.util.concurrent.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public final class TransferActionReceiverTest {
    @org.junit.After public void closeWorkDatabase() {
        androidx.work.testing.WorkManagerTestInitHelper.closeWorkDatabase();
    }

    @Test
    public void invalidActionsNeverEnterAsyncHandoff() {
        Context context = ApplicationProvider.getApplicationContext();
        Intent[] invalid = {null, new Intent("unrelated.action"),
                new Intent(TransferNotifications.ACTION_PAUSE), pause("../outside"),
                pause("valid-id").putExtra(TransferNotifications.EXTRA_CONTROL_GENERATION, -1L)};
        for (Intent intent : invalid) {
            TransferActionReceiver receiver = new TransferActionReceiver(command -> {
                throw new AssertionError("invalid action entered asynchronous scheduling");
            });
            receiver.onReceive(context, intent);
            assertFalse(org.robolectric.Shadows.shadowOf(receiver).wentAsync());
        }
    }

    @Test
    public void missingBroadcastResultCannotClaimDurableStop() {
        Context context = ApplicationProvider.getApplicationContext();
        TransferActionReceiver receiver = new TransferActionReceiver(command -> {
            throw new AssertionError("missing pending result must not schedule Stop");
        });
        receiver.onReceive(context, pause("missing-result"));
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("VitalisTransfer").stream()
                .anyMatch(entry -> "notification_handoff_missing_result".equals(entry.msg)));
    }

    @Test
    public void unavailableSchedulerFinishesBroadcastWithFailureNotStopAcknowledgement() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferActionReceiver receiver = new TransferActionReceiver(Runnable::run);
        var pending = attach(receiver);
        receiver.onReceive(context, pause("scheduler-unavailable"));
        assertTrue(finished(pending));
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("VitalisTransfer").stream()
                .anyMatch(entry -> "notification_handoff_failed".equals(entry.msg)));
        assertNull(new TransferManifestStore(context).read("scheduler-unavailable"));
    }

    @Test
    public void rejectedHandoffFinishesBroadcastWithRedactedDiagnostic() {
        Context context = ApplicationProvider.getApplicationContext();
        TransferActionReceiver receiver = new TransferActionReceiver(command -> {
            throw new RejectedExecutionException("fixture private detail");
        });
        android.content.BroadcastReceiver.PendingResult pending = attach(receiver);
        receiver.onReceive(context, pause("rejected-handoff"));
        assertTrue(finished(pending));
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("VitalisTransfer").stream()
                .anyMatch(entry -> "notification_handoff_rejected".equals(entry.msg)));
    }

    @Test
    public void unstartedHandoffDeadlineFinishesWithoutClaimingStop() {
        Context context = ApplicationProvider.getApplicationContext();
        TransferActionReceiver receiver = new TransferActionReceiver(command -> {});
        android.content.BroadcastReceiver.PendingResult pending = attach(receiver);
        receiver.onReceive(context, pause("held-handoff"));
        assertFalse(finished(pending));
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(
                TransferPolicy.NOTIFICATION_HANDOFF_MILLIS, TimeUnit.MILLISECONDS);
        assertTrue(finished(pending));
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("VitalisTransfer").stream()
                .anyMatch(entry -> "notification_handoff_unconfirmed".equals(entry.msg)));
    }

    private Intent pause(String identity) {
        return new Intent(TransferNotifications.ACTION_PAUSE)
                .putExtra(TransferNotifications.EXTRA_TRANSFER_ID, identity);
    }

    private boolean finished(android.content.BroadcastReceiver.PendingResult pending) {
        return org.robolectric.shadow.api.Shadow
                .<org.robolectric.shadows.ShadowBroadcastPendingResult>extract(pending)
                .getFuture().isDone();
    }

    private android.content.BroadcastReceiver.PendingResult attach(TransferActionReceiver receiver) {
        android.content.BroadcastReceiver.PendingResult pending =
                org.robolectric.util.ReflectionHelpers.callConstructor(
                        android.content.BroadcastReceiver.PendingResult.class,
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(int.class, 0),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(String.class, null),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(android.os.Bundle.class, null),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(int.class, 1),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(boolean.class, false),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(boolean.class, false),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(android.os.IBinder.class, null),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(int.class, 0),
                        org.robolectric.util.ReflectionHelpers.ClassParameter.from(int.class, 0));
        org.robolectric.util.ReflectionHelpers.setField(receiver, "mPendingResult", pending);
        return pending;
    }

    @Test
    public void pauseCallbackDoesNotWaitForManifestOwner() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(context);
        TransferActionReceiver receiver = new TransferActionReceiver();
        attach(receiver);
        String identity = "receiver-blocked-storage";
        File partial = new File(context.getFilesDir(), "models/receiver.gguf.part");
        TransferManifestStore store = new TransferManifestStore(context);
        store.write(new TransferManifest(identity, "job", "model", "owner/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                partial.getPath(), 3L, null, 0L, 0, TransferManifest.QUEUED, null, null, 1L, 1L));
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
        Future<?> callback = null;
        try {
            assertTrue(locked.await(10, TimeUnit.SECONDS));
            callback = executor.submit(() -> receiver.onReceive(context,
                    new Intent(TransferNotifications.ACTION_PAUSE)
                            .putExtra(TransferNotifications.EXTRA_TRANSFER_ID, identity)));
            try {
                callback.get(1, TimeUnit.SECONDS);
            } catch (TimeoutException blocked) {
                fail("notification callback waited for manifest storage ownership");
            }
        } finally {
            release.countDown();
            try {
                holder.get(10, TimeUnit.SECONDS);
                if (callback != null) callback.get(10, TimeUnit.SECONDS);
            } finally {
                executor.shutdownNow();
                assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS));
            }
        }
        assertTrue(org.robolectric.Shadows.shadowOf(receiver).wentAsync());
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (!store.read(identity).stopAcknowledged && System.nanoTime() < deadline) {
            Thread.sleep(10);
        }
        assertTrue("durable Stop command must eventually acknowledge Pause", store.read(identity).stopAcknowledged);
        assertEquals(TransferManifest.PAUSED, store.read(identity).state);
    }
}
