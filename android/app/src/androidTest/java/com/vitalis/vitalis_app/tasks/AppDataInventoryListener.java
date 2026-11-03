package com.vitalis.vitalis_app.tasks;

import org.junit.runner.Description;
import org.junit.runner.notification.RunListener;
import androidx.test.platform.app.InstrumentationRegistry;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.os.Bundle;
import java.io.File;
import java.io.FileInputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.TreeMap;
import java.util.Arrays;

/** Read-only upgrade evidence. Emits counts/hashes, never rows or private text. */
public final class AppDataInventoryListener extends RunListener {
    @Override public void testRunStarted(Description description) {
        Bundle result;
        try {result=capture();}
        catch(Exception failure) {
            result=new Bundle();result.putString("vitalis.inventory.status","UNVERIFIED_"+failure.getClass().getSimpleName());
        }
        InstrumentationRegistry.getInstrumentation().sendStatus(0,result);
    }
    private Bundle capture() throws Exception {
        Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        File file=context.getDatabasePath("vitalis.db");
        if(!file.isFile())throw new IllegalStateException("Existing database unavailable");
        Bundle result=new Bundle();
        try(SQLiteDatabase db=SQLiteDatabase.openDatabase(file.getPath(),null,SQLiteDatabase.OPEN_READONLY)) {
            result.putString("vitalis.inventory.schema_version",Integer.toString(db.getVersion()));
            for(String table:new String[]{"chats","messages","notes","personas","model_settings","chat_persona",
                    "chat_note_attachments","models","model_files","download_jobs","hub_search_cache",
                    "model_installation_journal","model_installation_shards","chat_file_attachments"}) {
                boolean exists;
                try(Cursor names=db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?",new String[]{table})) {
                    exists=names.moveToFirst();
                }
                if(!exists) {
                    if(table.equals("chats") || table.equals("messages"))throw new IllegalStateException("Required saved-content table missing");
                    result.putString("vitalis.inventory."+table,"absent");continue;
                }
                TreeMap<Integer,String> primary=new TreeMap<>();
                try(Cursor columns=db.rawQuery("PRAGMA table_info("+table+")",null)) {
                    while(columns.moveToNext()) {
                        int order=columns.getInt(columns.getColumnIndexOrThrow("pk"));
                        if(order>0)primary.put(order,"\""+columns.getString(columns.getColumnIndexOrThrow("name")).replace("\"","\"\"")+"\"");
                    }
                }
                String order=primary.isEmpty()?"rowid":String.join(",",primary.values());
                MessageDigest hash=MessageDigest.getInstance("SHA-256");long count=0;
                try(Cursor rows=db.rawQuery("SELECT * FROM "+table+" ORDER BY "+order,null)) {
                    while(rows.moveToNext()) {
                        count++;
                        for(int column=0;column<rows.getColumnCount();column++) {
                            int type=rows.getType(column);hash.update((byte)type);
                            switch(type) {
                                case Cursor.FIELD_TYPE_INTEGER:
                                    hash.update(ByteBuffer.allocate(8).putLong(rows.getLong(column)).array());break;
                                case Cursor.FIELD_TYPE_FLOAT:
                                    hash.update(ByteBuffer.allocate(8).putDouble(rows.getDouble(column)).array());break;
                                case Cursor.FIELD_TYPE_STRING:
                                    field(hash,rows.getString(column).getBytes(StandardCharsets.UTF_8));break;
                                case Cursor.FIELD_TYPE_BLOB:field(hash,rows.getBlob(column));break;
                                case Cursor.FIELD_TYPE_NULL:break;
                                default:throw new IllegalStateException("Unknown SQLite cell type");
                            }
                        }
                    }
                }
                StringBuilder hex=new StringBuilder();
                for(byte b:hash.digest())hex.append(String.format(Locale.ROOT,"%02x",b&255));
                result.putString("vitalis.inventory."+table,count+":"+hex);
            }
        }
        File workspace=new File(context.getFilesDir(),"input_workspace");
        if(workspace.exists()) {
            File[] files=workspace.listFiles((dir,name)->name.matches("[a-f0-9]{32}\\.(json|blob)"));
            if(files==null)throw new IllegalStateException("Input inventory unavailable");
            Arrays.sort(files,(a,b)->a.getName().compareTo(b.getName()));
            MessageDigest digest=MessageDigest.getInstance("SHA-256");
            for(File input:files) {
                if(java.nio.file.Files.isSymbolicLink(input.toPath()) || !input.isFile())throw new IllegalStateException("Input inventory unverified");
                field(digest,input.getName().getBytes(StandardCharsets.UTF_8));
                digest.update(ByteBuffer.allocate(8).putLong(input.length()).array());
                try(FileInputStream stream=new FileInputStream(input)) {
                    byte[] buffer=new byte[65536];int count;
                    while((count=stream.read(buffer))!=-1)digest.update(buffer,0,count);
                }
            }
            StringBuilder hex=new StringBuilder();for(byte b:digest.digest())hex.append(String.format(Locale.ROOT,"%02x",b&255));
            result.putString("vitalis.inventory.input_files",files.length+":"+hex);
        } else result.putString("vitalis.inventory.input_files","absent");
        result.putString("vitalis.inventory.status","CAPTURED_READ_ONLY");
        return result;
    }
    private static void field(MessageDigest hash,byte[] value) {
        hash.update(ByteBuffer.allocate(4).putInt(value.length).array());hash.update(value);
    }
}
