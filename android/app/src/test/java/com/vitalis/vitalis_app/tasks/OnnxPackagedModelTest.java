package com.vitalis.vitalis_app.tasks;
import static org.junit.Assert.*;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import java.io.File;
import java.nio.file.Files;
import java.util.UUID;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
@RunWith(RobolectricTestRunner.class)
@Config(sdk=28)
public final class OnnxPackagedModelTest {
 @Test public void readyPackageModelIsOwnedButCannotBeUsedAsWorkspaceInput() throws Exception {
  Context context=ApplicationProvider.getApplicationContext();
  File directory=new File(new File(context.getFilesDir(),"algorithm_packages"),UUID.randomUUID().toString().replace("-",""));
  assertTrue(directory.mkdirs());File model=new File(directory,"model.blob"),ready=new File(directory,"ready.json");
  try {
   Files.write(model.toPath(),new byte[]{1});Files.write(ready.toPath(),new byte[]{123,125});
   OnnxTaskEngine.requireOwnedModel(context,model);
   try {OnnxTaskEngine.requireOwnedFile(context,model);fail("Package accepted as loose input");} catch(IllegalArgumentException expected) {}
   assertTrue(ready.delete());
   try {OnnxTaskEngine.requireOwnedModel(context,model);fail("Uncommitted package admitted");} catch(IllegalArgumentException expected) {}
  } finally {model.delete();ready.delete();directory.delete();}
 }
 @Test public void aWorkspaceStyleIdentityOutsideBothRootsIsRejected() throws Exception {
  Context context=ApplicationProvider.getApplicationContext();File file=new File(context.getFilesDir(),UUID.randomUUID().toString().replace("-","")+".blob");
  try {Files.write(file.toPath(),new byte[]{1});try {OnnxTaskEngine.requireOwnedModel(context,file);fail("Outside model admitted");} catch(IllegalArgumentException expected) {}}
  finally {file.delete();}
 }
}
