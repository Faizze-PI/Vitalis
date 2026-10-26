package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;

import androidx.test.core.app.ApplicationProvider;
import androidx.work.WorkInfo;
import androidx.work.WorkManager;
import androidx.work.testing.WorkManagerTestInitHelper;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.io.File;
import java.util.List;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public final class TransferSchedulerTest {
    @org.junit.After public void closeWorkDatabase() {
        WorkManagerTestInitHelper.closeWorkDatabase();
    }

    @Test
    public void api28To33UsesUniqueConstrainedWorkManagerTransfer() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        WorkManagerTestInitHelper.initializeTestWorkManager(context);
        File partial = new File(context.getFilesDir(), "models/model.gguf.part");
        TransferManifest manifest = manifest(partial);

        assertTrue(TransferScheduler.schedule(context, manifest));

        List<WorkInfo> work = WorkManager.getInstance(context)
                .getWorkInfosByTag(manifest.transferId)
                .get();
        assertEquals(1, work.size());
        assertEquals(WorkInfo.State.ENQUEUED, work.get(0).getState());
    }

    private TransferManifest manifest(File partial) {
        long now = System.currentTimeMillis();
        return new TransferManifest(
                "transfer-test", "job-test", "model-test", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                partial.getPath(), 1024L, null, 0L, 0,
                TransferManifest.QUEUED, null, null, now, now
        );
    }
}
