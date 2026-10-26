package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.ComponentName;
import android.content.Intent;
import android.database.sqlite.SQLiteException;
import android.graphics.drawable.AdaptiveIconDrawable;
import android.graphics.drawable.Icon;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import androidx.test.core.app.ApplicationProvider;
import com.vitalis.vitalis_app.MainActivity;

import org.junit.Test;
import org.junit.Before;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;

import java.io.File;
import java.nio.file.Files;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class TransferNotificationsTest {
    @Test
    public void notificationTapOpensAppWithoutTransferControlSideEffects() {
        Context context = ApplicationProvider.getApplicationContext();
        Notification[] notifications = {
                TransferNotifications.build(context, manifest(context, "open-app")),
                TransferNotifications.starting(context, "open-app")
        };
        for (Notification notification : notifications) {
            assertNotNull(notification.contentIntent);
            assertTrue(notification.contentIntent.isImmutable());
            Intent target = Shadows.shadowOf(notification.contentIntent).getSavedIntent();
            assertEquals(new ComponentName(context, MainActivity.class), target.getComponent());
            assertEquals(Intent.ACTION_MAIN, target.getAction());
            assertTrue(target.hasCategory(Intent.CATEGORY_LAUNCHER));
            assertFalse(target.hasExtra(TransferNotifications.EXTRA_TRANSFER_ID));
            assertEquals(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    target.getFlags());
        }
    }

    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    public void notificationGlyphsHaveTransparentBackgrounds() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        Notification notification = TransferNotifications.build(context, manifest(context, "glyph"));
        assertTransparentGlyph(context, notification.getSmallIcon());
        for (Notification.Action action : notification.actions) {
            assertTransparentGlyph(context, action.getIcon());
        }
    }

    private static void assertTransparentGlyph(Context context, Icon icon) throws Exception {
        assertFalse(context.getDrawable(icon.getResId()) instanceof AdaptiveIconDrawable);
        try (java.io.InputStream raw = context.getResources().openRawResource(icon.getResId())) {
            Bitmap glyph = BitmapFactory.decodeStream(raw);
            assertNotNull("Notification must resolve to a standalone glyph", glyph);
            assertTrue("Glyph needs an alpha channel", glyph.hasAlpha());
            assertEquals("Opaque background becomes a solid notification silhouette", 0,
                    glyph.getPixel(0, 0) >>> 24);
            boolean visible = false;
            for (int y = 0; y < glyph.getHeight(); y++) {
                for (int x = 0; x < glyph.getWidth(); x++) {
                    visible |= (glyph.getPixel(x, y) >>> 24) != 0;
                }
            }
            assertTrue("Glyph must not be empty", visible);
        }
    }

    @Before
    public void clearDisposableHostIdentityFixture() {
        ApplicationProvider.<Context>getApplicationContext()
                .deleteDatabase("transfer_notification_ids.db");
    }

    @Test
    public void identitiesRemainStableAfterStoreReopeningInReverseOrder() {
        Context context = ApplicationProvider.getApplicationContext();
        int first = TransferNotifications.id(context, "Aa");
        int second = TransferNotifications.id(context, "BB");
        assertNotEquals(first, second);
        // Each lookup opens and closes its store; no static map supplies identity.
        assertEquals(second, TransferNotifications.id(context, "BB"));
        assertEquals(first, TransferNotifications.id(context, "Aa"));
    }

    @Test
    public void concurrentAllocatorsRetainDistinctAndStableIdentities() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferNotifications.id(context, "initialized");
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<Integer> first = executor.submit(() -> TransferNotifications.id(context, "Aa"));
            Future<Integer> second = executor.submit(() -> TransferNotifications.id(context, "BB"));
            int firstId = first.get(10, TimeUnit.SECONDS);
            int secondId = second.get(10, TimeUnit.SECONDS);
            assertNotEquals(firstId, secondId);
            assertEquals(firstId, TransferNotifications.id(context, "Aa"));
            assertEquals(secondId, TransferNotifications.id(context, "BB"));
        } finally {
            executor.shutdownNow();
            executor.awaitTermination(10, TimeUnit.SECONDS);
        }
    }

    @Test
    public void visibleLegacyNotificationCannotBeReusedForNewTransfer() {
        Context context = ApplicationProvider.getApplicationContext();
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.cancelAll();
        try {
            manager.notify(10_001, TransferNotifications.build(context, manifest(context, "legacy")));
            int allocated = TransferNotifications.id(context, "new-transfer");
            assertNotEquals(10_001, allocated);
            manager.notify(allocated, TransferNotifications.build(context, manifest(context, "new-transfer")));
            assertEquals(2, manager.getActiveNotifications().length);
        } finally {
            manager.cancelAll();
        }
    }

    @Test
    public void corruptIdentityStoreFailsWithoutDeletingItsEvidence() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        File database = context.getDatabasePath("transfer_notification_ids.db");
        Files.createDirectories(database.getParentFile().toPath());
        byte[] corrupt = "not a sqlite database".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        Files.write(database.toPath(), corrupt);

        assertThrows(SQLiteException.class, () -> TransferNotifications.id(context, "new-transfer"));
        assertArrayEquals(corrupt, Files.readAllBytes(database.toPath()));
    }

    @Test
    public void collidingTransfersKeepTheirOwnNotificationControls() {
        Context context = ApplicationProvider.getApplicationContext();
        Notification first = TransferNotifications.build(context, manifest(context, "Aa"));
        Notification second = TransferNotifications.build(context, manifest(context, "BB"));

        for (int action = 0; action < 2; action++) {
            assertEquals("Aa", Shadows.shadowOf(first.actions[action].actionIntent)
                    .getSavedIntent().getStringExtra(TransferNotifications.EXTRA_TRANSFER_ID));
            assertEquals("BB", Shadows.shadowOf(second.actions[action].actionIntent)
                    .getSavedIntent().getStringExtra(TransferNotifications.EXTRA_TRANSFER_ID));
        }
    }

    @Test
    public void collidingTransfersCannotReplaceEachOthersVisibleNotification() {
        Context context = ApplicationProvider.getApplicationContext();
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        manager.cancelAll();
        try {
            manager.notify(TransferNotifications.id(context, "Aa"),
                    TransferNotifications.build(context, manifest(context, "Aa")));
            manager.notify(TransferNotifications.id(context, "BB"),
                    TransferNotifications.build(context, manifest(context, "BB")));
            assertEquals(2, manager.getActiveNotifications().length);
            manager.cancel(TransferNotifications.id(context, "Aa"));
            assertEquals(1, manager.getActiveNotifications().length);
            assertEquals(TransferNotifications.id(context, "BB"), manager.getActiveNotifications()[0].getId());
        } finally {
            manager.cancelAll();
        }
    }

    private TransferManifest manifest(Context context, String identity) {
        return new TransferManifest(identity, "job-" + identity, "model-" + identity,
                "publisher/model", "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                new File(context.getFilesDir(), "models/" + identity + ".gguf.part").getPath(),
                1024L, null, 0L, 0, TransferManifest.QUEUED, null, null, 1L, 1L);
    }
}
