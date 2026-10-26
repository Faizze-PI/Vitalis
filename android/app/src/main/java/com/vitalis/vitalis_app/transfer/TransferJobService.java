package com.vitalis.vitalis_app.transfer;

import android.annotation.SuppressLint;
import android.app.job.JobParameters;
import android.app.job.JobService;
import android.os.Build;

import androidx.annotation.RequiresApi;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
// UIDT jobs use a dedicated JobScheduler namespace, so their IDs cannot
// collide with WorkManager's default namespace. Lint cannot infer that from
// the service declaration alone.
@SuppressLint("SpecifyJobSchedulerIdRange")
public final class TransferJobService extends JobService {
    private final Map<Integer, Thread> active = new ConcurrentHashMap<>();
    private volatile boolean destroyed;
    private final java.util.function.Function<android.content.Context, TransferEngine> engines;

    public TransferJobService() {
        this(TransferEngine::new);
    }

    TransferJobService(java.util.function.Function<android.content.Context, TransferEngine> engines) {
        this.engines = java.util.Objects.requireNonNull(engines);
    }

    @Override
    public boolean onStartJob(JobParameters parameters) {
        if (destroyed) return false;
        final long generation = parameters.getExtras()
                .getLong(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L); // hardcode: HC-053
        if (generation < 0L) return false;
        String transferId = parameters.getExtras().getString(TransferScheduler.INPUT_TRANSFER_ID);
        if (transferId == null) return false;
        final int notificationId = parameters.getExtras().getInt(TransferScheduler.INPUT_NOTIFICATION_ID);
        if (notificationId <= 0) {
            // A legacy queue entry stays resumable; explicit retry reschedules
            // with allocated identity. Never guess an ID on the callback thread.
            android.util.Log.w("VitalisTransfer", "notification_identity_required");
            return false;
        }
        OwnedJobThread thread = new OwnedJobThread(parameters, transferId, true, () -> {
            OwnedJobThread owner = (OwnedJobThread) Thread.currentThread();
            TransferExecutionResult outcome;
            try {
                TransferManifest initial = new TransferManifestStore(this).read(transferId);
                owner.snapshot = initial;
                if (initial == null) {
                    outcome = TransferExecutionResult.FAILURE;
                } else if (initial.controlGeneration != generation) {
                    outcome = TransferExecutionResult.SUCCESS;
                } else if (owner.stopping) {
                    return;
                } else {
                    outcome = engines.apply(this).run(
                            transferId, generation,
                            progress -> {
                                owner.snapshot = progress;
                                if (!owner.stopping) setNotification(
                                        parameters, notificationId,
                                        TransferNotifications.build(this, progress),
                                        JobService.JOB_END_NOTIFICATION_POLICY_REMOVE);
                            }
                    );
                }
            } catch (Exception failure) {
                if (!owner.stopping) persistStartupFailure(transferId, failure, generation);
                outcome = TransferExecutionResult.FAILURE;
            }
            owner.outcome = outcome;
        });
        synchronized (active) {
            if (destroyed || active.putIfAbsent(parameters.getJobId(), thread) != null) return false;
        }
        try {
            setNotification(parameters, notificationId,
                    TransferNotifications.starting(this, transferId, generation),
                    JobService.JOB_END_NOTIFICATION_POLICY_REMOVE);
        } catch (Exception failure) {
            android.util.Log.e("VitalisTransfer",
                    TransferFailureCode.FOREGROUND_PROMOTION_FAILED.wireName());
            thread.notificationFailed = true;
            thread.reportCompletion = false;
            thread.start();
            return false;
        }
        // Only the admitted owner can publish or start; storage remains off callback.
        thread.start();
        return !destroyed;
    }

    @Override
    public boolean onStopJob(JobParameters parameters) {
        synchronized (active) {
            OwnedJobThread owner = (OwnedJobThread) active.get(parameters.getJobId());
            if (owner == null) return false;
            if (!owner.transferId.equals(parameters.getExtras()
                    .getString(TransferScheduler.INPUT_TRANSFER_ID))
                    || owner.parameters.getExtras().getLong(
                            TransferNotifications.EXTRA_CONTROL_GENERATION, 0L)
                    != parameters.getExtras().getLong(
                            TransferNotifications.EXTRA_CONTROL_GENERATION, 0L)) return false;
            requestStop(owner, parameters.getStopReason());
            return owner.shouldRetry();
        }
    }

