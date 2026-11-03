package com.vitalis.vitalis_app.tasks;

import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import android.graphics.Bitmap;
import java.io.FileOutputStream;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.*;
import android.os.Bundle;
import android.os.SystemClock;

/** Synthetic graph, generated from readable protobuf fields; no downloaded data. */
@RunWith(AndroidJUnit4.class)
public final class OnnxTaskEngineInstrumentationTest {
    @Test public void cancelsObservedNativeLoopThenRunsAnotherModel() throws Exception {
        Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        File directory=new File(context.getFilesDir(),"input_workspace");
        assertTrue(directory.isDirectory() || directory.mkdirs());
        File model=new File(directory,UUID.randomUUID().toString().replace("-","")+".blob");
        assertTrue(model.createNewFile());
        byte[] bytes=loopModel(1000000); // Bounded test fixture, cancelled on observed JNI entry.
        Files.write(model.toPath(),bytes);
        var control=new OnnxTaskEngine.Control();
        ExecutorService worker=Executors.newSingleThreadExecutor();
        java.util.concurrent.atomic.AtomicReference<Thread> thread=new java.util.concurrent.atomic.AtomicReference<>();
        Future<?> running=worker.submit(() -> {
            thread.set(Thread.currentThread());
            try {
                OnnxTaskEngine.run(context,model,hex(MessageDigest.getInstance("SHA-256").digest(bytes)),
                        "features",new float[]{0},new long[]{1},Collections.singletonList("result"),control);
                throw new AssertionError("Long task completed before cancellation");
            } catch(CancellationException expected) { throw expected; }
              catch(Exception failure) {throw new RuntimeException(failure);}
        });
        boolean nativeObserved=false;
        try {
            long deadline=SystemClock.elapsedRealtime()+5000;
            while(!running.isDone() && SystemClock.elapsedRealtime()<deadline) {
                Thread current=thread.get();
                if(current!=null)for(StackTraceElement frame:current.getStackTrace()) {
                    if(frame.isNativeMethod() && frame.getClassName().equals("ai.onnxruntime.OrtSession")) {
                        nativeObserved=true;break;
                    }
                }
                if(nativeObserved)break;
                SystemClock.sleep(2);
            }
            long requested=SystemClock.elapsedRealtimeNanos();
            control.cancel();
            try {running.get(2,TimeUnit.SECONDS);fail("Cancellation not reported");}
            catch(ExecutionException expected){assertTrue(expected.getCause() instanceof CancellationException);}
            long acknowledged=SystemClock.elapsedRealtimeNanos();
            assertTrue("Native run was not independently observed",nativeObserved);
            Bundle evidence=new Bundle();
            evidence.putString("vitalis.onnx.native_run_observed","true");
            evidence.putString("vitalis.onnx.cancel_to_worker_termination_us",Long.toString((acknowledged-requested)/1000));
            InstrumentationRegistry.getInstrumentation().sendStatus(0,evidence);
            executesCsvReferenceAndReleasesResources();
        } finally {
            control.cancel();worker.shutdown();
            if(running.isDone())assertTrue(model.delete()); // Never delete under a live native reader.
        }
    }

