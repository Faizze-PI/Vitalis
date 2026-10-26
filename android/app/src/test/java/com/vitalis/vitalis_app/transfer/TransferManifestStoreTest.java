package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.json.JSONObject;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public final class TransferManifestStoreTest {
    private Context context;
    private TransferManifestStore store;

    @Before
    public void setUp() throws Exception {
        context = ApplicationProvider.getApplicationContext();
        store = new TransferManifestStore(context);
        store.delete("revision-test");
    }

    @Test
    public void listingIgnoresStagingFilesAndRetainsOnlyDurableRecords() throws Exception {
        store.write(manifest("listed-job"));
        File staging = new File(context.getFilesDir(), "transfers/unfinished.json.tmp");
        Files.write(staging.toPath(), new byte[] {123});
        try {
            var listed = new TransferManifestStore(context).list();
            assertEquals(1, listed.size());
            assertEquals("revision-test", listed.get(0).transferId);
            assertEquals("listed-job", listed.get(0).jobId);
            assertTrue(staging.isFile());
        } finally {
            Files.deleteIfExists(staging.toPath());
        }
    }

    @Test
    public void missingUpdateCannotCreateARecordOrInvokeItsTransition() throws Exception {
        org.junit.Assert.assertNull(store.update("not-created", current -> {
            throw new AssertionError("missing record must not enter transition");
        }));
        assertFalse(new File(context.getFilesDir(), "transfers/not-created.json").exists());
    }

    @Test
    public void transitionWithInventedRevisionCannotReplaceDurableData() throws Exception {
        TransferManifest before = store.write(manifest("retained-job"));
        assertThrows(IOException.class, () -> store.update("revision-test",
                current -> current.withStateRevision(current.stateRevision + 1L)));
        TransferManifest after = store.read("revision-test");
        assertEquals(before.stateRevision, after.stateRevision);
        assertEquals("retained-job", after.jobId);
        assertEquals(TransferManifest.QUEUED, after.state);
    }

    @Test
    public void emptyOrOversizedManifestFailsWithoutReplacingItsBytes() throws Exception {
        File destination = new File(context.getFilesDir(), "transfers/revision-test.json");
        for (long size : new long[] {0L, 1024L * 1024L + 1L}) {
            try (var fixture = new java.io.RandomAccessFile(destination, "rw")) {
                fixture.setLength(size);
            }
            try {
                assertThrows(IOException.class, () -> store.read("revision-test"));
                assertEquals(size, destination.length());
            } finally {
                Files.deleteIfExists(destination.toPath());
            }
        }
    }

    @Test
    public void unavailableStorageDirectoryFailsWithoutChangingTheBlockingFile() throws Exception {
        File blocked = new File(context.getCacheDir(), "manifest-storage-blocker");
        Files.write(blocked.toPath(), new byte[] {115});
        Context adapter = new android.content.ContextWrapper(context) {
            @Override public File getFilesDir() { return blocked; }
        };
        try {
            assertThrows(IllegalStateException.class, () -> new TransferManifestStore(adapter).list());
            org.junit.Assert.assertArrayEquals(new byte[] {115}, Files.readAllBytes(blocked.toPath()));
        } finally {
            Files.deleteIfExists(blocked.toPath());
        }
    }

    @Test
    public void mismatchedManifestIdentityCannotDeleteAnotherPartial() throws Exception {
        File unrelated = new File(context.getFilesDir(), "models/manifest-unrelated-fixture.gguf.part");
        Files.createDirectories(unrelated.getParentFile().toPath());
        Files.write(unrelated.toPath(), "unrelated-preserved".getBytes(StandardCharsets.UTF_8));
        JSONObject corrupt = manifest("job").toJson();
        corrupt.put("transferId", "foreign-transfer");
        corrupt.put("partialPath", unrelated.getPath());
        corrupt.put("finalPath", unrelated.getPath().replaceFirst("\\.part$", ""));
        File destination = new File(context.getFilesDir(), "transfers/revision-test.json");
        Files.write(destination.toPath(), corrupt.toString().getBytes(StandardCharsets.UTF_8));
        Exception rejected = null;
        try {
            new TransferController(context).stop("revision-test", true);
        } catch (Exception failure) {
            rejected = failure;
        }
        assertTrue("a manifest identity mismatch must never delete another partial", unrelated.isFile());
        assertTrue(rejected instanceof SecurityException);
        assertEquals("unrelated-preserved", new String(Files.readAllBytes(unrelated.toPath()), StandardCharsets.UTF_8));
    }

    @Test
    public void atomicUpdatesAcrossInstancesKeepAllProgressAndRevisions() throws Exception {
        store.write(manifest("job"));
        TransferManifestStore other = new TransferManifestStore(context);
        ExecutorService workers = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            Future<?> first = workers.submit(() -> increment(store, start));
            Future<?> second = workers.submit(() -> increment(other, start));
            start.countDown();
            first.get(20, TimeUnit.SECONDS);
            second.get(20, TimeUnit.SECONDS);
            TransferManifest result = new TransferManifestStore(context).read("revision-test");
            assertEquals(20L, result.downloadedBytes);
            assertEquals(21L, result.toJson().getLong("stateRevision"));
        } finally {
            workers.shutdownNow();
            assertTrue(workers.awaitTermination(20, TimeUnit.SECONDS));
        }
    }

    @Test
    public void legacyManifestWithoutStateRevisionUpgradesWithoutChangingIdentity() throws Exception {
        JSONObject legacy = manifest("legacy-job").toJson();
        legacy.remove("stateRevision");
        File destination = new File(context.getFilesDir(), "transfers/revision-test.json");
        Files.write(destination.toPath(), legacy.toString().getBytes(StandardCharsets.UTF_8));
        store.update("revision-test", current -> current.withStopRequest(false));
        TransferManifest result = store.read("revision-test");
        assertEquals("legacy-job", result.jobId);
        assertEquals(TransferManifest.PAUSED, result.state);
        assertEquals(1L, result.toJson().getLong("stateRevision"));
    }

    @Test
    public void separateProcessLeaseBlocksManifestUpdateUntilReleased() throws Exception {
        store.write(manifest("job"));
        File manifest = new File(context.getFilesDir(), "transfers/revision-test.json");
        File output = File.createTempFile("manifest-lock", ".log", context.getCacheDir());
        String executable = new File(System.getProperty("java.home"),
                "bin/" + (System.getProperty("os.name").startsWith("Windows") ? "java.exe" : "java")).getPath();
        String classpath = classpathFor(WriterLeaseProcessProbe.class)
                + File.pathSeparator + classpathFor(TransferWriterLease.class);
        Process child = new ProcessBuilder(executable, "-cp", classpath,
                WriterLeaseProcessProbe.class.getName(), manifest.getPath(), "hold")
                .redirectError(new File(output.getPath() + ".stderr")).redirectOutput(output).start();
        ExecutorService worker = Executors.newSingleThreadExecutor();
        try {
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20);
            while (!"ACQUIRED".equals(readOutput(output))
                    && child.isAlive() && System.nanoTime() < deadline) Thread.sleep(10);
            assertEquals(readOutput(new File(output.getPath() + ".stderr")), "ACQUIRED", readOutput(output));
            CountDownLatch entered = new CountDownLatch(1);
            Future<TransferManifest> pending = worker.submit(() -> {
                entered.countDown();
                return store.update("revision-test", current -> current.withStopRequest(true));
            });
            assertTrue(entered.await(20, TimeUnit.SECONDS));
            assertThrows(TimeoutException.class, () -> pending.get(100, TimeUnit.MILLISECONDS));
            child.getOutputStream().write(1);
            child.getOutputStream().flush();
            assertTrue(child.waitFor(20, TimeUnit.SECONDS));
            assertEquals(readOutput(new File(output.getPath() + ".stderr")), 0, child.exitValue());
            assertEquals(TransferManifest.CANCELLED, pending.get(20, TimeUnit.SECONDS).state);
            assertEquals(2L, store.read("revision-test").stateRevision);
        } finally {
            if (child.isAlive()) {
                child.destroyForcibly();
                assertTrue(child.waitFor(20, TimeUnit.SECONDS));
            }
            worker.shutdownNow();
            assertTrue(worker.awaitTermination(20, TimeUnit.SECONDS));
        }
    }

    private void increment(TransferManifestStore target, CountDownLatch start) {
        try {
            start.await();
            for (int index = 0; index < 10; index++) {
                target.update("revision-test", current -> current.withProgress(
                        TransferManifest.RUNNING, current.downloadedBytes + 1L,
                        current.retryCount, null, current.entityTag));
            }
        } catch (Exception failure) {
            throw new AssertionError(failure);
        }
    }

    private String readOutput(File file) throws IOException {
        return new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8).trim();
    }

    private String classpathFor(Class<?> type) throws Exception {
        String name = type.getName().replace('.', '/') + ".class";
        java.net.URL resource = type.getClassLoader().getResource(name);
        if (resource == null) throw new IOException("Missing child-process fixture class");
        if (resource.getProtocol().equals("jar")) {
            java.net.JarURLConnection jar = (java.net.JarURLConnection) resource.openConnection();
            return new File(jar.getJarFileURL().toURI()).getPath();
        }
        if (!resource.getProtocol().equals("file")) throw new IOException("Unsupported fixture location");
        String path = new File(resource.toURI()).getPath();
        return path.substring(0, path.length() - name.length());
    }

    @Test
    public void staleProgressCannotReplaceAnotherStoreStopRequest() throws Exception {
        store.write(manifest("job"));
        TransferManifest stale = store.read("revision-test");
        TransferManifestStore control = new TransferManifestStore(context);
        control.write(control.read("revision-test").withStopRequest(true));

        assertThrows(IOException.class, () -> store.write(stale.withProgress(
                TransferManifest.RUNNING, 9L, 0, null, "old-validator")));

        TransferManifest retained = control.read("revision-test");
        assertEquals(TransferManifest.CANCELLED, retained.state);
        assertFalse(retained.stopAcknowledged);
    }

    @Test
    public void identityCollisionCannotReplaceExistingManifest() throws Exception {
        store.write(manifest("original-job"));
        assertThrows(SecurityException.class, () -> store.write(manifest("other-job")));
        assertEquals("original-job", store.read("revision-test").jobId);
    }

    private TransferManifest manifest(String job) {
        File partial = new File(context.getFilesDir(), "models/revision-test.gguf.part");
        return new TransferManifest("revision-test", job, "model", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                partial.getPath(), 20L, null, 0L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L);
    }
}
