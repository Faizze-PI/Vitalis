package com.vitalis.vitalis_app.transfer;

import java.io.File;

/** Isolated child-process fixture; never launched by the application. */
public final class WriterLeaseProcessProbe {
    public static void main(String[] args) throws Exception {
        try (TransferWriterLease lease = TransferWriterLease.tryAcquire(new File(args[0]))) {
            System.out.println(lease == null ? "BUSY" : "ACQUIRED");
            System.out.flush();
            if (lease != null && args.length > 1) System.in.read();
        }
    }
}
