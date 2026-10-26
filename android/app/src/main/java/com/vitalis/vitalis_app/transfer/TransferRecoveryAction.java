package com.vitalis.vitalis_app.transfer;

/** Idempotent action selected when Flutter reconciles a persisted manifest. */
public enum TransferRecoveryAction {
    RESUME_DOWNLOAD,
    RESTART_VALIDATION,
    PROJECT_INSTALLATION,
    HOLD,
    NONE;

    public static TransferRecoveryAction forManifest(TransferManifest manifest) {
        if (manifest == null) return NONE;
        if (TransferManifest.QUEUED.equals(manifest.state)
                || TransferManifest.RUNNING.equals(manifest.state)) {
            return RESUME_DOWNLOAD;
        }
        if (TransferManifest.DOWNLOADED.equals(manifest.state)
                || TransferManifest.VALIDATING.equals(manifest.state)) {
            return RESTART_VALIDATION;
        }
        if (TransferManifest.READY_TO_INSTALL.equals(manifest.state)) {
            return PROJECT_INSTALLATION;
        }
        if (TransferManifest.PAUSED.equals(manifest.state)
                || TransferManifest.FAILED.equals(manifest.state)) {
            return HOLD;
        }
        return NONE;
    }
}
