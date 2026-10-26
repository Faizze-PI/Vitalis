package com.vitalis.vitalis_app.transfer;

/** Named, reviewable limits for durable model transfers. */
public final class TransferPolicy {
    // OC-176: leave a two-second margin under the foreground broadcast deadline.
    public static final long NOTIFICATION_HANDOFF_MILLIS = 8_000L; // hardcode: HC-026
    public static final int BUFFER_BYTES = 64 * 1024; // hardcode: HC-026
    public static final int CONNECT_TIMEOUT_MILLIS = 30_000; // hardcode: HC-026
    public static final int READ_TIMEOUT_MILLIS = 60_000; // hardcode: HC-026
    public static final int MAX_REDIRECTS = 5; // hardcode: HC-026
    public static final int MAX_RETRIES = 5; // hardcode: HC-026
    public static final long MIN_RETRY_DELAY_MILLIS = 1_000L; // hardcode: HC-026
    public static final long MAX_RETRY_DELAY_MILLIS = 60_000L; // hardcode: HC-026
    public static final long PROGRESS_CHECKPOINT_BYTES = 1024L * 1024L; // hardcode: HC-026

    private TransferPolicy() {}
}
