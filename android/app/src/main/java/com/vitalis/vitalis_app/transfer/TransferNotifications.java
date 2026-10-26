package com.vitalis.vitalis_app.transfer;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.Icon;
import android.net.Uri;

import com.vitalis.vitalis_app.R;
import com.vitalis.vitalis_app.MainActivity;

public final class TransferNotifications {
    public static final String CHANNEL_ID = "vitalis_model_transfers"; // hardcode: HC-063
    public static final String ACTION_PAUSE = "com.vitalis.transfer.PAUSE"; // hardcode: HC-063
    public static final String ACTION_CANCEL = "com.vitalis.transfer.CANCEL"; // hardcode: HC-063
    public static final String EXTRA_TRANSFER_ID = "transfer_id"; // hardcode: HC-063
    public static final String EXTRA_CONTROL_GENERATION = "control_generation"; // hardcode: HC-063

    private TransferNotifications() {}

    public static Notification build(Context context, TransferManifest manifest) {
        int percent = manifest.expectedBytes <= 0L
                ? 0
                : (int) Math.min(100L, manifest.downloadedBytes * 100L / manifest.expectedBytes);
        return build(context, manifest.transferId, manifest.controlGeneration, percent, manifest.expectedBytes <= 0L,
                percent + "% complete");
    }

    public static Notification starting(Context context, String transferId) {
        return starting(context, transferId, 0L);
    }

    public static Notification starting(Context context, String transferId, long generation) {
        return build(context, transferId, generation, 0, true, "Preparing download");
    }

    private static Notification build(Context context, String transferId, long generation, int percent,
                                      boolean indeterminate, String status) {
        ensureChannel(context);
        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID);
        return builder
                .setSmallIcon(R.mipmap.ic_launcher_foreground)
                .setContentTitle("Downloading local AI model")
                .setContentText(status)
                .setContentIntent(openApp(context))
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setProgress(100, percent, indeterminate)
                .addAction(new Notification.Action.Builder(
                        Icon.createWithResource(context, R.mipmap.ic_launcher_foreground),
                        "Pause",
                        action(context, ACTION_PAUSE, transferId, generation, 1)
                ).build())
                .addAction(new Notification.Action.Builder(
                        Icon.createWithResource(context, R.mipmap.ic_launcher_foreground),
                        "Cancel",
                        action(context, ACTION_CANCEL, transferId, generation, 2)
                ).build())
                .build();
    }

    private static PendingIntent openApp(Context context) {
        Intent intent = new Intent(context, MainActivity.class)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    public static int id(Context context, String transferId) {
        return TransferNotificationIds.forTransfer(context, transferId);
    }

    private static PendingIntent action(
            Context context,
            String action,
            String transferId,
            long generation,
            int requestSuffix
    ) {
        Intent intent = new Intent(context, TransferActionReceiver.class)
                .setAction(action)
                // Extras are not part of PendingIntent identity (HC-034).
                .setData(new Uri.Builder().scheme("vitalis-transfer").authority("control")
                        .appendPath(transferId).appendPath(action).appendPath(Long.toString(generation)).build())
                .putExtra(EXTRA_TRANSFER_ID, transferId)
                .putExtra(EXTRA_CONTROL_GENERATION, generation);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getBroadcast(
                context,
                requestSuffix,
                intent,
                flags
        );
    }

    private static void ensureChannel(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Model downloads",
                NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Visible progress for user-requested local model downloads");
        manager.createNotificationChannel(channel);
    }
}
