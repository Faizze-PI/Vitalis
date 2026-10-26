package com.vitalis.vitalis_app.transfer;

import android.app.NotificationManager;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import android.database.sqlite.SQLiteOpenHelper;
import android.service.notification.StatusBarNotification;

/** Native notification identities only; never opens or resets the chat database. */
final class TransferNotificationIds extends SQLiteOpenHelper {
    private static final int ID_BASE = 10_000; // hardcode: HC-034

    private TransferNotificationIds(Context context) {
        super(context.getApplicationContext(), "transfer_notification_ids.db", null, 1,
                database -> { throw new SQLiteException("Notification identity store corrupt"); });
    }

    static int forTransfer(Context context, String transferId) {
        if (transferId == null || transferId.isEmpty()) {
            throw new IllegalArgumentException("Missing transfer identity");
        }
        try (TransferNotificationIds store = new TransferNotificationIds(context)) {
            SQLiteDatabase database = store.getWritableDatabase();
            database.beginTransaction();
            try {
                try (Cursor row = database.query("identities", new String[] {"id"},
                        "transfer_id = ?", new String[] {transferId}, null, null, null)) {
                    if (row.moveToFirst()) {
                        int id = platformId(row.getLong(0));
                        database.setTransactionSuccessful();
                        return id;
                    }
                }
                // Reserve visible legacy IDs before allocating; never replace a
                // notification whose old transfer identity cannot be recovered.
                NotificationManager manager = context.getSystemService(NotificationManager.class);
                if (manager == null) throw new IllegalStateException("Notification inventory unavailable");
                for (StatusBarNotification active : manager.getActiveNotifications()) {
                    if (active.getId() <= ID_BASE) continue;
                    ContentValues reserved = new ContentValues();
                    reserved.put("id", (long) active.getId() - ID_BASE);
                    database.insertWithOnConflict("identities", null, reserved,
                            SQLiteDatabase.CONFLICT_IGNORE);
                }
                ContentValues values = new ContentValues();
                values.put("transfer_id", transferId);
                int id = platformId(database.insertOrThrow("identities", null, values));
                database.setTransactionSuccessful();
                return id;
            } finally {
                database.endTransaction();
            }
        }
    }

    private static int platformId(long rowId) {
        if (rowId <= 0 || rowId > Integer.MAX_VALUE - ID_BASE) {
            throw new SQLiteException("Notification identity space exhausted");
        }
        return ID_BASE + (int) rowId;
    }

    @Override
    public void onCreate(SQLiteDatabase database) {
        // Never reuse identities while an older immutable PendingIntent may exist.
        database.execSQL("CREATE TABLE identities (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                + "transfer_id TEXT UNIQUE)");
    }

    @Override
    public void onUpgrade(SQLiteDatabase database, int oldVersion, int newVersion) {
        throw new SQLiteException("Unsupported notification identity schema");
    }
}
