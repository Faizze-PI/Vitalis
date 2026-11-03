package com.vitalis.vitalis_app.tasks;

import static org.junit.Assert.*;
import android.content.Context;
import android.graphics.Bitmap;
import androidx.test.core.app.ApplicationProvider;
import java.io.File;
import java.io.FileOutputStream;
import java.util.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public final class OnnxImageInputTest {
    @Test public void preparesDeclaredRgbNchwPixels() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File root = new File(context.getFilesDir(), "input_workspace"); root.mkdirs();
        File image = new File(root, UUID.randomUUID().toString().replace("-", "") + ".blob");
        Bitmap bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888);
        bitmap.setPixels(new int[]{0xffff0000,0xff00ff00,0xff0000ff,0xffffffff},0,2,0,0,2,2);
        try {
            try(FileOutputStream out = new FileOutputStream(image)) { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,out)); }
            Map<String,Object> options = new HashMap<>();
            options.put("layout","NCHW"); options.put("resize","stretch");
            options.put("interpolation","nearest"); options.put("color_order","RGB");
            options.put("orientation","stored"); options.put("scale",1.0/255);
            options.put("mean",Arrays.asList(0.0,0.0,0.0)); options.put("std",Arrays.asList(1.0,1.0,1.0));
            float[] actual = OnnxImageInput.prepare(context,image,new long[]{1,3,2,2},options,
                    new OnnxTaskEngine.Control(), 1024 * 1024);
            assertArrayEquals(new float[]{1,0,0,1, 0,1,0,1, 0,0,1,1},actual,0.00001f);
        } finally {bitmap.recycle(); assertTrue(image.delete());}
    }
}
