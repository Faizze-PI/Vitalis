package com.vitalis.vitalis_app.transfer;

import java.io.File;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.file.LinkOption;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import java.util.HashSet;
import java.util.Set;

/** Exclusive writer/cleanup authority for a canonical partial, including across processes. */
final class TransferWriterLease implements AutoCloseable {
    // Do not open competing channels inside this VM: on some systems closing
    // any channel for a locked file can release that VM's other locks.
    private static final Set<String> OWNED = new HashSet<>();
    private final String identity;
    private final FileChannel channel;
    private boolean closed;

    private TransferWriterLease(String identity, FileChannel channel) {
        this.identity = identity;
        this.channel = channel;
    }

    static synchronized TransferWriterLease tryAcquire(File partial) throws IOException {
        File canonical = partial.getCanonicalFile();
        String identity = canonical.getPath();
        if (OWNED.contains(identity)) return null;
        File lockFile = new File(identity + ".writer.lock");
        Files.createDirectories(lockFile.getParentFile().toPath());
        FileChannel channel = FileChannel.open(lockFile.toPath(),
                StandardOpenOption.CREATE, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS);
        try {
            FileLock lock = channel.tryLock();
            if (lock == null) {
                channel.close();
                return null;
            }
            OWNED.add(identity);
            return new TransferWriterLease(identity, channel);
        } catch (IOException | RuntimeException failure) {
            try {
                channel.close();
            } catch (IOException closeFailure) {
                failure.addSuppressed(closeFailure);
            }
            throw failure;
        }
    }

    @Override
    public void close() throws IOException {
        synchronized (TransferWriterLease.class) {
            if (closed) return;
            try {
                // Closing releases the OS lease. Never delete its stable inode:
                // another process may already have the same lock file open.
                channel.close();
            } finally {
                if (!channel.isOpen()) {
                    closed = true;
                    OWNED.remove(identity);
                }
            }
        }
    }
}
