package com.vitalis.vitalis_app;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.AdaptiveIconDrawable;
import android.graphics.drawable.Drawable;
import androidx.test.core.app.ApplicationProvider;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;

/** Characterizes the app's anydpi launcher selection at its API-28 support floor. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public final class LauncherIconTest {
    @Test
    public void manifestLauncherRendersAdaptiveLayersAtEveryShippedDensity() {
        Context app = ApplicationProvider.getApplicationContext();
        assertEquals(R.mipmap.ic_launcher, app.getApplicationInfo().icon);
        for (int density : new int[] {160, 240, 320, 480, 640}) {
            Configuration configuration = new Configuration(app.getResources().getConfiguration());
            configuration.densityDpi = density;
            Context context = app.createConfigurationContext(configuration);
            Drawable drawable = context.getDrawable(app.getApplicationInfo().icon);
            assertTrue("Launcher must remain adaptive at density " + density,
                    drawable instanceof AdaptiveIconDrawable);
            AdaptiveIconDrawable icon = (AdaptiveIconDrawable) drawable;
            assertNotNull(icon.getForeground());
            assertNotNull(icon.getBackground());
            Bitmap bitmap = Bitmap.createBitmap(108, 108, Bitmap.Config.ARGB_8888);
            try {
                icon.setBounds(0, 0, 108, 108);
                icon.draw(new Canvas(bitmap));
                assertNotEquals("Launcher center must not be transparent", 0,
                        bitmap.getPixel(54, 54) >>> 24);
            } finally {
                bitmap.recycle();
            }
        }
    }
}