    private static byte[] loopModel(long iterations) {
        byte[] one=join(number(1,1),number(2,1),string(8,"one"),bytes(9,ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(1).array()));
        byte[] add=join(string(1,"carry"),string(1,"one"),string(2,"next"),string(4,"Add"));
        byte[] identity=join(string(1,"condition_in"),string(2,"condition_out"),string(4,"Identity"));
        byte[] body=join(bytes(1,add),bytes(1,identity),string(2,"count-body"),bytes(5,one),
                bytes(11,typedValue("iteration",7)),bytes(11,typedValue("condition_in",9)),bytes(11,value("carry",1)),
                bytes(12,typedValue("condition_out",9)),bytes(12,value("next",1)));
        byte[] trip=join(number(2,7),string(8,"trip"),bytes(9,ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(iterations).array()));
        byte[] condition=join(number(2,9),string(8,"condition"),bytes(9,new byte[]{1}));
        byte[] attribute=join(string(1,"body"),bytes(6,body),number(20,5));
        byte[] node=join(string(1,"trip"),string(1,"condition"),string(1,"features"),string(2,"result"),string(4,"Loop"),bytes(5,attribute));
        byte[] graph=join(bytes(1,node),string(2,"cancellation-reference"),bytes(5,trip),bytes(5,condition),bytes(11,value("features",1)),bytes(12,value("result",1)));
        return join(number(1,9),bytes(7,graph),bytes(8,number(2,18)));
    }
    @Test public void executesImagePreprocessingAndReferenceGraph() throws Exception {
        Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        File directory=new File(context.getFilesDir(),"input_workspace");
        assertTrue(directory.isDirectory() || directory.mkdirs());
        File model=new File(directory,UUID.randomUUID().toString().replace("-","")+".blob");
        File image=new File(directory,UUID.randomUUID().toString().replace("-","")+".blob");
        assertTrue(model.createNewFile()); assertTrue(image.createNewFile());
        Bitmap bitmap=Bitmap.createBitmap(2,2,Bitmap.Config.ARGB_8888);
        try {
            bitmap.setPixels(new int[]{0xffff0000,0xffff0000,0xff00ff00,0xff0000ff},0,2,0,0,2,2);
            try(FileOutputStream out=new FileOutputStream(image)){assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,out));}
            byte[] axes=join(number(1,2),number(2,7),string(8,"axes"),
                    bytes(9,ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN).putLong(2).putLong(3).array()));
            byte[] attribute=join(string(1,"keepdims"),number(3,0),number(20,2));
            byte[] node=join(string(1,"image"),string(1,"axes"),string(2,"mean_rgb"),string(4,"ReduceMean"),bytes(5,attribute));
            byte[] graph=join(bytes(1,node),string(2,"image-reference"),bytes(5,axes),bytes(11,value("image",1,3,2,2)),bytes(12,value("mean_rgb",1,3)));
            byte[] bytes=join(number(1,9),bytes(7,graph),bytes(8,number(2,18)));
            Files.write(model.toPath(),bytes);
            Map<String,Object> settings=new HashMap<>();
            settings.put("layout","NCHW");settings.put("resize","stretch");settings.put("interpolation","nearest");
            settings.put("color_order","RGB");settings.put("orientation","stored");settings.put("scale",1.0/255);
            settings.put("mean",Arrays.asList(0.0,0.0,0.0));settings.put("std",Arrays.asList(1.0,1.0,1.0));
            var control=new OnnxTaskEngine.Control();
            float[] pixels=OnnxImageInput.prepare(context,image,new long[]{1,3,2,2},settings,control,OnnxTaskEngine.allocationBudget(context));
            var result=OnnxTaskEngine.run(context,model,hex(MessageDigest.getInstance("SHA-256").digest(bytes)),
                    "image",pixels,new long[]{1,3,2,2},Collections.singletonList("mean_rgb"),control);
            assertArrayEquals(new float[]{.5f,.25f,.25f},result.outputs.get(0).values,0.00001f);
            assertArrayEquals(new long[]{1,3},result.outputs.get(0).shape);
        } finally {bitmap.recycle();assertTrue(model.delete());assertTrue(image.delete());}
    }
    @Test public void executesCsvReferenceAndReleasesResources() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        File directory = new File(context.getFilesDir(), "input_workspace");
        assertTrue(directory.isDirectory() || directory.mkdirs());
        File model = new File(directory, UUID.randomUUID().toString().replace("-", "") + ".blob");
        assertTrue(model.createNewFile());
        try {
            byte[] bytes = linearModel(); Files.write(model.toPath(), bytes);
            String hash = hex(MessageDigest.getInstance("SHA-256").digest(bytes));
            var result = OnnxTaskEngine.run(context, model, hash, "features",
                    new float[]{1,2,-1,3,0,0}, new long[]{3,2},
                    Collections.singletonList("prediction"), new OnnxTaskEngine.Control());
            assertArrayEquals(new float[]{3,2,0}, result.outputs.get(0).values, 0.00001f);
            assertArrayEquals(new long[]{3,1}, result.outputs.get(0).shape);
            assertEquals("prediction", result.outputs.get(0).name);
        } finally { assertTrue(!model.exists() || model.delete()); }
    }

    @Test public void cancellationBeforeLoadNeverStartsAnOrtSession() throws Exception {
        var control = new OnnxTaskEngine.Control(); control.cancel();
        try {
            OnnxTaskEngine.run(InstrumentationRegistry.getInstrumentation().getTargetContext(),
                    new File("/not-an-input"), "", "features", new float[0],
                    new long[]{1}, Collections.singletonList("prediction"), control);
            fail("Cancelled request was admitted");
        } catch (CancellationException expected) { assertTrue(control.isCancelled()); }
    }

    // ONNX ModelProto/GraphProto/TensorProto wire field numbers, not runtime policy.
    private static byte[] linearModel() {
        byte[] weights = join(number(1,2), number(1,1), number(2,1), string(8,"weights"),
                bytes(9, ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putFloat(1).putFloat(1).array()));
        byte[] node = join(string(1,"features"),string(1,"weights"),string(2,"prediction"),string(4,"MatMul"));
        byte[] graph = join(bytes(1,node),string(2,"vitalis-reference"),bytes(5,weights),bytes(11,value("features",3,2)),bytes(12,value("prediction",3,1)));
        return join(number(1,9),bytes(7,graph),bytes(8,number(2,18)));
    }
    private static byte[] value(String name, int... dimensions) {
        return typedValue(name,1,dimensions);
    }
    private static byte[] typedValue(String name,int type,int... dimensions) {
        byte[] shape=new byte[0];
        for(int dimension:dimensions)shape=join(shape,bytes(1,number(1,dimension)));
        return join(string(1,name),bytes(2,bytes(1,join(number(1,type),bytes(2,shape)))));
    }
    private static byte[] number(int field,long value) {return join(varint(field<<3),varint(value));}
    private static byte[] string(int field,String value) {return bytes(field,value.getBytes(StandardCharsets.UTF_8));}
    private static byte[] bytes(int field,byte[] value) {return join(varint((field<<3)|2),varint(value.length),value);}
    private static byte[] join(byte[]... parts) {var out=new ByteArrayOutputStream();for(var part:parts)out.write(part,0,part.length);return out.toByteArray();}
    private static byte[] varint(long value) {var out=new ByteArrayOutputStream();while((value&~127L)!=0){out.write((int)(value&127)|128);value>>>=7;}out.write((int)value);return out.toByteArray();}
    private static String hex(byte[] bytes) {var out=new StringBuilder();for(byte b:bytes)out.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return out.toString();}
}