    @Override
    public void onDestroy() {
        try {
            synchronized (active) {
                destroyed = true;
                for (Thread thread : active.values()) {
                    requestStop((OwnedJobThread) thread, JobParameters.STOP_REASON_UNDEFINED);
                }
            }
        } finally {
            super.onDestroy();
        }
    }

    private void requestStop(OwnedJobThread owner, int reason) {
        if (owner.stopping) return;
        owner.stopReason = reason;
        owner.stopping = true;
        if (!TransferRunControl.requestStop(this, owner.transferId, owner)) owner.interrupt();
    }

    private boolean recordStop(String transferId, int stopReason, long generation) {
        return new TransferController(this).recordSchedulerStop(transferId, stopReason, generation);
    }

    private static boolean userStop(int reason) {
        return reason == JobParameters.STOP_REASON_CANCELLED_BY_APP
                || reason == JobParameters.STOP_REASON_USER;
    }

    private final class OwnedJobThread extends Thread {
        private final JobParameters parameters;
        private final String transferId;
        private volatile boolean reportCompletion;
        private boolean notificationFailed;
        private final Runnable work;
        private volatile boolean stopping;
        private volatile int stopReason;
        private volatile TransferManifest snapshot;
        private TransferExecutionResult outcome = TransferExecutionResult.FAILURE;

        OwnedJobThread(JobParameters parameters, String transferId,
                       boolean reportCompletion, Runnable work) {
            super("vitalis-transfer-" + parameters.getJobId());
            this.parameters = parameters;
            this.transferId = transferId;
            this.reportCompletion = reportCompletion;
            this.work = work;
        }

        boolean shouldRetry() {
            if (!reportCompletion || userStop(stopReason)) return false;
            TransferManifest known = snapshot;
            return known == null || TransferManifest.QUEUED.equals(known.state)
                    || TransferManifest.RUNNING.equals(known.state);
        }

        @Override
        public void run() {
            try {
                if (notificationFailed) {
                    persistStartupFailure(transferId, TransferFailureCode.FOREGROUND_PROMOTION_FAILED,
                            parameters.getExtras().getLong(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L));
                } else {
                    work.run();
                }
            } finally {
                finishOwned();
            }
        }

        private void finishOwned() {
            boolean interrupted = Thread.interrupted();
            boolean stopProjected = false;
            try {
                for (;;) {
                    synchronized (active) {
                        if (active.get(parameters.getJobId()) != this) return;
                        if (!stopping || stopProjected) {
                            active.remove(parameters.getJobId(), this);
                            if (!stopping && reportCompletion) {
                                jobFinished(parameters, outcome.shouldReschedule());
                            }
                            return;
                        }
                    }
                    // Never perform storage I/O while holding callback coordination.
                    interrupted |= Thread.interrupted();
                    if (!recordStop(transferId, stopReason, parameters.getExtras()
                            .getLong(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L))) {
                        android.util.Log.e("VitalisTransfer", "stop_recovery_required");
                        return; // Retain ownership until explicit recovery/restart.
                    }
                    stopProjected = true;
                }
            } finally {
                if (interrupted) interrupt();
            }
        }
    }

    private void persistStartupFailure(String transferId, Exception failure, long generation) {
        persistStartupFailure(transferId, failure instanceof SecurityException
                ? TransferFailureCode.SECURITY_REJECTED
                : TransferFailureCode.MANIFEST_READ_FAILED, generation);
    }

    private void persistStartupFailure(String transferId, TransferFailureCode code, long generation) {
        try {
            TransferManifestStore store = new TransferManifestStore(this);
            store.update(transferId, current -> {
                if (current.controlGeneration != generation) return current;
                if (current.shouldReschedule()
                        || (!TransferManifest.QUEUED.equals(current.state)
                        && !TransferManifest.RUNNING.equals(current.state))) return current;
                return current.withFailure(code, code.wireName());
            });
        } catch (Exception persistenceFailure) {
            android.util.Log.e("VitalisTransfer", "Unable to persist redacted job failure");
        }
    }
}
