package com.vitalis.vitalis_app.transfer;

import org.json.JSONException;
import org.json.JSONObject;

/** Durable, atomic authority for one immutable Hugging Face artifact transfer. */
public final class TransferManifest {
    public static final String QUEUED = "queued"; // hardcode: HC-063
    public static final String RUNNING = "running"; // hardcode: HC-063
    public static final String PAUSED = "paused"; // hardcode: HC-063
    public static final String CANCELLED = "cancelled"; // hardcode: HC-063
    public static final String DOWNLOADED = "downloaded"; // hardcode: HC-063
    public static final String VALIDATING = "validating"; // hardcode: HC-063
    public static final String READY_TO_INSTALL = "readyToInstall"; // hardcode: HC-063
    public static final String INSTALLED = "installed"; // hardcode: HC-063
    public static final String FAILED = "failed"; // hardcode: HC-063

    public final String transferId;
    public final String jobId;
    public final String modelId;
    public final String repository;
    public final String revision;
    public final String sourceUrl;
    public final String partialPath;
    public final String finalPath;
    public final int artifactIndex;
    public final int shardCount;
    public final String validationState;
    public final String expectedHashAuthority;
    public final String installationProjectionState;
    public final long expectedBytes;
    public final String expectedSha256;
    public final long downloadedBytes;
    public final int retryCount;
    public final String state;
    public final String stopReason;
    public final String failureCode;
    public final String stopDisposition;
    public final boolean stopAcknowledged;
    public final String entityTag;
    public final long createdAtMillis;
    public final long updatedAtMillis;
    public final long stateRevision;
    public final long controlGeneration;

    public TransferManifest(
            String transferId,
            String jobId,
            String modelId,
            String repository,
            String revision,
            String sourceUrl,
            String partialPath,
            long expectedBytes,
            String expectedSha256,
            long downloadedBytes,
            int retryCount,
            String state,
            String stopReason,
            String entityTag,
            long createdAtMillis,
            long updatedAtMillis
    ) {
        this(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath,
                partialPath.endsWith(".part")
                        ? partialPath.substring(0, partialPath.length() - 5)
                        : partialPath,
                0, 1, "pending",
                expectedSha256 == null ? "immutable_revision_etag" : "publisher_sha256",
                "pending", expectedBytes, expectedSha256, downloadedBytes,
                retryCount, state, stopReason, entityTag, createdAtMillis,
                updatedAtMillis, FAILED.equals(state)
                        ? TransferFailureCode.TRANSFER_EXCEPTION.wireName()
                        : TransferFailureCode.NONE.wireName(),
                stopDispositionFor(state, stopReason).wireName(),
                PAUSED.equals(state) || CANCELLED.equals(state), 0L, 0L
        );
    }

    public TransferManifest(
            String transferId,
            String jobId,
            String modelId,
            String repository,
            String revision,
            String sourceUrl,
            String partialPath,
            String finalPath,
            int artifactIndex,
            int shardCount,
            String validationState,
            String expectedHashAuthority,
            String installationProjectionState,
            long expectedBytes,
            String expectedSha256,
            long downloadedBytes,
            int retryCount,
            String state,
            String stopReason,
            String entityTag,
            long createdAtMillis,
            long updatedAtMillis
    ) {
        this(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath, finalPath, artifactIndex, shardCount,
                validationState, expectedHashAuthority, installationProjectionState,
                expectedBytes, expectedSha256, downloadedBytes, retryCount,
                state, stopReason, entityTag, createdAtMillis, updatedAtMillis,
                FAILED.equals(state)
                        ? TransferFailureCode.TRANSFER_EXCEPTION.wireName()
                        : TransferFailureCode.NONE.wireName(),
                stopDispositionFor(state, stopReason).wireName(),
                PAUSED.equals(state) || CANCELLED.equals(state), 0L, 0L
        );
    }

    public TransferManifest withProgress(
            String nextState,
            long bytes,
            int retries,
            String reason,
            String nextEntityTag
    ) {
        return withProgressAt(
                nextState, bytes, retries, reason, nextEntityTag,
                System.currentTimeMillis()
        );
    }

    TransferManifest withProgressAt(
            String nextState,
            long bytes,
            int retries,
            String reason,
            String nextEntityTag,
            long updatedAt
    ) {
        return new TransferManifest(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath, finalPath, artifactIndex, shardCount,
                validationState, expectedHashAuthority, installationProjectionState,
                expectedBytes, expectedSha256, bytes, retries,
                nextState, reason, nextEntityTag, createdAtMillis,
                updatedAt, failureCode, stopDispositionFor(nextState, reason).wireName(),
                PAUSED.equals(nextState) || CANCELLED.equals(nextState), stateRevision,
                QUEUED.equals(nextState) && (PAUSED.equals(state) || CANCELLED.equals(state)
                        || FAILED.equals(state)) ? Math.addExact(controlGeneration, 1L) : controlGeneration
        );
    }

