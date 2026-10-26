package com.vitalis.vitalis_app.transfer;

import android.content.Context;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.security.MessageDigest;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

/** Shared scheduler-independent HTTPS Range transfer implementation. */
public final class TransferEngine {
    public interface ProgressListener {
        void onProgress(TransferManifest manifest);
    }

    interface ConnectionFactory {
        HttpURLConnection open(URI uri) throws Exception;
    }

    interface Sleeper {
        void sleep(long milliseconds) throws InterruptedException;
    }

    interface Clock {
        long nowMillis();
    }

    private final Context context;
    private final TransferManifestStore manifests;
    private final ConnectionFactory connections;
    private final Sleeper sleeper;
    private final Clock clock;

    public TransferEngine(Context context) {
        this(
                context,
                new TransferManifestStore(context.getApplicationContext()),
                uri -> (HttpURLConnection) uri.toURL().openConnection(),
                Thread::sleep,
                System::currentTimeMillis
        );
    }

    TransferEngine(
            Context context,
            TransferManifestStore manifests,
            ConnectionFactory connections,
            Sleeper sleeper,
            Clock clock
    ) {
        this.context = context.getApplicationContext();
        this.manifests = manifests;
        this.connections = connections;
        this.sleeper = sleeper;
        this.clock = clock;
    }

    public TransferExecutionResult run(String transferId, ProgressListener progress) {
        return runForGeneration(transferId, null, progress);
    }

    public TransferExecutionResult run(String transferId, long generation, ProgressListener progress) {
        if (generation < 0L) throw new IllegalArgumentException("Invalid control generation");
        return runForGeneration(transferId, generation, progress);
    }

