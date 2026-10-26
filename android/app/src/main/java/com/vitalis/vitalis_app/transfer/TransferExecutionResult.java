package com.vitalis.vitalis_app.transfer;

/** Typed scheduler-neutral result returned by the transfer engine. */
public enum TransferExecutionResult {
    SUCCESS(false),
    PAUSED(false),
    CANCELLED(false),
    RETRY(true),
    FAILURE(false);

    private final boolean reschedule;

    TransferExecutionResult(boolean reschedule) {
        this.reschedule = reschedule;
    }

    public boolean shouldReschedule() {
        return reschedule;
    }
}
