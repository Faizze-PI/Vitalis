package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.*;
import android.content.Context;
import android.os.Looper;
import android.os.storage.StorageManager;
import androidx.test.core.app.ApplicationProvider;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28, shadows = TransferStoragePreflightTest.StorageShadow.class)
public final class TransferStoragePreflightTest {
    @Implements(StorageManager.class)
    public static class StorageShadow {
        static long bytes;
        static int calls;
        static File destination;
        static String failure;
        static final UUID VOLUME = UUID.fromString("00000000-0000-0000-0000-000000000123");
        @Implementation protected UUID getUuidForPath(File path) throws IOException {
            destination = path;
            if ("path".equals(failure)) throw new IOException("private-path-must-not-escape");
            return VOLUME;
        }
        @Implementation protected long getAllocatableBytes(UUID volume) throws IOException {
            assertEquals(VOLUME, volume);
            assertNotSame(Looper.getMainLooper(), Looper.myLooper());
            calls++;
            if ("io".equals(failure)) throw new IOException("private-storage-detail");
            if ("security".equals(failure)) throw new SecurityException("private-storage-detail");
            return bytes;
        }
    }

    @Before public void reset() {
        StorageShadow.bytes = 123456L;
        StorageShadow.calls = 0;
        StorageShadow.destination = null;
        StorageShadow.failure = null;
    }

    @Test public void backgroundQueryUsesApplicationStorageVolume() throws Exception {
        Result result = background("allocatableBytes");
        assertEquals(123456L, result.value);
        assertNull(result.code);
        assertEquals(1, StorageShadow.calls);
        Context context = ApplicationProvider.getApplicationContext();
        assertEquals(context.getFilesDir(), StorageShadow.destination);
    }

    @Test public void zeroIsKnownButNegativeIsUnknown() throws Exception {
        StorageShadow.bytes = 0;
        assertEquals(0L, background("allocatableBytes").value);
        StorageShadow.bytes = -1;
        Result invalid = background("allocatableBytes");
        assertEquals("storage_unavailable", invalid.code);
        assertNull(invalid.value);
    }

    @Test public void mainThreadIsRejectedWithoutQueryingStorage() {
        Result result = new Result();
        new TransferStoragePreflight(ApplicationProvider.getApplicationContext())
                .onMethodCall(new MethodCall("allocatableBytes", null), result);
        assertEquals("storage_wrong_thread", result.code);
        assertEquals(0, StorageShadow.calls);
    }

    @Test public void storageFailuresAreRedactedUnknownResults() throws Exception {
        for (String failure : new String[] {"path", "io", "security"}) {
            StorageShadow.failure = failure;
            Result result = background("allocatableBytes");
            assertEquals("storage_unavailable", result.code);
            assertNull(result.value);
            assertNull(result.details);
            assertFalse(result.message.contains("private"));
        }
    }

    @Test public void unsupportedCallsDoNotQueryStorage() throws Exception {
        Result result = background("snapshot");
        assertTrue(result.notImplemented);
        assertEquals(0, StorageShadow.calls);
    }

    private Result background(String method) throws Exception {
        var executor = Executors.newSingleThreadExecutor();
        try {
            return executor.submit(() -> {
                Result result = new Result();
                new TransferStoragePreflight(ApplicationProvider.getApplicationContext())
                        .onMethodCall(new MethodCall(method, null), result);
                return result;
            }).get(10, TimeUnit.SECONDS);
        } finally {
            executor.shutdownNow();
            assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS));
        }
    }

    private static final class Result implements MethodChannel.Result {
        Object value;
        String code;
        String message;
        Object details;
        boolean notImplemented;
        @Override public void success(Object value) { this.value = value; }
        @Override public void error(String code, String message, Object details) {
            this.code = code; this.message = message; this.details = details;
        }
        @Override public void notImplemented() { notImplemented = true; }
    }
}
