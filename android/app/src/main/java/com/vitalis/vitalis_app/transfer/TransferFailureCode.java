package com.vitalis.vitalis_app.transfer;

/** Stable, non-sensitive reason persisted when a transfer cannot continue. */
public enum TransferFailureCode {
    NONE,
    MISSING_TRANSFER_ID,
    MANIFEST_MISSING,
    MANIFEST_READ_FAILED,
    FOREGROUND_PROMOTION_FAILED,
    SECURITY_REJECTED,
    HTTP_FAILURE,
    INVALID_CONTENT_RANGE,
    OVERSIZED_CONTENT,
    TRUNCATED_CONTENT,
    HASH_MISMATCH,
    NETWORK_EXHAUSTED,
    RETRY_EXHAUSTED,
    SCHEDULER_REJECTED,
    TRANSFER_EXCEPTION,
    MANIFEST_PERSIST_FAILED,
    SYSTEM_STOP;

    public String wireName() {
        return name().toLowerCase(java.util.Locale.ROOT);
    }
}
