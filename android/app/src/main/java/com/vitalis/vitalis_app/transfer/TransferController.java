package com.vitalis.vitalis_app.transfer;

import android.content.Context;

import org.json.JSONObject;

import java.io.File;
import java.net.URI;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;

/** Validates Flutter requests and projects durable native transfer state. */
public final class TransferController {
    private final Context context;
    private final TransferManifestStore store;

    public TransferController(Context context) {
        this.context = context.getApplicationContext();
        store = new TransferManifestStore(this.context);
    }

    public void register(BinaryMessenger messenger) {
        new MethodChannel(messenger, "vitalis/model_transfers", StandardMethodCodec.INSTANCE,
                messenger.makeBackgroundTaskQueue())
                .setMethodCallHandler((call, result) -> {
                    try {
                        if (call.method.equals("enqueue")) {
                            @SuppressWarnings("unchecked")
                            Map<String, Object> request = (Map<String, Object>) call.arguments;
                            result.success(enqueue(request));
                        } else if (call.method.equals("status")) {
                            result.success(status(call.argument("transferId")));
                        } else if (call.method.equals("list")) {
                            result.success(list());
                        } else if (call.method.equals("pause")) {
                            stop(call.argument("transferId"), false);
                            result.success(null);
                        } else if (call.method.equals("cancel")) {
                            stop(call.argument("transferId"), true);
                            result.success(null);
                        } else if (call.method.equals("recoverStop")) {
                            result.success(recoverStop(call.argument("transferId"), call.argument("jobId")));
                        } else {
                            result.notImplemented();
                        }
                    } catch (Exception failure) {
                        TransferFailureCode code = failure instanceof SecurityException
                                ? TransferFailureCode.SECURITY_REJECTED
                                : failure instanceof org.json.JSONException || failure instanceof java.io.IOException
                                ? TransferFailureCode.MANIFEST_READ_FAILED : TransferFailureCode.TRANSFER_EXCEPTION;
                        android.util.Log.e("VitalisTransfer", "Transfer request failed: " + code.wireName());
                        result.error(failure instanceof StopPending ? "transfer_stop_pending" : "transfer_failure",
                                code.wireName(), null);
                    }
                });
    }

    private static final class StopPending extends IllegalStateException {}

