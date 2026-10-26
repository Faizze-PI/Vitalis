package com.vitalis.vitalis_app.transfer;

import android.content.Context;

import java.net.HttpURLConnection;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.FutureTask;
import java.util.concurrent.atomic.AtomicBoolean;

/** Process-local control mailbox; the writer lease remains the file authority. */
final class TransferRunControl {
    private static final ConcurrentHashMap<String, TransferRunControl> RUNS = new ConcurrentHashMap<>();
    private final String key;
    private Thread worker = Thread.currentThread();
    private volatile boolean stopped;
    private long generation = -1L;
    private ConnectionClose connection;
    private FutureTask<Boolean> recovery;

    private TransferRunControl(String key) { this.key = key; }

    static TransferRunControl begin(Context context, String transferId) {
        String key = key(context, transferId);
        TransferRunControl control = new TransferRunControl(key);
        return RUNS.putIfAbsent(key, control) == null ? control : null;
    }

    static boolean requestStop(Context context, String transferId) {
        TransferRunControl control = RUNS.get(key(context, transferId));
        if (control == null) return false;
        control.requestStop();
        return true;
    }

    static boolean requestStop(Context context, String transferId, Thread owner) {
        TransferRunControl control = RUNS.get(key(context, transferId));
        if (control == null) return false;
        synchronized (control) {
            if (control.worker != owner) return false;
            control.requestStop();
            return true;
        }
    }

    static boolean requestStop(Context context, String transferId, long generation) {
        TransferRunControl control = RUNS.get(key(context, transferId));
        if (control == null) return false;
        synchronized (control) {
            if (control.generation != generation) return false;
            control.requestStop();
            return true;
        }
    }

    synchronized void bindGeneration(long value) {
        if (value < 0L || generation >= 0L) throw new IllegalStateException("Invalid control generation binding");
        generation = value;
    }

    synchronized boolean ownsGeneration(long value) { return generation == value; }

    static boolean hasPendingConnection(Context context, String transferId) {
        TransferRunControl control = RUNS.get(key(context, transferId));
        if (control == null) return false;
        synchronized (control) { return control.connection != null; }
    }

    static boolean requiresRecovery(Context context, String transferId) {
        TransferRunControl control = RUNS.get(key(context, transferId));
        if (control == null) return false;
        synchronized (control) { return control.worker == null && control.connection != null; }
    }

    static boolean recover(Context context, String transferId) throws Exception {
        TransferRunControl control = RUNS.get(key(context, transferId));
        return control == null || control.recover();
    }

    private boolean recover() throws Exception {
        FutureTask<Boolean> attempt;
        synchronized (this) {
            if (worker != null) return false;
            if (recovery == null) {
                recovery = new FutureTask<>(() -> {
                    ConnectionClose retry;
                    synchronized (this) {
                        if (connection != null) connection = new ConnectionClose(connection.value);
                        retry = connection;
                    }
                    if (retry != null) closeConnection(retry.value);
                    RUNS.remove(key, this);
                    return true;
                });
            }
            attempt = recovery;
        }
        try {
            attempt.run();
            return attempt.get();
        } finally {
            synchronized (this) {
                if (attempt.isDone() && recovery == attempt) recovery = null;
            }
        }
    }

    private static String key(Context context, String transferId) {
        return context.getFilesDir().getAbsolutePath() + '\0' + transferId;
    }

    private synchronized void requestStop() {
        if (stopped) return;
        stopped = true;
        // Self-control callbacks must still be able to persist their stop intent.
        if (worker != null && worker != Thread.currentThread()) worker.interrupt();
        if (connection != null) connection.requestClose();
    }

    boolean isStopped() { return stopped; }

    void checkStopped() throws StopRequested {
        if (stopped) throw new StopRequested();
    }

    synchronized void checkConnectionAvailable() {
        if (connection != null) throw new IllegalStateException("Connection cleanup pending");
    }

    synchronized void attach(HttpURLConnection value) {
        if (connection != null) throw new IllegalStateException("Connection cleanup pending");
        connection = new ConnectionClose(value);
        if (stopped) connection.requestClose();
    }

    void closeConnection(HttpURLConnection value) throws Exception {
        ConnectionClose owned;
        synchronized (this) {
            owned = connection;
            if (owned == null || owned.value != value) {
                throw new IllegalStateException("Connection ownership mismatch");
            }
        }
        owned.closeAndWait();
        synchronized (this) {
            if (connection == owned) connection = null;
        }
    }

    void finish() {
        ConnectionClose remaining;
        synchronized (this) { remaining = connection; }
        try {
            if (remaining != null) closeConnection(remaining.value);
            RUNS.remove(key, this);
        } catch (Exception failure) {
            // Keep the mailbox reserved: unconfirmed close is not termination.
            android.util.Log.e("VitalisTransfer", "connection_cleanup_unconfirmed");
        } finally {
            // A quarantined connection does not own this thread's future work.
            synchronized (this) { worker = null; }
        }
    }

    static final class StopRequested extends Exception {}

    private static final class ConnectionClose {
        final HttpURLConnection value;
        final AtomicBoolean started = new AtomicBoolean();
        final FutureTask<Void> completion;

        ConnectionClose(HttpURLConnection value) {
            this.value = value;
            completion = new FutureTask<>(() -> {
                value.disconnect();
                return null;
            });
        }

        void requestClose() {
            if (started.compareAndSet(false, true)) {
                new Thread(completion, "vitalis-transfer-close").start();
            }
        }

        void closeAndWait() throws Exception {
            if (started.compareAndSet(false, true)) completion.run();
            boolean interrupted = false;
            try {
                for (;;) {
                    try {
                        completion.get();
                        return;
                    } catch (InterruptedException stopped) {
                        interrupted = true;
                    }
                }
            } finally {
                if (interrupted) Thread.currentThread().interrupt();
            }
        }
    }
}
