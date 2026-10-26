package com.vitalis.vitalis_app.transfer;

import android.app.Notification;
import android.content.Context;
import android.content.pm.ServiceInfo;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.work.ForegroundInfo;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

public final class TransferWorker extends Worker {
    private final java.util.function.Function<Context, TransferEngine> engines;
    private Thread owner;
    private boolean stopSignalled;

    public TransferWorker(@NonNull Context context, @NonNull WorkerParameters parameters) {
        this(context, parameters, TransferEngine::new);
    }

    TransferWorker(Context context, WorkerParameters parameters,
                   java.util.function.Function<Context, TransferEngine> engines) {
        super(context, parameters);
        this.engines = java.util.Objects.requireNonNull(engines);
    }

    @Override
    public void onStopped() {
        super.onStopped();
        synchronized (this) {
            if (stopSignalled) return;
            stopSignalled = true;
            String transferId = getInputData().getString(TransferScheduler.INPUT_TRANSFER_ID);
            if (owner != null && transferId != null
                    && !TransferRunControl.requestStop(getApplicationContext(), transferId, owner)) {
                owner.interrupt();
            }
        }
    }

    @NonNull
    @Override
    public Result doWork() {
        String transferId = getInputData().getString(TransferScheduler.INPUT_TRANSFER_ID);
        if (transferId == null) return Result.failure();
        long generation = getInputData().getLong(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L);
        if (generation < 0L) return Result.failure();
        TransferManifestStore store = new TransferManifestStore(getApplicationContext());
        synchronized (this) {
            if (owner != null) return Result.retry();
            owner = Thread.currentThread();
        }
        try {
            if (isStopped()) return Result.retry();
            TransferManifest manifest = store.read(transferId);
            if (manifest == null) return Result.failure();
            if (manifest.controlGeneration != generation) return Result.success();
            if (isStopped()) return Result.retry();
            // WorkManager requires the foreground promotion to complete before
            // a long-running transfer begins doing network or file I/O.
            int notificationId = TransferNotifications.id(getApplicationContext(), transferId);
            setForegroundAsync(foreground(manifest, notificationId)).get();
            if (isStopped()) return Result.retry();
            TransferExecutionResult outcome = engines.apply(getApplicationContext()).run(
                    transferId, generation,
                    progress -> setForegroundAsync(foreground(progress, notificationId))
            );
            if (isStopped()) return Result.retry();
            if (outcome == TransferExecutionResult.RETRY) return Result.retry();
            if (outcome == TransferExecutionResult.FAILURE) return Result.failure();
            return Result.success();
        } catch (Exception failure) {
            if (isStopped()) return Result.retry();
            persistFailure(store, transferId, classify(failure), generation);
            return Result.failure();
        } finally {
            boolean interrupted;
            synchronized (this) {
                owner = null;
                interrupted = Thread.interrupted();
            }
            try {
                if (isStopped()) {
                    // Android exposes scheduler stop reasons only from API 31.
                    int reason = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                            ? getStopReason() : androidx.work.WorkInfo.STOP_REASON_UNKNOWN;
                    new TransferController(getApplicationContext())
                            .recordSchedulerStop(transferId, reason, generation);
                }
            } finally {
                if (interrupted) Thread.currentThread().interrupt();
            }
        }
    }

    private void persistFailure(
            TransferManifestStore store,
            String transferId,
            TransferFailureCode code,
            long generation
    ) {
        try {
            store.update(transferId, current -> {
                if (current.controlGeneration != generation) return current;
                if (current.shouldReschedule()
                        || (!TransferManifest.QUEUED.equals(current.state)
                        && !TransferManifest.RUNNING.equals(current.state))) return current;
                return current.withFailure(code, code.wireName());
            });
        } catch (Exception persistenceFailure) {
            android.util.Log.e("VitalisTransfer", "Unable to persist redacted transfer failure");
        }
    }

    private TransferFailureCode classify(Exception failure) {
        if (failure instanceof SecurityException) return TransferFailureCode.SECURITY_REJECTED;
        if (failure instanceof java.util.concurrent.ExecutionException) {
            return TransferFailureCode.FOREGROUND_PROMOTION_FAILED;
        }
        return TransferFailureCode.TRANSFER_EXCEPTION;
    }

    private ForegroundInfo foreground(TransferManifest manifest, int notificationId) {
        Notification notification = TransferNotifications.build(getApplicationContext(), manifest);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return new ForegroundInfo(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            );
        }
        return new ForegroundInfo(
                notificationId,
                notification
        );
    }
}
