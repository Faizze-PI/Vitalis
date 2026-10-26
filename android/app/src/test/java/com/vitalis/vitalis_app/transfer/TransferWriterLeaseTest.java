package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.*;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

public final class TransferWriterLeaseTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();

    @Test
    public void rejectedOverlappingOsLeaseDoesNotPoisonLaterOwnership() throws Exception {
        File partial = temporary.newFile("overlapping.gguf.part");
        java.nio.file.Files.write(partial.toPath(), new byte[] {112});
        File lockFile = new File(partial.getCanonicalPath() + ".writer.lock");
        try (var channel = java.nio.channels.FileChannel.open(lockFile.toPath(),
                java.nio.file.StandardOpenOption.CREATE, java.nio.file.StandardOpenOption.WRITE);
             var held = channel.lock()) {
            assertThrows(java.nio.channels.OverlappingFileLockException.class,
                    () -> TransferWriterLease.tryAcquire(partial));
            assertArrayEquals(new byte[] {112}, java.nio.file.Files.readAllBytes(partial.toPath()));
        }
        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
            assertNotNull("rejected acquisition must not retain VM ownership", lease);
            assertNull(TransferWriterLease.tryAcquire(partial));
        }
    }

    @Test
    public void parentOwnershipRejectsSeparateProcessThenAllowsItAfterClose() throws Exception {
        File partial = new File(temporary.getRoot(), "model.gguf.part");
        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
            assertNotNull(lease);
            assertEquals("BUSY", invoke(partial));
            assertNull(TransferWriterLease.tryAcquire(new File(temporary.getRoot(), "./model.gguf.part")));
        }
        assertEquals("ACQUIRED", invoke(partial));
    }

    @Test
    public void childOwnershipSurvivesRejectedParentAcquisitionUntilChildStops() throws Exception {
        File partial = new File(temporary.getRoot(), "model.gguf.part");
        File output = temporary.newFile();
        Process child = start(partial, output, true);
        try {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20);
            while (!"ACQUIRED".equals(read(output).trim()) && child.isAlive()
                    && System.nanoTime() < deadline) {
                Thread.sleep(10);
            }
            assertEquals(read(new File(output.getPath() + ".stderr")), "ACQUIRED", read(output).trim());
            assertNull(TransferWriterLease.tryAcquire(partial));
            assertNull(TransferWriterLease.tryAcquire(partial));
            child.getOutputStream().write(1);
            child.getOutputStream().flush();
            assertTrue(child.waitFor(20, TimeUnit.SECONDS));
            assertEquals(read(new File(output.getPath() + ".stderr")), 0, child.exitValue());
            try (TransferWriterLease lease = TransferWriterLease.tryAcquire(partial)) {
                assertNotNull(lease);
                lease.close();
                lease.close();
            }
        } finally {
            if (child.isAlive()) {
                child.destroyForcibly();
                assertTrue(child.waitFor(20, TimeUnit.SECONDS));
            }
        }
    }

    private String invoke(File partial) throws Exception {
        File output = temporary.newFile();
        Process child = start(partial, output, false);
        try {
            assertTrue(child.waitFor(20, TimeUnit.SECONDS));
            assertEquals(read(output) + read(new File(output.getPath() + ".stderr")), 0, child.exitValue());
            return read(output).trim();
        } finally {
            if (child.isAlive()) {
                child.destroyForcibly();
                assertTrue(child.waitFor(20, TimeUnit.SECONDS));
            }
        }
    }

    private String read(File output) throws Exception {
        return new String(java.nio.file.Files.readAllBytes(output.toPath()), StandardCharsets.UTF_8);
    }

    private Process start(File partial, File output, boolean hold) throws Exception {
        String executable = new File(System.getProperty("java.home"),
                "bin/" + (System.getProperty("os.name").startsWith("Windows") ? "java.exe" : "java")).getPath();
        String classpath = new File(WriterLeaseProcessProbe.class.getProtectionDomain()
                .getCodeSource().getLocation().toURI()).getPath() + File.pathSeparator
                + new File(TransferWriterLease.class.getProtectionDomain()
                .getCodeSource().getLocation().toURI()).getPath();
        ProcessBuilder builder = new ProcessBuilder(executable, "-cp", classpath,
                WriterLeaseProcessProbe.class.getName(), partial.getPath(), hold ? "hold" : "");
        // A non-holding probe receives EOF rather than a byte when it acquires.
        Process child = builder.redirectError(new File(output.getPath() + ".stderr"))
                .redirectOutput(output).start();
        if (!hold) child.getOutputStream().close();
        return child;
    }
}