    public Map<String, Object> recoverStop(String transferId, String jobId) throws Exception {
        TransferManifest current = store.read(transferId);
        if (current == null || jobId == null || !jobId.equals(current.jobId)) {
            throw new SecurityException("Transfer recovery identity mismatch");
        }
        if (!TransferManifest.PAUSED.equals(current.state)
                && !TransferManifest.CANCELLED.equals(current.state)) throw new StopPending();
        File partial = boundedPartial(current.partialPath);
        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
            if (lease == null || !TransferRunControl.recover(context, transferId)) throw new StopPending();
            acknowledgeStoppedWriter(transferId, partial);
        }
        return map(store.read(transferId));
    }

    public Map<String, Object> enqueue(Map<String, Object> request) throws Exception {
        String transferId = requiredString(request, "transferId");
        String jobId = requiredString(request, "jobId");
        String modelId = requiredString(request, "modelId");
        String repository = requiredString(request, "repository");
        String revision = requiredString(request, "revision");
        String sourceUrl = requiredString(request, "sourceUrl");
        String partialPath = requiredString(request, "partialPath");
        String finalPath = optionalString(request, "finalPath");
        if (finalPath == null) {
            finalPath = partialPath.endsWith(".part")
                    ? partialPath.substring(0, partialPath.length() - 5)
                    : partialPath;
        }
        int artifactIndex = optionalInt(request, "artifactIndex", 0);
        int shardCount = optionalInt(request, "shardCount", 1);
        long expectedBytes = requiredLong(request, "expectedBytes");
        String expectedHash = optionalString(request, "expectedSha256");
        validateIdentity(repository, revision, sourceUrl, expectedBytes, expectedHash);
        boundedPartial(partialPath);
        boundedFinal(finalPath);
        if (artifactIndex < 0 || shardCount <= 0 || artifactIndex > shardCount) {
            throw new IllegalArgumentException("Invalid artifact shard identity");
        }

        TransferManifest existing = store.read(transferId);
        if (existing != null) {
            if (!existing.jobId.equals(jobId)
                    || !existing.modelId.equals(modelId)
                    || !existing.repository.equals(repository)
                    || !existing.revision.equals(revision)
                    || !existing.sourceUrl.equals(sourceUrl)
                    || !existing.partialPath.equals(partialPath)
                    || !existing.finalPath.equals(finalPath)
                    || existing.artifactIndex != artifactIndex
                    || existing.shardCount != shardCount
                    || existing.expectedBytes != expectedBytes) {
                throw new SecurityException("Transfer identity collision");
            }
            if (TransferManifest.DOWNLOADED.equals(existing.state)) return map(existing);
            if ((TransferManifest.PAUSED.equals(existing.state) || TransferManifest.CANCELLED.equals(existing.state))
                    && !existing.stopAcknowledged) throw new StopPending();
            TransferManifest resumed = existing.withProgress(
                    TransferManifest.QUEUED,
                    boundedPartial(partialPath).length(),
                    existing.retryCount,
                    null,
                    existing.entityTag
            );
            resumed = store.write(resumed);
            scheduleOrThrow(resumed);
            return map(resumed);
        }

        long now = System.currentTimeMillis();
        TransferManifest manifest = new TransferManifest(
                transferId, jobId, modelId, repository, revision, sourceUrl,
                partialPath, finalPath, artifactIndex, shardCount, "pending",
                expectedHash == null ? "immutable_revision_etag" : "publisher_sha256",
                "pending", expectedBytes, expectedHash,
                boundedPartial(partialPath).length(), 0,
                TransferManifest.QUEUED, null, null, now, now
        );
        manifest = store.write(manifest);
        scheduleOrThrow(manifest);
        return map(manifest);
    }

    public Map<String, Object> status(String transferId) throws Exception {
        TransferManifest value = store.read(transferId);
        return value == null ? null : map(value);
    }

    public List<Map<String, Object>> list() throws Exception {
        List<Map<String, Object>> values = new ArrayList<>();
        for (TransferManifest manifest : store.list()) values.add(map(manifest));
        return values;
    }

    public void stop(String transferId, boolean cancel) throws Exception {
        stop(transferId, cancel, null);
    }

    public boolean stopForGeneration(String transferId, boolean cancel, long generation) throws Exception {
        if (generation < 0L) throw new IllegalArgumentException("Invalid control generation");
        return stop(transferId, cancel, generation);
    }

    private boolean stop(String transferId, boolean cancel, Long generation) throws Exception {
        TransferManifest requested = store.update(transferId, current -> {
            if (generation != null && current.controlGeneration != generation) return current;
            if (TransferManifest.CANCELLED.equals(current.state) && current.stopAcknowledged) return current;
            if (TransferManifest.PAUSED.equals(current.state) && current.stopAcknowledged && !cancel) return current;
            return current.withStopRequest(cancel || TransferManifest.CANCELLED.equals(current.state));
        });
        if (requested == null || (generation != null && requested.controlGeneration != generation)) return false;
        TransferRunControl.requestStop(context, transferId, requested.controlGeneration);
        TransferScheduler.cancel(context, transferId, requested.controlGeneration);
        // QUEUED can also mean an active engine is in retry backoff. State is
        // not termination evidence. Cleanup must acquire the writer lease.
        acknowledgeStop(transferId);
        return true;
    }

    public void acknowledgeStop(String transferId) throws Exception {
        TransferManifest current = store.read(transferId);
        if (current == null) return;
        File partial = boundedPartial(current.partialPath);
        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
            if (lease == null) return;
            if (TransferRunControl.hasPendingConnection(context, transferId)) return;
            acknowledgeStoppedWriter(transferId, partial);
        }
    }

    public boolean recordSchedulerStop(String transferId, int reason, long generation) {
        if (generation < 0L) return false;
        try {
            TransferManifest stopped = store.update(transferId, current -> {
                if (current.controlGeneration != generation) return current;
                if (!TransferManifest.QUEUED.equals(current.state)
                        && !TransferManifest.RUNNING.equals(current.state)) return current;
                boolean userStop = reason == androidx.work.WorkInfo.STOP_REASON_CANCELLED_BY_APP
                        || reason == androidx.work.WorkInfo.STOP_REASON_USER;
                return userStop ? current.withStopRequest(false) : current.withSystemStop(reason);
            });
            if (stopped == null) return false;
            if (stopped.controlGeneration != generation) return true;
            if (TransferManifest.PAUSED.equals(stopped.state)
                    || TransferManifest.CANCELLED.equals(stopped.state)) {
                acknowledgeStop(transferId);
                TransferManifest confirmed = store.read(transferId);
                return confirmed != null && (confirmed.controlGeneration != generation
                        || confirmed.stopAcknowledged);
            }
            return true;
        } catch (Exception failure) {
            android.util.Log.e("VitalisTransfer", "scheduler_stop_projection_unconfirmed");
            return false;
        }
    }

    private void acknowledgeStoppedWriter(String transferId, File partial) throws Exception {
        store.update(transferId, current -> {
            if (current.stopAcknowledged) return current;
            if (!TransferManifest.PAUSED.equals(current.state)
                    && !TransferManifest.CANCELLED.equals(current.state)) return current;
            if (!boundedPartial(current.partialPath).equals(partial)) {
                throw new SecurityException("Transfer partial identity changed");
            }
            long bytes = partial.isFile() ? partial.length() : 0L;
            if (TransferManifest.CANCELLED.equals(current.state)) {
                if (partial.exists() && !partial.delete()) {
                    throw new IllegalStateException("Unable to remove cancelled partial");
                }
                bytes = 0L;
            }
            return current.acknowledgeStop(bytes);
        });
    }

    private void scheduleOrThrow(TransferManifest manifest) throws Exception {
        if (!TransferScheduler.schedule(context, manifest)) {
            store.update(manifest.transferId, current -> {
                if (!TransferManifest.QUEUED.equals(current.state)) return current;
                return current.withProgress(TransferManifest.PAUSED, current.downloadedBytes,
                        current.retryCount, "scheduler_rejected", current.entityTag);
            });
            throw new IllegalStateException("Android transfer scheduler rejected the request");
        }
    }

    static void validateIdentity(
            String repository,
            String revision,
            String sourceUrl,
            long expectedBytes,
            String expectedHash
    ) {
        if (!repository.matches("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")) {
            throw new SecurityException("Invalid Hugging Face repository");
        }
        if (!revision.matches("[a-fA-F0-9]{40}")) {
            throw new SecurityException("Revision must be an immutable commit");
        }
        URI source = URI.create(sourceUrl);
        if (!"https".equals(source.getScheme())
                || !"huggingface.co".equalsIgnoreCase(source.getHost())
                || source.getUserInfo() != null
                || source.getQuery() != null
                || source.getFragment() != null) {
            throw new SecurityException("Initial transfer must use Hugging Face HTTPS");
        }
        String path = source.getPath().toLowerCase(Locale.ROOT);
        if (!path.startsWith(("/" + repository + "/resolve/" + revision + "/").toLowerCase(Locale.ROOT))) {
            throw new SecurityException("Transfer URL does not match immutable model identity");
        }
        if (expectedBytes <= 0L) throw new IllegalArgumentException("Expected size is required");
        if (expectedHash != null && !expectedHash.matches("[a-fA-F0-9]{64}")) {
            throw new IllegalArgumentException("Expected SHA-256 is invalid");
        }
    }

    private File boundedPartial(String path) throws Exception {
        File root = context.getFilesDir().getCanonicalFile();
        File partial = new File(path).getCanonicalFile();
        if (!partial.getPath().startsWith(root.getPath() + File.separator)
                || !partial.getName().endsWith(".part")) {
            throw new SecurityException("Transfer path escaped application storage");
        }
        return partial;
    }

    private File boundedFinal(String path) throws Exception {
        File root = context.getFilesDir().getCanonicalFile();
        File destination = new File(path).getCanonicalFile();
        if (!destination.getPath().startsWith(root.getPath() + File.separator)
                || destination.getName().endsWith(".part")
                || !destination.getName().endsWith(".gguf")) {
            throw new SecurityException("Final transfer path escaped application storage");
        }
        return destination;
    }

    private Map<String, Object> map(TransferManifest value) throws Exception {
        JSONObject json = value.toJson();
        Map<String, Object> result = new HashMap<>();
        java.util.Iterator<String> keys = json.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object item = json.get(key);
            result.put(key, item == JSONObject.NULL ? null : item);
        }
        result.put("recoveryRequired", TransferRunControl.requiresRecovery(context, value.transferId));
        return result;
    }

    private String requiredString(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof String) || ((String) item).isEmpty()) {
            throw new IllegalArgumentException("Missing " + key);
        }
        return (String) item;
    }

    private String optionalString(Map<String, Object> value, String key) {
        Object item = value.get(key);
        return item instanceof String && !((String) item).isEmpty() ? (String) item : null;
    }

    private long requiredLong(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof Number)) throw new IllegalArgumentException("Missing " + key);
        return ((Number) item).longValue();
    }

    private int optionalInt(Map<String, Object> value, String key, int fallback) {
        Object item = value.get(key);
        return item instanceof Number ? ((Number) item).intValue() : fallback;
    }
}
