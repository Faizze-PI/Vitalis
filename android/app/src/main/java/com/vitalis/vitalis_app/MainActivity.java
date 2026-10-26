package com.vitalis.vitalis_app;

import android.app.ActivityManager;
import android.content.Context;
import android.os.Build;
import android.os.Debug;
import android.os.PowerManager;
import android.Manifest;
import android.content.pm.PackageManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.HashMap;
import java.util.Map;

import com.vitalis.vitalis_app.transfer.TransferController;
import com.vitalis.vitalis_app.transfer.TransferStoragePreflight;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;

public class MainActivity extends FlutterActivity {
    private static final String METHOD_CHANNEL = "vitalis/device_safety"; // hardcode: HC-064
    private static final String EVENT_CHANNEL = "vitalis/device_events"; // hardcode: HC-064
    private static final int NOTIFICATION_PERMISSION_REQUEST = 7412; // hardcode: HC-064
    private EventChannel.EventSink eventSink;
    private MethodChannel.Result notificationPermissionResult;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        var messenger = flutterEngine.getDartExecutor().getBinaryMessenger();
        new MethodChannel(messenger, "vitalis/model_storage", StandardMethodCodec.INSTANCE,
                messenger.makeBackgroundTaskQueue())
                .setMethodCallHandler(new TransferStoragePreflight(this));
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                METHOD_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if (call.method.equals("snapshot")) {
                result.success(deviceSnapshot());
            } else if (call.method.equals("notificationPermission")) {
                requestNotificationPermission(result);
            } else {
                result.notImplemented();
            }
        });
        new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                EVENT_CHANNEL
        ).setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                eventSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                eventSink = null;
            }
        });
        new TransferController(this).register(
                flutterEngine.getDartExecutor().getBinaryMessenger());
    }

    private void requestNotificationPermission(MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(permissionStatus("not_required"));
            return;
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            result.success(permissionStatus("granted"));
            return;
        }
        if (notificationPermissionResult != null) {
            result.success(permissionStatus("request_in_progress"));
            return;
        }
        notificationPermissionResult = result;
        requestPermissions(
                new String[]{Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST
        );
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            String[] permissions,
            int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST || notificationPermissionResult == null) {
            return;
        }
        MethodChannel.Result pending = notificationPermissionResult;
        notificationPermissionResult = null;
        boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        pending.success(permissionStatus(granted ? "granted" : "denied"));
    }

    private Map<String, Object> permissionStatus(String status) {
        Map<String, Object> value = new HashMap<>();
        value.put("status", status);
        return value;
    }

    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        if (eventSink != null) {
            Map<String, Object> event = new HashMap<>();
            event.put("trimMemoryLevel", level);
            eventSink.success(event);
        }
    }

    private Map<String, Object> deviceSnapshot() {
        ActivityManager manager =
                (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(memory);
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);

        Map<String, Object> value = new HashMap<>();
        value.put("availableMemoryBytes", memory.availMem);
        value.put("totalMemoryBytes", memory.totalMem);
        value.put("memoryThresholdBytes", memory.threshold);
        value.put("lowMemory", memory.lowMemory);
        value.put("processRssBytes", (long) Debug.getPss() * 1024L);
        value.put("powerSaveMode", power.isPowerSaveMode());
        value.put("logicalProcessors", Runtime.getRuntime().availableProcessors());
        value.put("performanceProcessors", performanceProcessorCount());
        value.put("deviceFingerprint", Build.FINGERPRINT);
        value.put("supportedAbis", Arrays.asList(Build.SUPPORTED_ABIS));
        value.put("packagedBackends", packagedBackends());
        value.put(
                "thermalStatus",
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                        ? power.getCurrentThermalStatus()
                        : null
        );
        return value;
    }

    private List<String> packagedBackends() {
        List<String> backends = new ArrayList<>();
        backends.add("cpu");
        File nativeDirectory = new File(getApplicationInfo().nativeLibraryDir);
        if (new File(nativeDirectory, "libggml-vulkan.so").isFile()) {
            backends.add("vulkan");
        }
        return backends;
    }

    private Integer performanceProcessorCount() {
        int logical = Runtime.getRuntime().availableProcessors();
        long[] frequencies = new long[logical];
        long maximum = 0L;
        for (int index = 0; index < logical; index++) {
            frequencies[index] = readLong(
                    "/sys/devices/system/cpu/cpu" + index +
                            "/cpufreq/cpuinfo_max_freq"
            );
            maximum = Math.max(maximum, frequencies[index]);
        }
        if (maximum <= 0L) return null;
        int performance = 0;
        for (long frequency : frequencies) {
            if (frequency >= (long) (maximum * 0.70)) performance++;
        }
        return Math.max(1, performance);
    }

    private long readLong(String path) {
        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            return Long.parseLong(reader.readLine().trim());
        } catch (Exception ignored) {
            return 0L;
        }
    }
}
