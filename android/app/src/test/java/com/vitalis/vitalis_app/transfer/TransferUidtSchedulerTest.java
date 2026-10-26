package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.Context;

import androidx.test.core.app.ApplicationProvider;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implements;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.RealObject;
import org.robolectric.shadows.ShadowJobScheduler.ShadowJobSchedulerImpl;

import java.io.File;
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34, shadows = TransferUidtSchedulerTest.SharedNamespaceScheduler.class)
public final class TransferUidtSchedulerTest {
    @Test
    public void olderGenerationCannotCancelReplacementUidtJob() {
        Context context = ApplicationProvider.getApplicationContext();
        JobScheduler scheduler = context.getSystemService(JobScheduler.class)
                .forNamespace("vitalis_model_transfers");
        scheduler.cancelAll();
        TransferManifest paused = new TransferManifest(
                "generation-uidt", "job", "model", "publisher/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                new File(context.getFilesDir(), "models/generation.gguf.part").getPath(),
                3L, null, 1L, 0, TransferManifest.PAUSED, null, null, 1L, 1L);
        TransferManifest replacement = paused.withProgress(TransferManifest.QUEUED, 1L, 0, null, null);
        try {
            assertTrue(TransferScheduler.schedule(context, replacement));
            TransferScheduler.cancel(context, replacement.transferId, 0L);
            assertEquals(1, scheduler.getAllPendingJobs().size());
            assertEquals(1L, scheduler.getAllPendingJobs().get(0).getExtras()
                    .getLong(TransferNotifications.EXTRA_CONTROL_GENERATION));
            TransferScheduler.cancel(context, replacement.transferId, 1L);
            assertTrue(scheduler.getAllPendingJobs().isEmpty());
        } finally {
            scheduler.cancelAll();
        }
    }

    // Robolectric's per-wrapper maps do not model Android's shared scheduler
    // service. These tests use one namespace only; they do not test isolation.
    @Implements(className = "android.app.JobSchedulerImpl", isInAndroidSdk = false, minSdk = 34)
    public static class SharedNamespaceScheduler extends ShadowJobSchedulerImpl {
        @RealObject private JobScheduler scheduler;

        @Implementation
        protected JobScheduler forNamespace(String namespace) {
            return scheduler;
        }
    }

    @Test
    public void distinctTransferIdsCannotReplaceEachOthersScheduledJob() {
        Context context = ApplicationProvider.getApplicationContext();
        JobScheduler scheduler = context.getSystemService(JobScheduler.class)
                .forNamespace("vitalis_model_transfers");
        scheduler.cancelAll();
        try {
            // Java hash collision: the scheduler must preserve both identities.
            for (String identity : new String[] {"Aa", "BB"}) {
                TransferManifest manifest = new TransferManifest(
                        identity, "job-" + identity, "model-" + identity, "publisher/model",
                        "0123456789012345678901234567890123456789",
                        "https://huggingface.co/publisher/model/resolve/"
                                + "0123456789012345678901234567890123456789/model.gguf",
                        new File(context.getFilesDir(), "models/" + identity + ".gguf.part").getPath(),
                        1024L, null, 0L, 0, TransferManifest.QUEUED, null, null, 1L, 1L);
                assertTrue(TransferScheduler.schedule(context, manifest));
            }
            assertEquals(2, scheduler.getAllPendingJobs().size());
            java.util.Set<String> identities = new java.util.HashSet<>();
            for (JobInfo job : scheduler.getAllPendingJobs()) {
                identities.add(job.getExtras().getString(TransferScheduler.INPUT_TRANSFER_ID));
            }
            assertEquals(new java.util.HashSet<>(java.util.Arrays.asList("Aa", "BB")), identities);
            TransferScheduler.cancel(context, "Aa");
            assertEquals(1, scheduler.getAllPendingJobs().size());
            assertEquals("BB", scheduler.getAllPendingJobs().get(0).getExtras()
                    .getString(TransferScheduler.INPUT_TRANSFER_ID));
        } finally {
            scheduler.cancelAll();
        }
    }

    @Test
    public void api34SchedulesUserInitiatedNetworkJob() {
        Context context = ApplicationProvider.getApplicationContext();
        File partial = new File(context.getFilesDir(), "models/model.gguf.part");
        long now = System.currentTimeMillis();
        TransferManifest manifest = new TransferManifest(
                "transfer-uidt", "job-uidt", "model-uidt", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                partial.getPath(), 1024L, null, 0L, 0,
                TransferManifest.QUEUED, null, null, now, now
        );

        assertTrue(TransferScheduler.schedule(context, manifest));

        JobInfo job = TransferScheduler.buildUidtJob(context, manifest);
        assertTrue(job.isUserInitiated());
        assertEquals(TransferNotifications.id(context, manifest.transferId),
                job.getExtras().getInt(TransferScheduler.INPUT_NOTIFICATION_ID));
        assertEquals(
                manifest.transferId,
                job.getExtras().getString(TransferScheduler.INPUT_TRANSFER_ID)
        );
    }
}
