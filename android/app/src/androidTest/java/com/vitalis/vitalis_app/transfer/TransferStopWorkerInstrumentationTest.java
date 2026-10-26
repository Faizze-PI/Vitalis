package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.*;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.work.Data;
import androidx.work.Worker;
import androidx.work.testing.TestWorkerBuilder;
import java.io.File;
import java.nio.file.Files;
import java.util.UUID;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Real Android filesystem/Worker checks; not a process-death or scheduler suite. */
@RunWith(AndroidJUnit4.class)
public final class TransferStopWorkerInstrumentationTest {
    private Context context;
    private TransferManifestStore store;
    private String identity;
    private File partial;
    private File sibling;

    @Before public void prepareOwnedFixtures() throws Exception {
        context = ApplicationProvider.getApplicationContext();
        store = new TransferManifestStore(context);
        identity = "instrumented-stop-" + UUID.randomUUID();
        File directory = new File(context.getFilesDir(), "transfer-test-fixtures/" + identity);
        Files.createDirectories(directory.toPath());
        partial = new File(directory, "model.gguf.part");
        sibling = new File(directory, "other.gguf.part");
        Files.write(partial.toPath(), new byte[] {1, 2, 3});
        Files.write(sibling.toPath(), new byte[] {4, 5});
        store.write(new TransferManifest(identity, "fixture-job", "fixture-model", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/0123456789012345678901234567890123456789/model.gguf",
                partial.getPath(), 20L, null, 3L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L));
    }

    @After public void removeOwnedFixtures() throws Exception {
        if (identity != null && store != null) store.delete(identity);
        if (partial != null) Files.deleteIfExists(partial.toPath());
        if (sibling != null) Files.deleteIfExists(sibling.toPath());
        // Keep the stable writer-lock inode; no shared lock is deleted by cleanup.
    }

    @Test public void pauseCannotAcknowledgeUntilWriterLeaseIsReleased() throws Exception {
        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
            assertNotNull(lease);
            assertEquals(Worker.Result.retry(), stop(false, 0L));
            TransferManifest pending = new TransferManifestStore(context).read(identity);
            assertEquals(TransferManifest.PAUSED, pending.state);
            assertFalse(pending.stopAcknowledged);
            assertArrayEquals(new byte[] {1, 2, 3}, Files.readAllBytes(partial.toPath()));
        }
        assertEquals(Worker.Result.success(), stop(false, 0L));
        TransferManifest settled = new TransferManifestStore(context).read(identity);
        assertTrue(settled.stopAcknowledged);
        assertEquals(3L, settled.downloadedBytes);
        assertArrayEquals(new byte[] {4, 5}, Files.readAllBytes(sibling.toPath()));
    }

    @Test public void acknowledgedCancelRemovesOnlyItsOwnPartial() throws Exception {
        assertEquals(Worker.Result.success(), stop(true, 0L));
        TransferManifest cancelled = new TransferManifestStore(context).read(identity);
        assertEquals(TransferManifest.CANCELLED, cancelled.state);
        assertTrue(cancelled.stopAcknowledged);
        assertFalse(partial.exists());
        assertArrayEquals(new byte[] {4, 5}, Files.readAllBytes(sibling.toPath()));
        assertEquals(Worker.Result.success(), stop(false, 0L));
        assertEquals(TransferManifest.CANCELLED, store.read(identity).state);
    }

    @Test public void staleStopCannotChangeResumedGeneration() throws Exception {
        assertEquals(Worker.Result.success(), stop(false, 0L));
        TransferManifest resumed = store.write(store.read(identity).withProgress(
                TransferManifest.QUEUED, 3L, 0, null, null));
        assertTrue(resumed.controlGeneration > 0L);
        assertEquals(Worker.Result.success(), stop(true, 0L));
        TransferManifest retained = new TransferManifestStore(context).read(identity);
        assertEquals(TransferManifest.QUEUED, retained.state);
        assertEquals(resumed.stateRevision, retained.stateRevision);
        assertArrayEquals(new byte[] {1, 2, 3}, Files.readAllBytes(partial.toPath()));
    }

    private Worker.Result stop(boolean cancel, long generation) {
        return TestWorkerBuilder.from(context, TransferStopWorker.class, Runnable::run)
                .setInputData(new Data.Builder()
                        .putString(TransferScheduler.INPUT_TRANSFER_ID, identity)
                        .putLong(TransferStopWorker.INPUT_GENERATION, generation)
                        .putBoolean(TransferStopWorker.INPUT_CANCEL, cancel).build())
                .build().doWork();
    }
}