    private TransferManifest(
            String transferId, String jobId, String modelId, String repository,
            String revision, String sourceUrl, String partialPath, String finalPath,
            int artifactIndex, int shardCount, String validationState,
            String expectedHashAuthority, String installationProjectionState,
            long expectedBytes, String expectedSha256, long downloadedBytes,
            int retryCount, String state, String stopReason, String entityTag,
            long createdAtMillis, long updatedAtMillis, String failureCode,
            String stopDisposition, boolean stopAcknowledged, long stateRevision, long controlGeneration
    ) {
        this.transferId = transferId;
        this.jobId = jobId;
        this.modelId = modelId;
        this.repository = repository;
        this.revision = revision;
        this.sourceUrl = sourceUrl;
        this.partialPath = partialPath;
        this.finalPath = finalPath;
        this.artifactIndex = artifactIndex;
        this.shardCount = shardCount;
        this.validationState = validationState;
        this.expectedHashAuthority = expectedHashAuthority;
        this.installationProjectionState = installationProjectionState;
        this.expectedBytes = expectedBytes;
        this.expectedSha256 = expectedSha256;
        this.downloadedBytes = downloadedBytes;
        this.retryCount = retryCount;
        this.state = state;
        this.stopReason = stopReason;
        this.entityTag = entityTag;
        this.createdAtMillis = createdAtMillis;
        this.updatedAtMillis = updatedAtMillis;
        this.failureCode = failureCode;
        this.stopDisposition = stopDisposition;
        this.stopAcknowledged = stopAcknowledged;
        if (stateRevision < 0L) throw new IllegalArgumentException("Invalid manifest revision");
        this.stateRevision = stateRevision;
        if (controlGeneration < 0L) throw new IllegalArgumentException("Invalid control generation");
        this.controlGeneration = controlGeneration;
    }

    public TransferManifest withFailure(TransferFailureCode code, String reason) {
        return new TransferManifest(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath, finalPath, artifactIndex, shardCount,
                validationState, expectedHashAuthority, installationProjectionState,
                expectedBytes, expectedSha256, downloadedBytes, retryCount,
                FAILED, reason, entityTag, createdAtMillis, System.currentTimeMillis(),
                code.wireName(), TransferStopDisposition.PERMANENT_FAILURE.wireName(), true,
                stateRevision, controlGeneration
        );
    }

    public TransferManifest withSystemStop(int reason) {
        return new TransferManifest(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath, finalPath, artifactIndex, shardCount,
                validationState, expectedHashAuthority, installationProjectionState,
                expectedBytes, expectedSha256, downloadedBytes, retryCount,
                QUEUED, "system_stop_" + reason, entityTag, createdAtMillis,
                System.currentTimeMillis(), TransferFailureCode.SYSTEM_STOP.wireName(),
                TransferStopDisposition.SYSTEM_RETRY.wireName(), true, stateRevision, controlGeneration
        );
    }

    public TransferManifest withStopRequest(boolean cancel) {
        String nextState = cancel ? CANCELLED : PAUSED;
        String reason = cancel ? "user_cancel_requested" : "user_pause_requested";
        return new TransferManifest(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath, finalPath, artifactIndex, shardCount,
                validationState, expectedHashAuthority, installationProjectionState,
                expectedBytes, expectedSha256, downloadedBytes, retryCount,
                nextState, reason, entityTag, createdAtMillis, System.currentTimeMillis(),
                TransferFailureCode.NONE.wireName(),
                stopDispositionFor(nextState, reason).wireName(), false, stateRevision, controlGeneration
        );
    }

    public TransferManifest acknowledgeStop(long bytes) {
        if (!PAUSED.equals(state) && !CANCELLED.equals(state)) return this;
        String reason = CANCELLED.equals(state) ? "user_cancelled" : "user_paused";
        return new TransferManifest(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath, finalPath, artifactIndex, shardCount,
                validationState, expectedHashAuthority, installationProjectionState,
                expectedBytes, expectedSha256, bytes, retryCount,
                state, reason, entityTag, createdAtMillis, System.currentTimeMillis(),
                TransferFailureCode.NONE.wireName(), stopDisposition, true, stateRevision, controlGeneration
        );
    }

