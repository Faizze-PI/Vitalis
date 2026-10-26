package com.vitalis.vitalis_app.transfer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class TransferActionReceiver extends BroadcastReceiver {
    private final java.util.concurrent.Executor handoffs;

    public TransferActionReceiver() {
        this(java.util.concurrent.ForkJoinPool.commonPool());
    }

    TransferActionReceiver(java.util.concurrent.Executor handoffs) {
        this.handoffs = java.util.Objects.requireNonNull(handoffs);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String transferId = intent.getStringExtra(TransferNotifications.EXTRA_TRANSFER_ID);
        boolean cancel = TransferNotifications.ACTION_CANCEL.equals(intent.getAction());
        long generation = intent.getLongExtra(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L);
        if ((!cancel && !TransferNotifications.ACTION_PAUSE.equals(intent.getAction()))
                || transferId == null || !transferId.matches("[A-Za-z0-9_.-]{1,160}") || generation < 0L) return;
        PendingResult pending = goAsync();
        if (pending == null) {
            android.util.Log.e("VitalisTransfer", "notification_handoff_missing_result");
            return;
        }
        Context app = context.getApplicationContext();
        android.os.Handler handler = new android.os.Handler(android.os.Looper.getMainLooper());
        java.util.concurrent.atomic.AtomicBoolean finished = new java.util.concurrent.atomic.AtomicBoolean();
        Runnable timeout = () -> {
            if (finished.compareAndSet(false, true)) {
                android.util.Log.e("VitalisTransfer", "notification_handoff_unconfirmed");
                pending.finish();
            }
        };
        Runnable finish = () -> {
            if (finished.compareAndSet(false, true)) {
                handler.removeCallbacks(timeout);
                pending.finish();
            }
        };
        handler.postDelayed(timeout, TransferPolicy.NOTIFICATION_HANDOFF_MILLIS);
        try {
            handoffs.execute(() -> {
                try {
                    androidx.work.OneTimeWorkRequest request =
                            new androidx.work.OneTimeWorkRequest.Builder(TransferStopWorker.class)
                                    .setInputData(new androidx.work.Data.Builder()
                                            .putString(TransferScheduler.INPUT_TRANSFER_ID, transferId)
                                            .putLong(TransferStopWorker.INPUT_GENERATION, generation)
                                            .putBoolean(TransferStopWorker.INPUT_CANCEL, cancel).build())
                                    .build();
                    // Cancel must not queue behind a Pause waiting for cleanup.
                    androidx.work.Operation operation = androidx.work.WorkManager.getInstance(app)
                            .enqueueUniqueWork(TransferStopWorker.WORK_PREFIX + transferId
                                            + "_" + generation + (cancel ? "_cancel" : "_pause"),
                                    androidx.work.ExistingWorkPolicy.KEEP, request);
                    operation.getResult().addListener(() -> {
                        try { operation.getResult().get(); }
                        catch (Exception failure) {
                            android.util.Log.e("VitalisTransfer", "notification_handoff_failed");
                        } finally { finish.run(); }
                    }, Runnable::run);
                } catch (Exception failure) {
                    android.util.Log.e("VitalisTransfer", "notification_handoff_failed");
                    finish.run();
                }
            });
        } catch (Exception failure) {
            android.util.Log.e("VitalisTransfer", "notification_handoff_rejected");
            finish.run();
        }
    }
}
