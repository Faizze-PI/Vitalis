package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.StandardMethodCodec;
import io.flutter.plugin.common.FlutterException;
import java.io.File;
import java.nio.ByteBuffer;
import java.util.Collections;
import java.util.Map;
import java.util.HashMap;
import java.nio.file.Files;
import java.nio.charset.StandardCharsets;
import org.junit.Test;
import org.junit.After;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public final class TransferChannelTest {
    @Test
    @Config(sdk = 34)
    public void channelPauseRecoveryAndCancelPreserveDurableOwnership() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferManifestStore store = new TransferManifestStore(context);
        File partial = new File(context.getFilesDir(), "models/channel-control.gguf.part");
        Files.createDirectories(partial.getParentFile().toPath());
        Files.write(partial.toPath(), new byte[] {1, 2, 3});
        store.write(new TransferManifest("channel-test", "job", "model", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/0123456789012345678901234567890123456789/model.gguf",
                partial.getPath(), 20L, null, 3L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L));
        Messenger messenger = new Messenger();
        new TransferController(context).register(messenger);
        Map<String, Object> args = new HashMap<>();
        args.put("transferId", "channel-test");
        args.put("jobId", "job");
        invoke(messenger, "pause", args);
        assertEquals(TransferManifest.PAUSED, store.read("channel-test").state);
        assertTrue(store.read("channel-test").stopAcknowledged);
        assertArrayEquals(new byte[] {1, 2, 3}, Files.readAllBytes(partial.toPath()));
        Map<?, ?> recovered = (Map<?, ?>) invoke(messenger, "recoverStop", args);
        assertEquals(TransferManifest.PAUSED, recovered.get("state"));
        assertEquals(Boolean.TRUE, recovered.get("stopAcknowledged"));
        assertTrue(((java.util.List<?>) invoke(messenger, "list", null)).stream()
                .anyMatch(item -> "channel-test".equals(((Map<?, ?>) item).get("transferId"))));
        invoke(messenger, "cancel", args);
        assertEquals(TransferManifest.CANCELLED, store.read("channel-test").state);
        assertTrue(store.read("channel-test").stopAcknowledged);
        assertFalse(partial.exists());
    }

    @Test
    public void unknownMethodDoesNotMutateTransferRecords() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferManifestStore store = new TransferManifestStore(context);
        Messenger messenger = new Messenger();
        new TransferController(context).register(messenger);
        assertNull(invoke(messenger, "unsupported", null));
        assertNull(store.read("channel-test"));
    }

    private Object invoke(Messenger messenger, String method, Object arguments) {
        ByteBuffer request = StandardMethodCodec.INSTANCE.encodeMethodCall(new MethodCall(method, arguments));
        request.flip();
        Object[] response = {null};
        messenger.handler.onMessage(request, reply -> {
            if (reply == null) return;
            reply.flip();
            response[0] = StandardMethodCodec.INSTANCE.decodeEnvelope(reply);
        });
        return response[0];
    }

    @After
    public void removeOwnedFixtures() throws Exception {
        TransferManifestStore store = new TransferManifestStore(ApplicationProvider.getApplicationContext());
        store.delete("corrupt-channel-test");
        store.delete("channel-test");
        store.delete("pending-channel-test");
    }

    @Test
    public void pendingStopReplyIsTypedWithoutResumingTheWriter() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferManifestStore store = new TransferManifestStore(context);
        String revision = "0123456789012345678901234567890123456789";
        String source = "https://huggingface.co/publisher/model/resolve/" + revision + "/model.gguf";
        File partial = new File(context.getFilesDir(), "models/pending-channel.gguf.part");
        store.delete("pending-channel-test");
        store.write(new TransferManifest("pending-channel-test", "job", "model", "publisher/model",
                revision, source, partial.getPath(), 20L, null, 0L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L).withStopRequest(false));
        Map<String, Object> arguments = new HashMap<>();
        arguments.put("transferId", "pending-channel-test");
        arguments.put("jobId", "job"); arguments.put("modelId", "model");
        arguments.put("repository", "publisher/model"); arguments.put("revision", revision);
        arguments.put("sourceUrl", source); arguments.put("partialPath", partial.getPath());
        arguments.put("expectedBytes", 20L);
        Messenger messenger = new Messenger();
        new TransferController(context).register(messenger);
        ByteBuffer request = StandardMethodCodec.INSTANCE.encodeMethodCall(new MethodCall("enqueue", arguments));
        request.flip();
        FlutterException[] error = {null};
        messenger.handler.onMessage(request, reply -> {
            reply.flip();
            try { StandardMethodCodec.INSTANCE.decodeEnvelope(reply); }
            catch (FlutterException failure) { error[0] = failure; }
        });
        assertNotNull(error[0]);
        assertEquals("transfer_stop_pending", error[0].code);
        assertEquals(TransferManifest.PAUSED, store.read("pending-channel-test").state);
        assertFalse(store.read("pending-channel-test").stopAcknowledged);
    }

    @Test
    public void errorReplyDoesNotEchoCorruptManifestContents() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferManifestStore store = new TransferManifestStore(context);
        store.delete("corrupt-channel-test");
        String privateText = "private_secret_phrase";
        File file = new File(context.getFilesDir(), "transfers/corrupt-channel-test.json");
        Files.write(file.toPath(), privateText.getBytes(StandardCharsets.UTF_8));
        Messenger messenger = new Messenger();
        new TransferController(context).register(messenger);
        ByteBuffer request = StandardMethodCodec.INSTANCE.encodeMethodCall(new MethodCall(
                "status", Collections.singletonMap("transferId", "corrupt-channel-test")));
        request.flip();
        FlutterException[] error = {null};
        messenger.handler.onMessage(request, reply -> {
            reply.flip();
            try {
                StandardMethodCodec.INSTANCE.decodeEnvelope(reply);
            } catch (FlutterException failure) {
                error[0] = failure;
            }
        });
        assertNotNull(error[0]);
        assertEquals("transfer_failure", error[0].code);
        assertFalse(String.valueOf(error[0].getMessage()).contains(privateText));
    }

    @Test
    public void manifestChannelUsesBackgroundQueueAndReturnsActualRecord() throws Exception {
        Context context = ApplicationProvider.getApplicationContext();
        TransferManifestStore store = new TransferManifestStore(context);
        store.delete("channel-test");
        File partial = new File(context.getFilesDir(), "models/channel.gguf.part");
        store.write(new TransferManifest("channel-test", "job", "model", "publisher/model",
                "0123456789012345678901234567890123456789",
                "https://huggingface.co/publisher/model/resolve/"
                        + "0123456789012345678901234567890123456789/model.gguf",
                partial.getPath(), 20L, null, 0L, 0,
                TransferManifest.QUEUED, null, null, 1L, 1L));
        Messenger messenger = new Messenger();
        new TransferController(context).register(messenger);
        assertEquals("vitalis/model_transfers", messenger.channel);
        assertSame("disk-backed transfer handlers must use a background TaskQueue",
                messenger.background, messenger.registeredQueue);
        ByteBuffer request = StandardMethodCodec.INSTANCE.encodeMethodCall(
                new MethodCall("status", Collections.singletonMap("transferId", "channel-test")));
        request.flip();
        Object[] response = {null};
        messenger.handler.onMessage(request, reply -> {
            reply.flip();
            response[0] = StandardMethodCodec.INSTANCE.decodeEnvelope(reply);
        });
        assertTrue(response[0] instanceof Map);
        Map<?, ?> record = (Map<?, ?>) response[0];
        assertEquals("job", record.get("jobId"));
        assertEquals(1L, ((Number) record.get("stateRevision")).longValue());
        assertEquals(TransferManifest.QUEUED, record.get("state"));
    }

    static final class Messenger implements BinaryMessenger {
        final TaskQueue background = new TaskQueue() {};
        TaskQueue registeredQueue;
        String channel;
        BinaryMessageHandler handler;
        @Override public TaskQueue makeBackgroundTaskQueue() { return background; }
        @Override public void setMessageHandler(String name, BinaryMessageHandler value) {
            channel = name; handler = value; registeredQueue = null;
        }
        @Override public void setMessageHandler(String name, BinaryMessageHandler value, TaskQueue queue) {
            channel = name; handler = value; registeredQueue = queue;
        }
        @Override public void send(String name, ByteBuffer value) { throw new AssertionError("Unexpected send"); }
        @Override public void send(String name, ByteBuffer value, BinaryReply reply) {
            throw new AssertionError("Unexpected send");
        }
    }
}