    public boolean shouldReschedule() {
        return TransferStopDisposition.SYSTEM_RETRY.wireName().equals(stopDisposition);
    }

    TransferManifest withStateRevision(long value) {
        return new TransferManifest(transferId, jobId, modelId, repository, revision,
                sourceUrl, partialPath, finalPath, artifactIndex, shardCount,
                validationState, expectedHashAuthority, installationProjectionState,
                expectedBytes, expectedSha256, downloadedBytes, retryCount, state,
                stopReason, entityTag, createdAtMillis, updatedAtMillis, failureCode,
                stopDisposition, stopAcknowledged, value, controlGeneration);
    }

    private static TransferStopDisposition stopDispositionFor(String state, String reason) {
        if (CANCELLED.equals(state)) return TransferStopDisposition.USER_CANCELLED;
        if (PAUSED.equals(state)) return TransferStopDisposition.USER_PAUSED;
        if (FAILED.equals(state)) return TransferStopDisposition.PERMANENT_FAILURE;
        if (reason != null && reason.startsWith("system_stop_")) {
            return TransferStopDisposition.SYSTEM_RETRY;
        }
        return TransferStopDisposition.NONE;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject value = new JSONObject();
        value.put("transferId", transferId);
        value.put("jobId", jobId);
        value.put("modelId", modelId);
        value.put("repository", repository);
        value.put("revision", revision);
        value.put("sourceUrl", sourceUrl);
        value.put("partialPath", partialPath);
        value.put("finalPath", finalPath);
        value.put("artifactIndex", artifactIndex);
        value.put("shardCount", shardCount);
        value.put("validationState", validationState);
        value.put("expectedHashAuthority", expectedHashAuthority);
        value.put("installationProjectionState", installationProjectionState);
        value.put("expectedBytes", expectedBytes);
        value.put("expectedSha256", expectedSha256 == null ? JSONObject.NULL : expectedSha256);
        value.put("downloadedBytes", downloadedBytes);
        value.put("retryCount", retryCount);
        value.put("state", state);
        value.put("stopReason", stopReason == null ? JSONObject.NULL : stopReason);
        value.put("failureCode", failureCode);
        value.put("stopDisposition", stopDisposition);
        value.put("stopAcknowledged", stopAcknowledged);
        value.put("entityTag", entityTag == null ? JSONObject.NULL : entityTag);
        value.put("createdAtMillis", createdAtMillis);
        value.put("updatedAtMillis", updatedAtMillis);
        value.put("stateRevision", stateRevision);
        value.put("controlGeneration", controlGeneration);
        return value;
    }

    public static TransferManifest fromJson(JSONObject value) throws JSONException {
        return new TransferManifest(
                value.getString("transferId"),
                value.getString("jobId"),
                value.getString("modelId"),
                value.getString("repository"),
                value.getString("revision"),
                value.getString("sourceUrl"),
                value.getString("partialPath"),
                value.optString(
                        "finalPath",
                        value.getString("partialPath").replaceFirst("\\.part$", "")
                ),
                value.optInt("artifactIndex", 0),
                value.optInt("shardCount", 1),
                value.optString("validationState", "pending"),
                value.optString(
                        "expectedHashAuthority",
                        value.isNull("expectedSha256")
                                ? "immutable_revision_etag"
                                : "publisher_sha256"
                ),
                value.optString("installationProjectionState", "pending"),
                value.getLong("expectedBytes"),
                nullableString(value, "expectedSha256"),
                value.getLong("downloadedBytes"),
                value.getInt("retryCount"),
                value.getString("state"),
                nullableString(value, "stopReason"),
                nullableString(value, "entityTag"),
                value.getLong("createdAtMillis"),
                value.getLong("updatedAtMillis"),
                value.optString("failureCode", TransferFailureCode.NONE.wireName()),
                value.optString("stopDisposition", TransferStopDisposition.NONE.wireName()),
                value.optBoolean("stopAcknowledged", false),
                readRevision(value, "stateRevision"), readRevision(value, "controlGeneration")
        );
    }

    private static String nullableString(JSONObject value, String key) {
        return value.isNull(key) ? null : value.optString(key, null);
    }

    private static long readRevision(JSONObject value, String key) throws JSONException {
        if (!value.has(key)) return 0L;
        Object revision = value.get(key);
        if (!(revision instanceof Long) && !(revision instanceof Integer)) {
            throw new JSONException("Invalid transfer state revision");
        }
        long result = ((Number) revision).longValue();
        if (result < 0L) throw new JSONException("Invalid transfer state revision");
        return result;
    }
}
