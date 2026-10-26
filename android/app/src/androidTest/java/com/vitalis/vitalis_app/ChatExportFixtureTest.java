package com.vitalis.vitalis_app;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.time.Instant;

/** Adds one isolated fixture; never updates or deletes existing conversation data. */
@RunWith(AndroidJUnit4.class)
public final class ChatExportFixtureTest {
    @Test
    public void seedLongHistory() {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        File path = context.getDatabasePath("vitalis.db");
        assertTrue("An initialized test installation is required", path.isFile());
        String title = "QA_Export_130_20261026";
        try (SQLiteDatabase db = SQLiteDatabase.openDatabase(path.getPath(), null,
                SQLiteDatabase.OPEN_READWRITE)) {
            db.beginTransaction();
            try {
                long chatId;
                try (Cursor existing = db.rawQuery("SELECT id FROM chats WHERE title = ?",
                        new String[]{title})) {
                    if (existing.moveToFirst()) {
                        chatId = existing.getLong(0);
                        assertTrue("Fixture title must be unique", !existing.moveToNext());
                    } else {
                        String timestamp = Instant.now().toString();
                        ContentValues chat = new ContentValues();
                        chat.put("title", title);
                        chat.put("created_at", timestamp);
                        chat.put("updated_at", timestamp);
                        chatId = db.insertOrThrow("chats", null, chat);
                        for (int index = 1; index <= 130; index++) {
                            ContentValues message = new ContentValues();
                            message.put("chat_id", chatId);
                            message.put("role", index % 2 == 1 ? "user" : "assistant");
                            message.put("content", "QA_EXPORT_1026_" + index);
                            message.put("timestamp", timestamp);
                            db.insertOrThrow("messages", null, message);
                        }
                    }
                }
                try (Cursor messages = db.rawQuery(
                        "SELECT content FROM messages WHERE chat_id = ? ORDER BY id",
                        new String[]{Long.toString(chatId)})) {
                    assertEquals(130, messages.getCount());
                    for (int index = 1; index <= 130; index++) {
                        assertTrue(messages.moveToNext());
                        assertEquals("QA_EXPORT_1026_" + index, messages.getString(0));
                    }
                }
                db.setTransactionSuccessful();
            } finally {
                db.endTransaction();
            }
        }
    }
}
