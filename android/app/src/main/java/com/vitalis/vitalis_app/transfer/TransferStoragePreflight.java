package com.vitalis.vitalis_app.transfer;

import android.content.Context;
import android.os.Looper;
import android.os.storage.StorageManager;
import androidx.annotation.WorkerThread;
import java.io.IOException;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class TransferStoragePreflight implements MethodChannel.MethodCallHandler {
    private final Context context;

    public TransferStoragePreflight(Context context) {
        this.context = context.getApplicationContext();
    }

    // Registered only on the dedicated Flutter background task queue.
    @WorkerThread
    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (!"allocatableBytes".equals(call.method)) {
            result.notImplemented();
            return;
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            result.error("storage_wrong_thread", "Storage preflight requires a background queue", null);
            return;
        }
        try {
            StorageManager storage = context.getSystemService(StorageManager.class);
            if (storage == null) throw new IOException("Storage service unavailable");
            long bytes = storage.getAllocatableBytes(storage.getUuidForPath(context.getFilesDir()));
            if (bytes < 0) throw new IOException("Invalid allocation budget");
            result.success(bytes);
        } catch (IOException | SecurityException unavailable) {
            result.error("storage_unavailable", "Storage budget is unavailable", null);
        }
    }
}
