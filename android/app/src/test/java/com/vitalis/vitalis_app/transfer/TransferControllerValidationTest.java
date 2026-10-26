package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;

import android.content.Context;

import androidx.test.core.app.ApplicationProvider;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.io.File;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public final class TransferControllerValidationTest {
    private static final String REVISION =
            "0123456789012345678901234567890123456789";

    @Test
    @Config(sdk = 34)
    public void enqueueAndResumeRetainIdentityAndActualPartialBytes() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File partial = new File(context.getFilesDir(), "models/enqueue-resume.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {1, 2, 3});
        TransferManifestStore store = new TransferManifestStore(context);
        TransferController controller = new TransferController(context);
        Map<String, Object> input = request(partial);
        Map<String, Object> first = controller.enqueue(input);
        assertEquals(TransferManifest.QUEUED, first.get("state"));
        assertEquals(3L, ((Number) first.get("downloadedBytes")).longValue());
        assertEquals("immutable_revision_etag", first.get("expectedHashAuthority"));
        controller.stop("transfer-validation", false);
        assertTrue(store.read("transfer-validation").stopAcknowledged);
        Map<String, Object> resumed = controller.enqueue(input);
        assertEquals(TransferManifest.QUEUED, resumed.get("state"));
        assertEquals(3L, ((Number) resumed.get("downloadedBytes")).longValue());
        long revision = store.read("transfer-validation").stateRevision;
        input.put("jobId", "another-job");
        assertThrows(SecurityException.class, () -> controller.enqueue(input));
        assertEquals(revision, store.read("transfer-validation").stateRevision);
        org.junit.Assert.assertArrayEquals(new byte[] {1, 2, 3}, Files.readAllBytes(partial.toPath()));
    }

    @Test
    public void malformedRequestsCannotCreateManifestOrChangePartial() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File partial = new File(context.getFilesDir(), "models/rejected-input.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {7});
        TransferController controller = new TransferController(context);
        String[] keys = {"jobId", "expectedBytes", "finalPath", "artifactIndex", "shardCount",
                "repository", "revision", "expectedSha256"};
        Object[] invalid = {"", "not-a-number", partial.getPath(), -1, 0,
                "../invalid", "main", "not-a-hash"};
        for (int index = 0; index < keys.length; index++) {
            Map<String, Object> input = request(partial);
            input.put(keys[index], invalid[index]);
            assertThrows(Exception.class, () -> controller.enqueue(input));
            org.junit.Assert.assertNull(new TransferManifestStore(context).read("transfer-validation"));
            org.junit.Assert.assertArrayEquals(new byte[] {7}, Files.readAllBytes(partial.toPath()));
        }
    }

    @Test
    public void enqueueCannotResumeAnUnacknowledgedStop() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File partial = new File(context.getFilesDir(), "models/unacknowledged-resume.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {1, 2, 3});
        TransferManifestStore store = new TransferManifestStore(context);
        store.delete("transfer-validation");
        TransferManifest pending = new TransferManifest("transfer-validation", "job-validation",
                "model-validation", "publisher/model", REVISION,
                "https://huggingface.co/publisher/model/resolve/" + REVISION + "/model.gguf",
                partial.getPath(), 1024L, null, 3L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L).withStopRequest(false);
        store.write(pending);
        Exception rejected = null;
        try {
            new TransferController(context).enqueue(request(partial));
        } catch (Exception failure) {
            rejected = failure;
        }
        TransferManifest result = store.read("transfer-validation");
        assertEquals("resume must not erase stop intent", TransferManifest.PAUSED, result.state);
        assertFalse(result.stopAcknowledged);
        assertTrue(rejected instanceof IllegalStateException);
        assertTrue(partial.isFile());
    }

    @Test
    @Config(sdk = 34)
    public void acknowledgedPauseCanBeEscalatedToCancellation() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File partial = new File(context.getFilesDir(), "models/paused-cancel.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {1, 2, 3});
        TransferManifestStore store = new TransferManifestStore(context);
        store.write(manifest("paused-cancel", partial).withStopRequest(false).acknowledgeStop(3L));

        new TransferController(context).stop("paused-cancel", true);

        TransferManifest result = store.read("paused-cancel");
        assertEquals(TransferManifest.CANCELLED, result.state);
        assertTrue(result.stopAcknowledged);
        assertFalse(partial.exists());
    }

    @Test
    @Config(sdk = 34)
    public void latePauseCannotDowngradePendingOrAcknowledgedCancellation() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File partial = new File(context.getFilesDir(), "models/cancel-dominance.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {1, 2, 3});
        TransferManifestStore store = new TransferManifestStore(context);
        store.write(manifest("cancel-dominance", partial).withStopRequest(true));
        TransferController controller = new TransferController(context);

        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
            assertNotNull(lease);
            controller.stop("cancel-dominance", false);
            assertEquals(TransferManifest.CANCELLED, store.read("cancel-dominance").state);
            assertFalse(store.read("cancel-dominance").stopAcknowledged);
            assertTrue(partial.isFile());
        }
        controller.acknowledgeStop("cancel-dominance");
        controller.stop("cancel-dominance", false);
        assertEquals(TransferManifest.CANCELLED, store.read("cancel-dominance").state);
        assertTrue(store.read("cancel-dominance").stopAcknowledged);
        assertFalse(partial.exists());
    }

    private TransferManifest manifest(String identity, File partial) {
        return new TransferManifest(identity, "job", "model", "publisher/model", REVISION,
                "https://huggingface.co/publisher/model/resolve/" + REVISION + "/model.gguf",
                partial.getPath(), 20L, null, 3L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L);
    }

    @Test
    public void acceptsCanonicalQueryFreeUrlGeneratedByFlutterPolicy() {
        TransferController.validateIdentity(
                "publisher/model",
                REVISION,
                "https://huggingface.co/publisher/model/resolve/" + REVISION
                        + "/weights/model.gguf",
                1024L,
                null
        );
    }

    @Test
    public void rejectsInitialUrlQuerySoCredentialsCannotEnterManifest() {
        Context context = ApplicationProvider.getApplicationContext();
        File partial = new File(context.getFilesDir(), "models/model.gguf.part");
        Map<String, Object> request = request(partial);
        request.put(
                "sourceUrl",
                "https://huggingface.co/publisher/model/resolve/" + REVISION
                        + "/model.gguf?token=secret"
        );

        assertThrows(
                SecurityException.class,
                () -> new TransferController(context).enqueue(request)
        );
    }

    @Test
    public void rejectsPartialPathOutsideApplicationStorage() {
        Context context = ApplicationProvider.getApplicationContext();
        Map<String, Object> request = request(
                new File(context.getFilesDir().getParentFile(), "escaped.gguf.part")
        );

        assertThrows(
                SecurityException.class,
                () -> new TransferController(context).enqueue(request)
        );
    }

    private Map<String, Object> request(File partial) {
        Map<String, Object> value = new HashMap<>();
        value.put("transferId", "transfer-validation");
        value.put("jobId", "job-validation");
        value.put("modelId", "model-validation");
        value.put("repository", "publisher/model");
        value.put("revision", REVISION);
        value.put(
                "sourceUrl",
                "https://huggingface.co/publisher/model/resolve/" + REVISION
                        + "/model.gguf"
        );
        value.put("partialPath", partial.getPath());
        value.put("expectedBytes", 1024L);
        return value;
    }
}
