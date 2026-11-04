package com.vitalis.vitalis_app.tasks;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.io.File;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import io.flutter.plugin.common.*;

/** Separate control channel remains responsive while native CPU work runs. */
public final class OnnxTaskChannel implements MethodChannel.MethodCallHandler {
    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor();
    private static final AtomicReference<Job> ACTIVE = new AtomicReference<>();
    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());
    private static final class Job {
        final String id; final OnnxTaskEngine.Control control=new OnnxTaskEngine.Control();
        Job(String id) {this.id=id;}
    }
    public OnnxTaskChannel(Context context) {this.context=context.getApplicationContext();}
    public void register(BinaryMessenger messenger) {
        new MethodChannel(messenger,"vitalis/custom_tasks").setMethodCallHandler(this); // HC-078
    }
    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            if ("limits".equals(call.method)) {
                long budget=OnnxTaskEngine.allocationBudget(context);
                Map<String,Object> limits=new HashMap<>();
                limits.put("maxInputElements",Math.min(budget/Float.BYTES,Integer.MAX_VALUE));
                limits.put("maxModelBytes",Math.min(budget,Integer.MAX_VALUE)); limits.put("maxTextBytes",budget/4); result.success(limits); return;
            }
            String id=call.argument("requestId");
            if(id==null || !id.matches("[a-f0-9]{32}")) throw new IllegalArgumentException();
            if("cancel".equals(call.method)) {
                Job job=ACTIVE.get();
                if(job!=null && job.id.equals(id)) job.control.cancel();
                result.success(null); return; // Intent only; Run resolves after native cleanup.
            }
            if(!"run".equals(call.method)) {result.notImplemented(); return;}
            Map<String,Object> args=call.arguments();
            Job job=new Job(id);
            if(!ACTIVE.compareAndSet(null,job)) {result.error("runtimeBusy","Another task is running.",null);return;}
            WORKER.execute(() -> execute(job,args,result));
        } catch(Exception failure) {result.error("invalidTaskRequest","Task request could not be admitted.",null);}
    }
    private File owned(String id) throws Exception {
        if(id==null || !id.matches("[a-f0-9]{32}")) throw new IllegalArgumentException("fileIdentity");
        File file=new File(new File(context.getFilesDir(),"input_workspace"),id+".blob");
        OnnxTaskEngine.requireOwnedFile(context,file); return file;
    }
    private File packageModel(String id) throws Exception {
        if(id==null || !id.matches("[a-f0-9]{32}")) throw new IllegalArgumentException("packageIdentity"); // HC-082
        File model=new File(new File(new File(context.getFilesDir(),"algorithm_packages"),id),"model.blob");
        OnnxTaskEngine.requireOwnedModel(context,model); return model;
    }
    @SuppressWarnings("unchecked")
    private void execute(Job job, Map<String,Object> args, MethodChannel.Result result) {
        Object value=null; String code=null;
        try {
            job.control.check();
            List<Number> dimensions=(List<Number>)args.get("shape");
            long[] shape=new long[dimensions.size()];
            for(int i=0;i<shape.length;i++)shape[i]=dimensions.get(i).longValue();
            float[] input;
            if("image".equals(args.get("kind"))) {
                input=OnnxImageInput.prepare(context,owned((String)args.get("inputId")),shape,
                        (Map<String,Object>)args.get("image"),job.control,OnnxTaskEngine.allocationBudget(context));
            } else if("csv".equals(args.get("kind"))) input=(float[])args.get("values");
            else throw new IllegalArgumentException("inputKind");
            if(args.containsKey("modelPackageId") && args.containsKey("modelId")) throw new IllegalArgumentException("ambiguousModelIdentity");
            File model=args.containsKey("modelPackageId") ? packageModel((String)args.get("modelPackageId")) : owned((String)args.get("modelId"));
            var output=OnnxTaskEngine.run(context,model,
                    (String)args.get("modelSha256"),(String)args.get("inputName"),input,shape,
                    (List<String>)args.get("outputs"),job.control);
            List<Map<String,Object>> rows=new ArrayList<>();
            for(var tensor:output.outputs) {
                Map<String,Object> row=new HashMap<>();
                row.put("name",tensor.name); row.put("shape",tensor.shape); row.put("values",tensor.values); rows.add(row);
            }
            Map<String,Object> response=new HashMap<>();
            response.put("requestId",job.id); response.put("outputs",rows); response.put("backend","ONNX CPU");
            value=response;
        } catch(CancellationException failure) {code="cancelled";}
          catch(IllegalArgumentException failure) {code="invalidInputOrModel";}
          catch(LinkageError failure) {code="backendUnavailable";}
          catch(OutOfMemoryError failure) {code="memoryBudget";}
          catch(Exception failure) {code="executionFailed";}
        finally {ACTIVE.compareAndSet(job,null);}
        final String terminal=code; final Object response=value;
        main.post(() -> {
            if(terminal==null)result.success(response);
            else result.error(terminal,"Task ended ("+terminal+"). Check the declared model/input contract.",null);
        });
    }
}
