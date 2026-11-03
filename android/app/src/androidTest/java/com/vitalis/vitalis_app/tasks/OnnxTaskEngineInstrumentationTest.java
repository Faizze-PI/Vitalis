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
import java.util.UUID;
import java.util.concurrent.CancellationException;

/** Synthetic graph, generated from readable protobuf fields; no downloaded data. */
@RunWith(AndroidJUnit4.class)
public final class OnnxTaskEngineInstrumentationTest {
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
    private static byte[] value(String name, int rows, int columns) {
        byte[] shape=join(bytes(1,number(1,rows)),bytes(1,number(1,columns)));
        return join(string(1,name),bytes(2,bytes(1,join(number(1,1),bytes(2,shape)))));
    }
    private static byte[] number(int field,long value) {return join(varint(field<<3),varint(value));}
    private static byte[] string(int field,String value) {return bytes(field,value.getBytes(StandardCharsets.UTF_8));}
    private static byte[] bytes(int field,byte[] value) {return join(varint((field<<3)|2),varint(value.length),value);}
    private static byte[] join(byte[]... parts) {var out=new ByteArrayOutputStream();for(var part:parts)out.write(part,0,part.length);return out.toByteArray();}
    private static byte[] varint(long value) {var out=new ByteArrayOutputStream();while((value&~127L)!=0){out.write((int)(value&127)|128);value>>>=7;}out.write((int)value);return out.toByteArray();}
    private static String hex(byte[] bytes) {var out=new StringBuilder();for(byte b:bytes)out.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return out.toString();}
}