    private TransferExecutionResult runForGeneration(
            String transferId, Long generation, ProgressListener progress) {
        TransferRunControl control = TransferRunControl.begin(context, transferId);
        if (control == null) return TransferExecutionResult.RETRY;
        try {
            TransferManifest initial = manifests.read(transferId);
            if (initial == null) return TransferExecutionResult.FAILURE;
            if (generation != null && initial.controlGeneration != generation) {
                return TransferExecutionResult.SUCCESS; // Obsolete scheduler work, not a download completion.
            }
            control.bindGeneration(initial.controlGeneration);
            File partial = boundedPartial(initial.partialPath);
            TransferExecutionResult result;
            try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
                if (lease == null) return TransferExecutionResult.RETRY;
                result = runOwned(transferId, progress, partial, control);
            }
            boolean interrupted = Thread.interrupted();
            try {
                TransferExecutionResult stopped = requestedStopResult(transferId);
                if (stopped == null) return control.isStopped() ? TransferExecutionResult.RETRY : result;
                new TransferController(context).acknowledgeStop(transferId);
                TransferManifest settled = manifests.read(transferId);
                if (settled == null || !settled.stopAcknowledged) return TransferExecutionResult.RETRY;
                return TransferManifest.CANCELLED.equals(settled.state)
                        ? TransferExecutionResult.CANCELLED
                        : TransferManifest.PAUSED.equals(settled.state)
                        ? TransferExecutionResult.PAUSED : TransferExecutionResult.RETRY;
            } finally {
                if (interrupted) Thread.currentThread().interrupt();
            }
        } catch (Exception failure) {
            if (Thread.currentThread().isInterrupted()) return TransferExecutionResult.RETRY;
            android.util.Log.e("VitalisTransfer", "Transfer writer ownership unavailable");
            return TransferExecutionResult.FAILURE;
        } finally {
            control.finish();
        }
    }

    private TransferExecutionResult runOwned(
            String transferId, ProgressListener progress, File ownedPartial, TransferRunControl control
    ) {
        TransferManifest manifest = null;
        File partial = null;
        try {
            manifest = manifests.read(transferId);
            if (manifest == null) return TransferExecutionResult.FAILURE;
            if (!control.ownsGeneration(manifest.controlGeneration)) return TransferExecutionResult.RETRY;
            if (!boundedPartial(manifest.partialPath).equals(ownedPartial)) {
                throw new SecurityException("Transfer partial identity changed");
            }
            if (TransferManifest.CANCELLED.equals(manifest.state)) {
                return TransferExecutionResult.CANCELLED;
            }
            if (TransferManifest.PAUSED.equals(manifest.state)) {
                return TransferExecutionResult.PAUSED;
            }
            if (TransferManifest.DOWNLOADED.equals(manifest.state)
                    || TransferManifest.VALIDATING.equals(manifest.state)
                    || TransferManifest.READY_TO_INSTALL.equals(manifest.state)
                    || TransferManifest.INSTALLED.equals(manifest.state)) {
                return TransferExecutionResult.SUCCESS;
            }
            if (!TransferManifest.QUEUED.equals(manifest.state)
                    && !TransferManifest.RUNNING.equals(manifest.state)) {
                return TransferExecutionResult.FAILURE;
            }

            partial = boundedPartial(manifest.partialPath);
            long existing = partial.isFile() ? partial.length() : 0L;
            if (existing > manifest.expectedBytes) {
                truncate(partial);
                existing = 0L;
            }
            manifest = progressState(manifest,
                    TransferManifest.RUNNING, existing, manifest.retryCount,
                    null, manifest.entityTag
            );
            manifest = manifests.write(manifest);
            progress.onProgress(manifest);

            for (int attempt = manifest.retryCount;
                 attempt < TransferPolicy.MAX_RETRIES || canVerifyCompletePartial(manifest, partial);
                 attempt++) {
                control.checkStopped();
                TransferExecutionResult stopped = requestedStopResult(transferId);
                if (stopped != null) return stopped;
                try {
                    // Completed crash-recovery files still pass the shared hash check below.
                    TransferOutcome outcome = canVerifyCompletePartial(manifest, partial)
                            ? TransferOutcome.success(manifest.entityTag)
                            : downloadOnce(manifest, partial, progress, control);
                    if (outcome.restartRequired) {
                        truncate(partial);
                        manifest = progressState(manifest,
                                TransferManifest.RUNNING, 0L, attempt + 1,
                                "range_restart", null
                        );
                        manifest = publishProgress(manifest);
                        continue;
                    }
                    if (outcome.retryAfterMillis >= 0L) {
                        manifest = progressState(manifest,
                                TransferManifest.QUEUED, partial.length(), attempt + 1,
                                "transient_http", outcome.entityTag
                        );
                        manifest = publishProgress(manifest);
                        sleepBounded(outcome.retryAfterMillis);
                        continue;
                    }
                    if (!outcome.success) {
                        return fail(manifest, partial, attempt + 1, "http_failure");
                    }
                    if (partial.length() != manifest.expectedBytes) {
                        return fail(manifest, partial, attempt + 1, "truncated_content");
                    }
                    String actualHash = sha256(transferId, partial);
                    if (manifest.expectedSha256 != null
                            && !manifest.expectedSha256.equalsIgnoreCase(actualHash)) {
                        return fail(manifest, partial, attempt + 1, "hash_mismatch");
                    }
                    manifest = progressState(manifest,
                            TransferManifest.DOWNLOADED, partial.length(), attempt,
                            null, outcome.entityTag
                    );
                    manifest = publishProgress(manifest);
                    progress.onProgress(manifest);
                    return TransferExecutionResult.SUCCESS;
                } catch (TransferRunControl.StopRequested requested) {
                    return TransferExecutionResult.RETRY;
                } catch (StopObserved stoppedDuringProgress) {
                    TransferExecutionResult current = requestedStopResult(transferId);
                    return current == null ? TransferExecutionResult.RETRY
                            : current;
                } catch (InterruptedException interrupted) {
                    // File-channel cleanup must run with a clear interrupt flag.
                    Thread.interrupted();
                    try {
                        TransferExecutionResult current = requestedStopResult(transferId);
                        return current == null ? TransferExecutionResult.RETRY
                                : current;
                    } finally {
                        Thread.currentThread().interrupt();
                    }
                } catch (SecurityException rejected) {
                    return fail(manifest, partial, attempt + 1, "security_rejected");
                } catch (InvalidContentRange rejected) {
                    return fail(manifest, partial, attempt + 1, "invalid_content_range");
                } catch (OversizedContent rejected) {
                    return fail(manifest, partial, attempt + 1, "oversized_content");
                } catch (TruncatedContent rejected) {
                    return fail(manifest, partial, attempt + 1, "truncated_content");
                } catch (Exception transientFailure) {
                    if (control.isStopped() || Thread.currentThread().isInterrupted()) return TransferExecutionResult.RETRY;
                    TransferExecutionResult current = requestedStopResult(transferId);
                    if (current != null) return current;
                    TransferManifest latest = manifests.read(transferId);
                    if (latest == null) return TransferExecutionResult.CANCELLED;
                    if (!control.ownsGeneration(latest.controlGeneration)) return TransferExecutionResult.RETRY;
                    manifest = progressState(latest,
                            TransferManifest.QUEUED,
                            partial.isFile() ? partial.length() : 0L,
                            attempt + 1,
                            "transient_network",
                            latest.entityTag
                    );
                    manifest = publishProgress(manifest);
                    if (attempt + 1 >= TransferPolicy.MAX_RETRIES) {
                        return fail(manifest, partial, attempt + 1, "network_exhausted");
                    }
                    sleepBounded(Math.min(
                            TransferPolicy.MAX_RETRY_DELAY_MILLIS,
                            TransferPolicy.MIN_RETRY_DELAY_MILLIS << attempt
                    ));
                }
            }
            return fail(manifest, partial, TransferPolicy.MAX_RETRIES, "retry_exhausted");
        } catch (Exception failure) {
            if (control.isStopped() || Thread.currentThread().isInterrupted()) return TransferExecutionResult.RETRY;
            if (manifest != null && partial != null) {
                try {
                    return fail(
                            manifest,
                            partial,
                            manifest.retryCount,
                            failure instanceof SecurityException
                                    ? "security_rejected"
                                    : "transfer_exception"
                    );
                } catch (Exception persistenceFailure) {
                    return TransferExecutionResult.FAILURE;
                }
            }
            return TransferExecutionResult.FAILURE;
        }
    }

    private boolean canVerifyCompletePartial(TransferManifest manifest, File partial) {
        return manifest.expectedSha256 != null && partial.isFile()
                && partial.length() == manifest.expectedBytes;
    }

    private TransferOutcome downloadOnce(
            TransferManifest manifest,
            File partial,
            ProgressListener progress,
            TransferRunControl control
    ) throws Exception {
        for (;;) {
            control.checkStopped();
            if (requestedStopResult(manifest.transferId) != null) throw new StopObserved();
            long offset = partial.isFile() ? partial.length() : 0L;
            HttpURLConnection connection = open(manifest.sourceUrl, offset, manifest.entityTag, control);
            TransferOutcome outcome;
            try {
                outcome = receive(manifest, partial, progress, offset, connection, control);
            } finally {
                control.closeConnection(connection);
            }
            if (!outcome.moreRanges) return outcome;
            manifest = manifests.read(manifest.transferId);
            if (manifest == null || !control.ownsGeneration(manifest.controlGeneration)) {
                throw new InterruptedException("Transfer ownership changed between ranges");
            }
        }
    }

    private TransferOutcome receive(TransferManifest manifest, File partial,
                                     ProgressListener progress, long offset,
                                     HttpURLConnection connection, TransferRunControl control) throws Exception {
        control.checkStopped();
        int status = connection.getResponseCode();
        String entityTag = connection.getHeaderField("ETag");
        if (status == 429 || (status >= 500 && status <= 599)) {
            long delay = retryAfterMillis(connection.getHeaderField("Retry-After"));
            // Error-page validators do not describe the partial artifact on disk.
            return TransferOutcome.retry(delay, manifest.entityTag);
        }
        if (status == 416) {
            String header = connection.getHeaderField("Content-Range");
            java.util.regex.Matcher range = java.util.regex.Pattern
                    .compile("(?i:bytes) \\*/([0-9]+)").matcher(header == null ? "" : header.trim());
            if (offset != manifest.expectedBytes || !range.matches()) throw new InvalidContentRange();
            try {
                if (Long.parseLong(range.group(1)) != manifest.expectedBytes) throw new InvalidContentRange();
            } catch (NumberFormatException malformed) {
                throw new InvalidContentRange();
            }
            if (isStrongEntityTag(manifest.entityTag) && manifest.entityTag.equals(entityTag)) {
                return TransferOutcome.success(entityTag);
            }
            return TransferOutcome.restart();
        }
        if (offset > 0L && status != HttpURLConnection.HTTP_PARTIAL) {
            return TransferOutcome.restart();
        }
        if (offset > 0L && manifest.entityTag != null && entityTag != null
                && !manifest.entityTag.equals(entityTag)) {
            return TransferOutcome.restart();
        }
        if (status < 200 || status >= 300) {
            return TransferOutcome.failure();
        }
        long responseEnd = manifest.expectedBytes;
        if (status == HttpURLConnection.HTTP_PARTIAL) {
            responseEnd = validateContentRange(connection, offset, manifest.expectedBytes);
            if (entityTag == null && offset > 0L && isStrongEntityTag(manifest.entityTag)) {
                // A validated conditional suffix retains its prior representation identity.
                entityTag = manifest.entityTag;
            }
        }

        File parent = partial.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IllegalStateException("Unable to create transfer directory");
        }
        TransferManifest current = progressState(manifest,
                TransferManifest.RUNNING, offset, manifest.retryCount, null, entityTag
        );
        // Bind even a sub-checkpoint partial to its representation before writing bytes.
        current = publishProgress(current);
        long persistedAt = offset;
        try (BufferedInputStream input = new BufferedInputStream(connection.getInputStream());
             FileOutputStream output = new FileOutputStream(partial, offset > 0L)) {
            byte[] buffer = new byte[TransferPolicy.BUFFER_BYTES];
            long total = offset;
            while (true) {
                control.checkStopped();
                TransferExecutionResult stopped = requestedStopResult(manifest.transferId);
                if (stopped != null) throw new InterruptedException(stopped.name());
                int read = input.read(buffer);
                control.checkStopped();
                if (read < 0) break;
                if (read > responseEnd - total) throw new OversizedContent();
                output.write(buffer, 0, read);
                total += read;
                if (total - persistedAt >= TransferPolicy.PROGRESS_CHECKPOINT_BYTES) {
                    current = progressState(current,
                            TransferManifest.RUNNING, total, current.retryCount,
                            null, entityTag
                    );
                    current = publishProgress(current);
                    progress.onProgress(current);
                    persistedAt = total;
                }
            }
            output.flush();
            output.getFD().sync();
        }
        if (partial.length() != responseEnd) throw new TruncatedContent();
        current = progressState(current,
                TransferManifest.RUNNING, partial.length(), current.retryCount,
                null, entityTag
        );
        current = publishProgress(current);
        progress.onProgress(current);
        return responseEnd < manifest.expectedBytes
                ? TransferOutcome.moreRanges(entityTag) : TransferOutcome.success(entityTag);
    }

    private long validateContentRange(HttpURLConnection connection, long offset, long expectedBytes)
            throws InvalidContentRange {
        String header = connection.getHeaderField("Content-Range");
        if (header == null) throw new InvalidContentRange();
        java.util.regex.Matcher range = java.util.regex.Pattern
                .compile("(?i:bytes) ([0-9]+)-([0-9]+)/([0-9]+)").matcher(header.trim());
        if (!range.matches()) throw new InvalidContentRange();
        try {
            long start = Long.parseLong(range.group(1));
            long end = Long.parseLong(range.group(2));
            long total = Long.parseLong(range.group(3));
            if (start != offset || total != expectedBytes || start > end || end >= total) {
                throw new InvalidContentRange();
            }
            long contentLength = connection.getContentLengthLong();
            if (contentLength >= 0L && contentLength != end - start + 1L) {
                throw new InvalidContentRange();
            }
            return end + 1L;
        } catch (NumberFormatException malformed) {
            throw new InvalidContentRange();
        }
    }

    private static final class InvalidContentRange extends Exception {}
    private static final class OversizedContent extends Exception {}
    private static final class TruncatedContent extends Exception {}

    private boolean isStrongEntityTag(String value) {
        return value != null && value.matches("\"[\\x21\\x23-\\x7E\\x80-\\xFF]*\"");
    }

    private HttpURLConnection open(String source, long offset, String entityTag,
                                   TransferRunControl control) throws Exception {
        URI current = URI.create(source);
        for (int redirects = 0; redirects <= TransferPolicy.MAX_REDIRECTS; redirects++) {
            validateRemote(current);
            control.checkStopped();
            control.checkConnectionAvailable();
            HttpURLConnection connection = connections.open(current);
            control.attach(connection);
            boolean handedOff = false;
            try {
                control.checkStopped();
                connection.setInstanceFollowRedirects(false);
                connection.setConnectTimeout(TransferPolicy.CONNECT_TIMEOUT_MILLIS);
                connection.setReadTimeout(TransferPolicy.READ_TIMEOUT_MILLIS);
                connection.setRequestProperty("Accept-Encoding", "identity");
                connection.setRequestProperty("User-Agent", "VITALIS-Android-Model-Transfer");
                if (offset > 0L) {
                    connection.setRequestProperty("Range", "bytes=" + offset + "-");
                    // RFC 9110: If-Range requires one syntactically valid strong entity tag.
                    if (isStrongEntityTag(entityTag)) {
                        connection.setRequestProperty("If-Range", entityTag);
                    }
                }
                int status = connection.getResponseCode();
                control.checkStopped();
                if (status < 300 || status > 399) {
                    handedOff = true;
                    return connection;
                }
                String location = connection.getHeaderField("Location");
                if (location == null) throw new SecurityException("Redirect had no destination");
                current = current.resolve(location);
            } finally {
                if (!handedOff) control.closeConnection(connection);
            }
        }
        throw new SecurityException("Too many transfer redirects");
    }

    private void validateRemote(URI value) {
        String host = value.getHost();
        String normalized = host == null ? "" : host.toLowerCase(Locale.ROOT);
        boolean approved = normalized.equals("huggingface.co")
                || normalized.endsWith(".huggingface.co")
                || normalized.equals("hf.co")
                || normalized.endsWith(".hf.co");
        if (!"https".equals(value.getScheme()) || !approved
                || value.getUserInfo() != null || value.getFragment() != null) {
            throw new SecurityException("Unapproved transfer destination");
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

    private TransferExecutionResult fail(
            TransferManifest manifest,
            File partial,
            int retries,
            String reason
    ) throws Exception {
        TransferFailureCode code = failureCode(reason);
        TransferManifest failed = progressState(manifest,
                TransferManifest.FAILED,
                partial.isFile() ? partial.length() : 0L,
                retries,
                reason,
                manifest.entityTag
        );
        TransferManifest retained = manifests.update(manifest.transferId, current -> {
            if (blocksProgress(current)) return current;
            return current.withProgressAt(failed.state, failed.downloadedBytes,
                    failed.retryCount, failed.stopReason, current.entityTag, failed.updatedAtMillis)
                    .withFailure(code, reason);
        });
        TransferExecutionResult stopped = requestedStopResult(manifest.transferId);
        if (stopped != null) return stopped;
        return retained != null && retained.shouldReschedule()
                ? TransferExecutionResult.RETRY : TransferExecutionResult.FAILURE;
    }

    private TransferExecutionResult requestedStopResult(String transferId) throws Exception {
        TransferManifest value = manifests.read(transferId);
        if (value == null) return TransferExecutionResult.CANCELLED;
        if (TransferManifest.PAUSED.equals(value.state)) return TransferExecutionResult.PAUSED;
        if (TransferManifest.CANCELLED.equals(value.state)) return TransferExecutionResult.CANCELLED;
        return null;
    }

    private boolean blocksProgress(TransferManifest manifest) {
        return manifest.shouldReschedule()
                || (!TransferManifest.RUNNING.equals(manifest.state)
                && !TransferManifest.QUEUED.equals(manifest.state));
    }

    private TransferManifest publishProgress(TransferManifest proposed) throws Exception {
        TransferManifest current = manifests.update(proposed.transferId, latest -> {
            if (blocksProgress(latest)) return latest;
            return latest.withProgressAt(proposed.state, proposed.downloadedBytes,
                    proposed.retryCount, proposed.stopReason, proposed.entityTag,
                    proposed.updatedAtMillis);
        });
        if (current == null || current.shouldReschedule()
                || !proposed.state.equals(current.state)) throw new StopObserved();
        return current;
    }

    private static final class StopObserved extends Exception {}

    private TransferFailureCode failureCode(String reason) {
        if ("security_rejected".equals(reason)) return TransferFailureCode.SECURITY_REJECTED;
        if ("http_failure".equals(reason)) return TransferFailureCode.HTTP_FAILURE;
        if ("invalid_content_range".equals(reason)) return TransferFailureCode.INVALID_CONTENT_RANGE;
        if ("oversized_content".equals(reason)) return TransferFailureCode.OVERSIZED_CONTENT;
        if ("truncated_content".equals(reason)) return TransferFailureCode.TRUNCATED_CONTENT;
        if ("hash_mismatch".equals(reason)) return TransferFailureCode.HASH_MISMATCH;
        if ("network_exhausted".equals(reason)) return TransferFailureCode.NETWORK_EXHAUSTED;
        if ("retry_exhausted".equals(reason)) return TransferFailureCode.RETRY_EXHAUSTED;
        return TransferFailureCode.TRANSFER_EXCEPTION;
    }

    private void truncate(File file) throws Exception {
        File parent = file.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IllegalStateException("Unable to create transfer directory");
        }
        try (FileOutputStream output = new FileOutputStream(file, false)) {
            output.getFD().sync();
        }
    }

    private String sha256(String transferId, File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[TransferPolicy.BUFFER_BYTES];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                if (requestedStopResult(transferId) != null) {
                    throw new InterruptedException("Transfer stopped while hashing");
                }
                digest.update(buffer, 0, read);
            }
        }
        StringBuilder value = new StringBuilder();
        for (byte item : digest.digest()) value.append(String.format(Locale.ROOT, "%02x", item));
        return value.toString();
    }

    private long retryAfterMillis(String value) {
        if (value == null) return TransferPolicy.MIN_RETRY_DELAY_MILLIS;
        try {
            return Math.min(
                    TransferPolicy.MAX_RETRY_DELAY_MILLIS,
                    Math.max(TransferPolicy.MIN_RETRY_DELAY_MILLIS,
                            java.util.concurrent.TimeUnit.SECONDS.toMillis(Long.parseLong(value)))
            );
        } catch (NumberFormatException ignored) {
            try {
                long requested = ZonedDateTime.parse(
                        value,
                        DateTimeFormatter.RFC_1123_DATE_TIME
                ).toInstant().toEpochMilli() - clock.nowMillis();
                return Math.min(
                        TransferPolicy.MAX_RETRY_DELAY_MILLIS,
                        Math.max(TransferPolicy.MIN_RETRY_DELAY_MILLIS, requested)
                );
            } catch (Exception invalidDate) {
                return TransferPolicy.MIN_RETRY_DELAY_MILLIS;
            }
        }
    }

    private void sleepBounded(long milliseconds) throws InterruptedException {
        sleeper.sleep(Math.min(
                TransferPolicy.MAX_RETRY_DELAY_MILLIS,
                Math.max(0L, milliseconds)
        ));
    }

    private TransferManifest progressState(
            TransferManifest manifest,
            String state,
            long bytes,
            int retries,
            String reason,
            String entityTag
    ) {
        return manifest.withProgressAt(
                state, bytes, retries, reason, entityTag, clock.nowMillis()
        );
    }

    private static final class TransferOutcome {
        final boolean success;
        final boolean restartRequired;
        final long retryAfterMillis;
        final String entityTag;
        final boolean moreRanges;

        private TransferOutcome(boolean success, boolean restart, long retry, String tag) {
            this(success, restart, retry, tag, false);
        }

        private TransferOutcome(boolean success, boolean restart, long retry, String tag, boolean more) {
            this.success = success;
            restartRequired = restart;
            retryAfterMillis = retry;
            entityTag = tag;
            moreRanges = more;
        }

        static TransferOutcome success(String tag) { return new TransferOutcome(true, false, -1L, tag); }
        static TransferOutcome moreRanges(String tag) { return new TransferOutcome(true, false, -1L, tag, true); }
        static TransferOutcome failure() { return new TransferOutcome(false, false, -1L, null); }
        static TransferOutcome restart() { return new TransferOutcome(false, true, -1L, null); }
        static TransferOutcome retry(long delay, String tag) { return new TransferOutcome(false, false, delay, tag); }
    }
}
