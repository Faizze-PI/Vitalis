package com.vitalis.vitalis_app.transfer;

import static org.junit.Assert.*;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public final class TransferRunControlTest {
    @Test
    public void oldGenerationCannotSignalReplacementControl() {
        Context context = ApplicationProvider.getApplicationContext();
        String identity = "replacement-generation";
        TransferRunControl control = TransferRunControl.begin(context, identity);
        assertNotNull(control);
        try {
            control.bindGeneration(1L);
            assertFalse(TransferRunControl.requestStop(context, identity, 0L));
            assertFalse(control.isStopped());
            assertTrue(TransferRunControl.requestStop(context, identity, 1L));
            assertTrue(control.isStopped());
        } finally {
            control.finish();
        }
    }

    @Test
    public void foreignOwnerCannotStopActiveRun() {
        Context context = ApplicationProvider.getApplicationContext();
        String identity = "replacement-owner";
        Thread staleOwner = new Thread();
        TransferRunControl control = TransferRunControl.begin(context, identity);
        assertNotNull(control);
        try {
            assertFalse(TransferRunControl.requestStop(context, identity, staleOwner));
            assertFalse(control.isStopped());
            assertFalse(Thread.currentThread().isInterrupted());
            assertTrue(TransferRunControl.requestStop(context, identity, Thread.currentThread()));
            assertTrue(control.isStopped());
            assertFalse("self-stop must not interrupt its own state projection",
                    Thread.currentThread().isInterrupted());
        } finally {
            control.finish();
        }
        assertFalse(TransferRunControl.requestStop(context, identity, staleOwner));
    }

    @Test
    public void rejectedDuplicateAcquisitionLeavesOwnerUntouched() {
        Context context = ApplicationProvider.getApplicationContext();
        String identity = "duplicate-owner";
        TransferRunControl first = TransferRunControl.begin(context, identity);
        assertNotNull(first);
        try {
            assertNull(TransferRunControl.begin(context, identity));
            assertFalse(first.isStopped());
        } finally {
            first.finish();
        }
        TransferRunControl next = TransferRunControl.begin(context, identity);
        assertNotNull(next);
        try {
            assertFalse(next.isStopped());
        } finally {
            next.finish();
        }
    }
}
