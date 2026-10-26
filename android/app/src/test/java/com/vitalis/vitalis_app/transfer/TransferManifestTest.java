package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertThrows;
import org.json.JSONException;
import org.json.JSONObject;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public final class TransferManifestTest {
    @Test
    public void restartRecoveryUsesTheDurableValidationAndInstallationBoundary() {
        assertEquals(TransferRecoveryAction.NONE, TransferRecoveryAction.forManifest(null));
        String[] states = {TransferManifest.QUEUED, TransferManifest.RUNNING,
                TransferManifest.DOWNLOADED, TransferManifest.VALIDATING,
                TransferManifest.READY_TO_INSTALL, TransferManifest.INSTALLED,
                TransferManifest.PAUSED, TransferManifest.FAILED, TransferManifest.CANCELLED};
        TransferRecoveryAction[] actions = {TransferRecoveryAction.RESUME_DOWNLOAD,
                TransferRecoveryAction.RESUME_DOWNLOAD, TransferRecoveryAction.RESTART_VALIDATION,
                TransferRecoveryAction.RESTART_VALIDATION, TransferRecoveryAction.PROJECT_INSTALLATION,
                TransferRecoveryAction.NONE, TransferRecoveryAction.HOLD,
                TransferRecoveryAction.HOLD, TransferRecoveryAction.NONE};
        for (int index = 0; index < states.length; index++) {
            TransferManifest manifest = new TransferManifest("recovery", "job", "model", "publisher/model",
                    "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                    "/private/model.gguf.part", 20L, null, 0L, 0, states[index], null, null, 1L, 1L);
            assertEquals(states[index], actions[index], TransferRecoveryAction.forManifest(manifest));
        }
    }

    @Test
    public void missingLegacyStopAcknowledgementRemainsUnconfirmed() throws Exception {
        TransferManifest original = new TransferManifest("legacy-stop", "job", "model", "publisher/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                "/private/model.gguf.part", 20L, null, 0L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L);
        for (boolean cancel : new boolean[] {false, true}) {
            JSONObject legacy = original.withStopRequest(cancel).toJson();
            legacy.remove("stopAcknowledged");
            assertFalse(TransferManifest.fromJson(legacy).stopAcknowledged);
        }
    }

    @Test
    public void malformedStateRevisionsCannotMasqueradeAsLegacyRecords() throws Exception {
        TransferManifest original = new TransferManifest("revision", "job", "model", "publisher/model",
                "0123456789012345678901234567890123456789", "https://huggingface.co/model.gguf",
                "/private/model.gguf.part", 20L, null, 0L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L);
        for (Object invalid : new Object[] {"3", 1.5d, -1L, true, JSONObject.NULL}) {
            JSONObject json = original.toJson();
            json.put("stateRevision", invalid);
            assertThrows(JSONException.class, () -> TransferManifest.fromJson(json));
        }
    }

    @Test
    public void jsonRoundTripPreservesImmutableIdentityAndProgress() throws Exception {
        TransferManifest original = new TransferManifest(
                "transfer-a", "job-a", "model-a", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                "/private/model.gguf.part", 1024L, null, 512L, 2,
                TransferManifest.PAUSED, "user_paused", "etag-a", 1L, 2L
        );

        TransferManifest restored = TransferManifest.fromJson(original.toJson());

        assertEquals(original.transferId, restored.transferId);
        assertEquals(original.revision, restored.revision);
        assertEquals(512L, restored.downloadedBytes);
        assertEquals(TransferManifest.PAUSED, restored.state);
        assertEquals("/private/model.gguf", restored.finalPath);
        assertEquals(0, restored.artifactIndex);
        assertEquals(1, restored.shardCount);
        assertEquals("immutable_revision_etag", restored.expectedHashAuthority);
        assertEquals("pending", restored.validationState);
        assertEquals(TransferFailureCode.NONE.wireName(), restored.failureCode);
        assertEquals(TransferStopDisposition.USER_PAUSED.wireName(), restored.stopDisposition);
        assertFalse(restored.shouldReschedule());
        assertNull(restored.expectedSha256);
    }

    @Test
    public void recoveryActionAndRescheduleAreStateSpecific() throws Exception {
        TransferManifest original = new TransferManifest(
                "transfer-b", "job-b", "model-b", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                "/private/model.gguf.part", 1024L, null, 512L, 2,
                TransferManifest.RUNNING, null, "etag-b", 1L, 2L
        );

        TransferManifest stopped = original.withSystemStop(7);
        assertEquals(TransferRecoveryAction.RESUME_DOWNLOAD,
                TransferRecoveryAction.forManifest(stopped));
        assertEquals(TransferFailureCode.SYSTEM_STOP.wireName(), stopped.failureCode);
        assertTrue(stopped.shouldReschedule());

        TransferManifest failed = original.withFailure(
                TransferFailureCode.HASH_MISMATCH,
                "hash_mismatch"
        );
        assertEquals(TransferRecoveryAction.HOLD,
                TransferRecoveryAction.forManifest(failed));
        assertEquals(TransferFailureCode.HASH_MISMATCH.wireName(), failed.failureCode);
        assertEquals(TransferStopDisposition.PERMANENT_FAILURE.wireName(),
                failed.stopDisposition);
    }

    @Test
    public void userStopRequiresExplicitAcknowledgement() {
        TransferManifest original = new TransferManifest(
                "transfer-c", "job-c", "model-c", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                "/private/model.gguf.part", 1024L, null, 512L, 0,
                TransferManifest.RUNNING, null, "etag-c", 1L, 2L
        );

        TransferManifest requested = original.withStopRequest(true);
        assertEquals(TransferManifest.CANCELLED, requested.state);
        assertFalse(requested.stopAcknowledged);
        assertEquals("user_cancel_requested", requested.stopReason);

        TransferManifest acknowledged = requested.acknowledgeStop(0L);
        assertTrue(acknowledged.stopAcknowledged);
        assertEquals("user_cancelled", acknowledged.stopReason);
        assertEquals(0L, acknowledged.downloadedBytes);
    }
}
