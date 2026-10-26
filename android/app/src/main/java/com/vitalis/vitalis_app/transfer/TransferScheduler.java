package com.vitalis.vitalis_app.transfer;

import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.os.PersistableBundle;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

import androidx.annotation.RequiresApi;
import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;

public final class TransferScheduler {
    public static final String INPUT_TRANSFER_ID = "transfer_id"; // hardcode: HC-063
    public static final String INPUT_NOTIFICATION_ID = "notification_id"; // hardcode: HC-063
    private static final String WORK_PREFIX = "vitalis-model-transfer-"; // hardcode: HC-063

    private TransferScheduler() {}

    public static synchronized boolean schedule(Context context, TransferManifest manifest) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            JobInfo info = buildUidtJob(context, manifest);
            JobScheduler scheduler = context.getSystemService(JobScheduler.class)
                    .forNamespace("vitalis_model_transfers");
            return scheduler.schedule(info) == JobScheduler.RESULT_SUCCESS;
        }

        Data input = new Data.Builder()
                .putString(INPUT_TRANSFER_ID, manifest.transferId)
                .putLong(TransferNotifications.EXTRA_CONTROL_GENERATION, manifest.controlGeneration)
                .build();
        Constraints constraints = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(TransferWorker.class)
                .setInputData(input)
                .setConstraints(constraints)
                .addTag(manifest.transferId)
                .build();
        WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_PREFIX + manifest.transferId + "_" + manifest.controlGeneration,
                ExistingWorkPolicy.REPLACE,
                request
        );
        return true;
    }

    public static synchronized void cancel(Context context, String transferId) {
        cancel(context, transferId, -1L);
    }

    public static synchronized void cancel(Context context, String transferId, long generation) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            JobScheduler scheduler = context.getSystemService(JobScheduler.class)
                    .forNamespace("vitalis_model_transfers");
            for (JobInfo job : pendingJobs(scheduler)) {
                if (owns(context, job, transferId) && (generation < 0L
                        || job.getExtras().getLong(TransferNotifications.EXTRA_CONTROL_GENERATION, 0L)
                        == generation)) scheduler.cancel(job.getId());
            }
        } else {
            WorkManager manager = WorkManager.getInstance(context);
            if (generation < 0L) manager.cancelAllWorkByTag(transferId);
            else {
                manager.cancelUniqueWork(WORK_PREFIX + transferId + "_" + generation);
                if (generation == 0L) manager.cancelUniqueWork(WORK_PREFIX + transferId);
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    static synchronized JobInfo buildUidtJob(Context context, TransferManifest manifest) {
        NetworkRequest network = new NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build();
        PersistableBundle extras = new PersistableBundle();
        extras.putString(INPUT_TRANSFER_ID, manifest.transferId);
        extras.putLong(TransferNotifications.EXTRA_CONTROL_GENERATION, manifest.controlGeneration);
        extras.putInt(INPUT_NOTIFICATION_ID, TransferNotifications.id(context, manifest.transferId));
        return new JobInfo.Builder(
                availableJobId(context, manifest.transferId),
                new ComponentName(context, TransferJobService.class)
        )
                .setUserInitiated(true)
                .setRequiredNetwork(network)
                .setEstimatedNetworkBytes(
                        Math.max(0L, manifest.expectedBytes - manifest.downloadedBytes),
                        0L
                )
                .setExtras(extras)
                .build();
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private static int availableJobId(Context context, String transferId) {
        JobScheduler scheduler = context.getSystemService(JobScheduler.class)
                .forNamespace("vitalis_model_transfers");
        Set<Integer> occupied = new HashSet<>();
        for (JobInfo job : pendingJobs(scheduler)) {
            if (owns(context, job, transferId)) return job.getId();
            occupied.add(job.getId());
        }
        int candidate = 20_000 + (transferId.hashCode() & 0x3fffffff) % 1_000_000;
        while (occupied.contains(candidate)) {
            candidate = candidate == Integer.MAX_VALUE ? 0 : candidate + 1;
        }
        return candidate;
    }

    private static List<JobInfo> pendingJobs(JobScheduler scheduler) {
        List<JobInfo> jobs = scheduler.getAllPendingJobs();
        if (jobs == null) throw new IllegalStateException("Scheduler inventory unavailable");
        return jobs;
    }

    private static boolean owns(Context context, JobInfo job, String transferId) {
        return new ComponentName(context, TransferJobService.class).equals(job.getService())
                && transferId.equals(job.getExtras().getString(INPUT_TRANSFER_ID));
    }
}
