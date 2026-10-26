package com.vitalis.vitalis_app.transfer;

/** Scheduler action associated with the latest stop or terminal failure. */
public enum TransferStopDisposition {
    NONE(false),
    USER_PAUSED(false),
    USER_CANCELLED(false),
    SYSTEM_RETRY(true),
    PERMANENT_FAILURE(false);

    private final boolean reschedule;

    TransferStopDisposition(boolean reschedule) {
        this.reschedule = reschedule;
    }

    public boolean shouldReschedule() {
        return reschedule;
    }

    public String wireName() {
        return name().toLowerCase(java.util.Locale.ROOT);
    }
}
