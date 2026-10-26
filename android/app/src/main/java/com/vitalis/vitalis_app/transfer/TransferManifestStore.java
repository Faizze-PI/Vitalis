package com.vitalis.vitalis_app.transfer;

import android.content.Context;

import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.LinkOption;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantLock;

/** Persists transfer state with fsync and same-directory atomic replacement. */
public final class TransferManifestStore {
    private static final long MAX_MANIFEST_BYTES = 1024L * 1024L; // hardcode: HC-065
    private static final ConcurrentHashMap<String, ReentrantLock> LOCKS = new ConcurrentHashMap<>();
    private final File directory;

    public TransferManifestStore(Context context) {
        directory = new File(context.getFilesDir(), "transfers");
    }

    public TransferManifest write(TransferManifest manifest) throws Exception {
        return locked(manifest.transferId, destination -> {
            TransferManifest current = readUnlocked(destination);
            verifyIdentity(current, manifest);
            if (manifest.stateRevision != (current == null ? 0L : current.stateRevision)) {
                throw new IOException("Transfer manifest revision conflict");
            }
            return replace(destination, current, manifest);
        });
    }

    public interface Transition {
        TransferManifest apply(TransferManifest current) throws Exception;
    }

    /** The transition sees the latest record under both VM and process locks. */
    public TransferManifest update(String transferId, Transition transition) throws Exception {
        return locked(transferId, destination -> {
            TransferManifest current = readUnlocked(destination);
            if (current == null) return null;
            TransferManifest next = transition.apply(current);
            if (next == current) return current;
            verifyIdentity(current, next);
            if (next.stateRevision != current.stateRevision) {
                throw new IOException("Transfer manifest revision conflict");
            }
            return replace(destination, current, next);
        });
    }

    private TransferManifest replace(File destination, TransferManifest current,
                                     TransferManifest next) throws Exception {
        TransferManifest stored = next.withStateRevision(Math.addExact(
                current == null ? 0L : current.stateRevision, 1L));
        File temporary = new File(directory, destination.getName() + ".tmp");
        byte[] bytes = stored.toJson().toString().getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_MANIFEST_BYTES) throw new IOException("Transfer manifest too large");
        try (FileChannel output = FileChannel.open(temporary.toPath(),
                StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING,
                StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS)) {
            ByteBuffer buffer = ByteBuffer.wrap(bytes);
            while (buffer.hasRemaining()) output.write(buffer);
            output.force(true);
        }
        Files.move(
                temporary.toPath(),
                destination.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE
        );
        return stored;
    }

    public TransferManifest read(String transferId) throws Exception {
        return locked(transferId, this::readUnlocked);
    }

    private TransferManifest readUnlocked(File source) throws Exception {
        if (!source.isFile()) return null;
        byte[] bytes;
        try (FileChannel input = FileChannel.open(source.toPath(),
                StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)) {
            long size = input.size();
            if (size <= 0L || size > MAX_MANIFEST_BYTES) {
                throw new IOException("Transfer manifest size is invalid");
            }
            bytes = new byte[(int) size];
            ByteBuffer buffer = ByteBuffer.wrap(bytes);
            while (buffer.hasRemaining()) {
                int read = input.read(buffer);
                if (read < 0) throw new IllegalStateException("Truncated transfer manifest");
            }
        }
        TransferManifest manifest = TransferManifest.fromJson(
                new JSONObject(new String(bytes, StandardCharsets.UTF_8))
        );
        if (!source.getName().equals(manifest.transferId + ".json")) {
            throw new SecurityException("Transfer manifest identity mismatch");
        }
        return manifest;
    }

    public List<TransferManifest> list() throws Exception {
        ensureDirectory();
        List<TransferManifest> values = new ArrayList<>();
        File[] files = directory.listFiles((ignored, name) -> name.endsWith(".json"));
        if (files == null) return values;
        for (File file : files) {
            String name = file.getName();
            TransferManifest current = read(name.substring(0, name.length() - 5));
            if (current != null) values.add(current);
        }
        return values;
    }

    public void delete(String transferId) throws Exception {
        locked(transferId, manifest -> {
            if (manifest.exists() && !manifest.delete()) {
                throw new IOException("Unable to remove transfer manifest");
            }
            return null;
        });
    }

    private interface Operation<T> { T run(File destination) throws Exception; }

    private <T> T locked(String transferId, Operation<T> operation) throws Exception {
        File destination = fileFor(transferId);
        String identity = destination.getCanonicalPath();
        ReentrantLock local = LOCKS.computeIfAbsent(identity, ignored -> new ReentrantLock());
        local.lock();
        try (FileChannel channel = FileChannel.open(new File(identity + ".writer.lock").toPath(),
                StandardOpenOption.CREATE, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS);
             FileLock ignored = channel.lock()) {
            return operation.run(destination);
        } finally {
            // Keep the lock inode and VM coordinator stable for other waiters.
            local.unlock();
        }
    }

    private void verifyIdentity(TransferManifest current, TransferManifest next) {
        if (current == null) return;
        if (!Objects.equals(current.transferId, next.transferId)
                || !Objects.equals(current.jobId, next.jobId)
                || !Objects.equals(current.modelId, next.modelId)
                || !Objects.equals(current.repository, next.repository)
                || !Objects.equals(current.revision, next.revision)
                || !Objects.equals(current.sourceUrl, next.sourceUrl)
                || !Objects.equals(current.partialPath, next.partialPath)
                || !Objects.equals(current.finalPath, next.finalPath)
                || current.artifactIndex != next.artifactIndex
                || current.shardCount != next.shardCount
                || current.expectedBytes != next.expectedBytes
                || !Objects.equals(current.expectedSha256, next.expectedSha256)
                || !Objects.equals(current.expectedHashAuthority, next.expectedHashAuthority)
                || current.createdAtMillis != next.createdAtMillis) {
            throw new SecurityException("Transfer identity collision");
        }
    }

    private File fileFor(String transferId) throws Exception {
        if (!transferId.matches("[A-Za-z0-9_.-]{1,160}")) {
            throw new SecurityException("Invalid transfer identity");
        }
        ensureDirectory();
        File file = new File(directory, transferId + ".json");
        String root = directory.getCanonicalPath() + File.separator;
        if (!file.getCanonicalPath().startsWith(root)) {
            throw new SecurityException("Transfer manifest escaped storage boundary");
        }
        return file;
    }

    private void ensureDirectory() throws Exception {
        if (!directory.isDirectory() && !directory.mkdirs() && !directory.isDirectory()) {
            throw new IllegalStateException("Unable to create transfer storage");
        }
    }
}
