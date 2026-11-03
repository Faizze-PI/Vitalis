package com.vitalis.vitalis_app.tasks;

import static org.junit.Assert.*;
import android.content.Context;
import android.app.ActivityManager;
import androidx.test.core.app.ApplicationProvider;
import java.io.File;
import java.nio.file.Files;
import java.util.Collections;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public final class OnnxTaskEngineTest {
    @Test public void cancellationRejectsBeforeAnyModelOrNativeAccess() throws Exception {
        OnnxTaskEngine.Control control = new OnnxTaskEngine.Control();
        control.cancel(); control.cancel();
        try {
            OnnxTaskEngine.run(null, null, null, null, null, null, null, control);
            fail("Cancelled work admitted");
        } catch (CancellationException expected) { assertTrue(control.isCancelled()); }
    }

    @Test public void rejectsUnownedModelBeforeNativeLoading() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        try {
            OnnxTaskEngine.run(context, new File(context.getCacheDir(), "model.blob"),
                    "a".repeat(64), "features", new float[]{1}, new long[]{1},
                    Collections.singletonList("prediction"), new OnnxTaskEngine.Control());
            fail("Unowned path accepted");
        } catch (IllegalArgumentException expected) {
            assertEquals("modelNotOwned", expected.getMessage());
        }
    }

    @Test public void rejectsChangedModelBytesWithoutLoadingOrt() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo();
        memory.availMem = Runtime.getRuntime().maxMemory();
        memory.lowMemory = false;
        org.robolectric.Shadows.shadowOf((ActivityManager)
                context.getSystemService(Context.ACTIVITY_SERVICE)).setMemoryInfo(memory);
        File root = new File(context.getFilesDir(), "input_workspace");
        assertTrue(root.isDirectory() || root.mkdirs());
        File model = new File(root, UUID.randomUUID().toString().replace("-", "") + ".blob");
        assertTrue(model.createNewFile());
        try {
            Files.write(model.toPath(), new byte[]{1,2,3});
            try {
                OnnxTaskEngine.run(context, model, "a".repeat(64), "features",
                        new float[]{1}, new long[]{1}, Collections.singletonList("prediction"),
                        new OnnxTaskEngine.Control());
                fail("Hash mismatch accepted");
            } catch (IllegalArgumentException expected) {
                assertEquals("hashMismatch", expected.getMessage());
            }
        } finally { assertTrue(model.delete()); }
    }
}
