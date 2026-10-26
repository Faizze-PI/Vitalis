package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Notification;
import android.content.Context;

import androidx.test.core.app.ApplicationProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;

/** Device-runtime checks for durable transfer state and notification wiring. */
@RunWith(AndroidJUnit4.class)
public final class TransferRuntimeInstrumentationTest {
    private static final String TRANSFER_ID = "instrumented-transfer";
    private Context context;
    private TransferManifestStore store;

    @Before
    public void setUp() throws Exception {
        context = ApplicationProvider.getApplicationContext();
        store = new TransferManifestStore(context);
        store.delete(TRANSFER_ID);
    }

    @After
    public void tearDown() throws Exception {
        store.delete(TRANSFER_ID);
    }

    @Test
    public void manifestSurvivesStoreReconstructionAndSelectsRecovery() throws Exception {
        TransferManifest running = manifest(TransferManifest.RUNNING);
        store.write(running);

        TransferManifest restored = new TransferManifestStore(context).read(TRANSFER_ID);

        assertNotNull(restored);
        assertEquals(TransferRecoveryAction.RESUME_DOWNLOAD,
                TransferRecoveryAction.forManifest(restored));
        assertEquals(running.revision, restored.revision);
    }

    @Test
    public void pauseCancelAndSystemStopHaveDistinctSchedulerSemantics() throws Exception {
        TransferManifest running = manifest(TransferManifest.RUNNING);
        TransferManifest paused = running.withProgress(
                TransferManifest.PAUSED, 0L, 0, "user_paused", null);
        TransferManifest cancelled = running.withProgress(
                TransferManifest.CANCELLED, 0L, 0, "user_cancelled", null);
        TransferManifest stopped = running.withSystemStop(7);

        assertFalse(paused.shouldReschedule());
        assertFalse(cancelled.shouldReschedule());
        assertTrue(stopped.shouldReschedule());
        assertEquals(TransferRecoveryAction.HOLD,
                TransferRecoveryAction.forManifest(paused));
        assertEquals(TransferRecoveryAction.NONE,
                TransferRecoveryAction.forManifest(cancelled));
    }

    @Test
    public void foregroundNotificationCanBeCreatedFromPersistedState() {
        Notification notification = TransferNotifications.build(
                context, manifest(TransferManifest.RUNNING));
        assertNotNull(notification);
        assertNotNull(notification.contentIntent);
    }

    private TransferManifest manifest(String state) {
        File partial = new File(context.getFilesDir(), "models/instrumented.gguf.part");
        return new TransferManifest(
                TRANSFER_ID, "instrumented-job", "model", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                partial.getAbsolutePath(), 1024L, null, 0L, 0,
                state, null, null, 1L, 1L
        );
    }
}
