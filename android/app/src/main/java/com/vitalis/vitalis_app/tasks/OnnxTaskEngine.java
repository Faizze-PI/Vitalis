package com.vitalis.vitalis_app.tasks;

import ai.onnxruntime.*;
import android.app.ActivityManager;
import android.content.Context;
import java.io.File;
import java.io.ByteArrayOutputStream;
import java.io.FileInputStream;
import java.nio.FloatBuffer;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.CancellationException;

/** CPU-only, single-file float32 task execution. No custom native operators. */
public final class OnnxTaskEngine {
    private OnnxTaskEngine() {}

    public static final class Control {
        private boolean cancelled;
        private OrtSession.RunOptions active;
        public synchronized void cancel() throws OrtException {
            cancelled = true;
            if (active != null) active.setTerminate(true);
        }
        public synchronized boolean isCancelled() { return cancelled; }
        private synchronized void attach(OrtSession.RunOptions options) throws OrtException {
            active = options;
            if (cancelled) options.setTerminate(true);
        }
        private synchronized void detach() { active = null; }
        void check() { if (isCancelled()) throw new CancellationException(); }
    }

    public static final class Output {
        public final String name;
        public final long[] shape;
        public final float[] values;
        Output(String name, long[] shape, float[] values) {
            this.name = name; this.shape = shape.clone(); this.values = values;
        }
    }
    public static final class Result {
        public final List<Output> outputs;
        Result(List<Output> outputs) { this.outputs = Collections.unmodifiableList(outputs); }
    }

    public static Result run(Context context, File model, String expectedHash,
            String inputName, float[] values, long[] shape, List<String> outputNames,
            Control control) throws Exception {
        control.check();
        requireOwnedFile(context, model);
        if (expectedHash == null || !expectedHash.matches("[a-f0-9]{64}"))
            throw new IllegalArgumentException("hashRequired");
        long budget = allocationBudget(context);
        if (model.length() <= 0 || model.length() > budget ||
                model.length() > Integer.MAX_VALUE) throw new IllegalArgumentException("memoryBudget");
        return runOwned(context, model, expectedHash, inputName, values, shape, outputNames, control, budget);
    }

    static void requireOwnedFile(Context context, File model) throws Exception {
        File root = new File(context.getFilesDir(), "input_workspace");
        // Android may alias /data/user/0 to /data/data; reject selected links,
        // not the operating system's canonical app-storage ancestry.
        if (Files.isSymbolicLink(root.toPath()) ||
                !model.getCanonicalFile().getParentFile().equals(root.getCanonicalFile()) ||
                !model.getName().matches("[a-f0-9]{32}\\.blob") ||
                Files.isSymbolicLink(model.toPath()) || !model.isFile())
            throw new IllegalArgumentException("modelNotOwned");
    }

    static long allocationBudget(Context context) {
        ActivityManager manager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(memory);
        // HC-078: conservative prototype allocation budget; never probe to exhaustion.
        long budget = Math.min(memory.availMem / 4, Runtime.getRuntime().maxMemory() / 4);
        if (memory.lowMemory || budget <= 0) throw new IllegalArgumentException("memoryBudget");
        return budget;
    }

    private static Result runOwned(Context context, File model, String expectedHash, String inputName,
            float[] values, long[] shape, List<String> outputNames, Control control, long budget) throws Exception {
        long elements = 1;
        for (long dimension : shape) {
            if (dimension <= 0 || elements > budget / Float.BYTES / dimension)
                throw new IllegalArgumentException("inputBudget");
            elements *= dimension;
        }
        if (shape.length == 0 || elements != values.length || outputNames.isEmpty() ||
                new HashSet<>(outputNames).size() != outputNames.size())
            throw new IllegalArgumentException("invalidInput");
        for (float value : values) if (!Float.isFinite(value))
            throw new IllegalArgumentException("nonFiniteInput");
        byte[] bytes;
        try (FileInputStream source = new FileInputStream(model);
                ByteArrayOutputStream copy = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192]; // HC-078: bounded streaming copy buffer.
            int count;
            while ((count = source.read(buffer)) != -1) {
                control.check();
                if (copy.size() > budget - count) throw new IllegalArgumentException("modelBudget");
                copy.write(buffer, 0, count);
            }
            bytes = copy.toByteArray();
        }
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder actual = new StringBuilder();
        for (byte b : digest) actual.append(String.format(Locale.ROOT, "%02x", b & 255));
        if (!expectedHash.contentEquals(actual)) throw new IllegalArgumentException("hashMismatch");
        control.check();
        OrtEnvironment environment = OrtEnvironment.getEnvironment(OrtLoggingLevel.ORT_LOGGING_LEVEL_FATAL);
        environment.setTelemetry(false);
        try (OrtSession.SessionOptions options = new OrtSession.SessionOptions()) {
            // HC-078: CPU-only conservative first runner; benchmarking follows real execution.
            options.setIntraOpNumThreads(1);
            options.setInterOpNumThreads(1);
            options.setSessionLogLevel(OrtLoggingLevel.ORT_LOGGING_LEVEL_FATAL);
            try (OrtSession session = environment.createSession(bytes, options)) {
                control.check();
                NodeInfo node = session.getInputInfo().get(inputName);
                if (session.getInputInfo().size() != 1 || node == null ||
                        !(node.getInfo() instanceof TensorInfo))
                    throw new IllegalArgumentException("inputContract");
                TensorInfo info = (TensorInfo) node.getInfo();
                long[] declared = info.getShape();
                if (info.type != OnnxJavaType.FLOAT || declared.length != shape.length)
                    throw new IllegalArgumentException("inputContract");
                for (int i = 0; i < shape.length; i++) if (declared[i] > 0 && declared[i] != shape[i])
                    throw new IllegalArgumentException("inputShape");
                if (!session.getOutputNames().containsAll(outputNames))
                    throw new IllegalArgumentException("outputContract");
                try (OnnxTensor tensor = OnnxTensor.createTensor(environment, FloatBuffer.wrap(values), shape);
                        OrtSession.RunOptions run = new OrtSession.RunOptions()) {
                    control.attach(run);
                    try {
                        control.check();
                        try (OrtSession.Result result = session.run(Collections.singletonMap(inputName, tensor),
                                new LinkedHashSet<>(outputNames), run)) {
                            control.check();
                            List<Output> outputs = new ArrayList<>();
                            long remaining = budget / Float.BYTES;
                            for (String name : outputNames) {
                                OnnxValue value = result.get(name).orElseThrow(() ->
                                        new IllegalArgumentException("outputMissing"));
                                if (!(value instanceof OnnxTensor) ||
                                        ((OnnxTensor) value).getInfo().type != OnnxJavaType.FLOAT)
                                    throw new IllegalArgumentException("outputType");
                                OnnxTensor output = (OnnxTensor) value;
                                long count = output.getInfo().getNumElements();
                                if (count < 0 || count > remaining || count > Integer.MAX_VALUE)
                                    throw new IllegalArgumentException("outputBudget");
                                remaining -= count;
                                float[] data = new float[(int) count];
                                output.getFloatBuffer().get(data);
                                outputs.add(new Output(name, output.getInfo().getShape(), data));
                            }
                            control.check();
                            return new Result(outputs);
                        }
                    } finally { control.detach(); }
                }
            }
        } catch (OrtException failure) {
            if (control.isCancelled()) throw new CancellationException();
            throw failure;
        }
    }
}
