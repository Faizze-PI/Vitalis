package com.vitalis.vitalis_app.transfer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import java.util.Map;

/** Durable notification command; never owns the transfer's file writer. */
public final class TransferStopWorker extends Worker {
    static final String INPUT_CANCEL = "cancel"; // hardcode: HC-063
    static final String INPUT_GENERATION = TransferNotifications.EXTRA_CONTROL_GENERATION;
    static final String WORK_PREFIX = "vitalis_transfer_stop_"; // hardcode: HC-063

    public TransferStopWorker(@NonNull Context context, @NonNull WorkerParameters parameters) {
        super(context, parameters);
    }

    @NonNull
    @Override
    public Result doWork() {
        String identity = getInputData().getString(TransferScheduler.INPUT_TRANSFER_ID);
        long generation = getInputData().getLong(INPUT_GENERATION, -1L);
        if (identity == null || !identity.matches("[A-Za-z0-9_.-]{1,160}") || generation < 0L) return Result.failure();
        try {
            TransferController controller = new TransferController(getApplicationContext());
            if (controller.status(identity) == null) return Result.failure();
            if (!controller.stopForGeneration(identity,
                    getInputData().getBoolean(INPUT_CANCEL, false), generation)) {
                return Result.success(); // Obsolete command; never Stop the replacement run.
            }
            Map<String, Object> state = controller.status(identity);
            if (state == null) return Result.failure();
            return Boolean.TRUE.equals(state.get("stopAcknowledged")) ? Result.success() : Result.retry();
        } catch (SecurityException rejected) {
            android.util.Log.e("VitalisTransfer", "notification_stop_security_rejected");
            return Result.failure();
        } catch (Exception failure) {
            android.util.Log.e("VitalisTransfer", "notification_stop_retry_required");
            return Result.retry();
        }
    }
}
