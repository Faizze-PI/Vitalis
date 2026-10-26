import java.io.IOException;
import java.nio.file.Path;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.ZipFile;

public final class VerifyAndroidNativeInventory {
    public static void main(String[] args) {
        if (args.length == 3 && args[0].equals("--manifest")) {
            try (var zip = new ZipFile(Path.of(args[1]).toFile())) {
                if (!(args[2].equals("apk") || args[2].equals("aab"))) {
                    throw new IOException("Unknown archive layout");
                }
                var entry = zip.getEntry((args[2].equals("aab") ? "base/" : "")
                        + "assets/flutter_assets/NativeAssetsManifest.json");
                if (entry == null) throw new IOException("Native Assets manifest missing");
                try (var stream = zip.getInputStream(entry)) {
                    // HC-070: Bound decompression before forwarding metadata to Dart.
                    int limit = 1024 * 1024;
                    byte[] bytes = stream.readNBytes(limit + 1);
                    if (bytes.length > limit) throw new IOException("Manifest inspection limit");
                    System.out.write(bytes);
                }
            } catch (Exception failure) {
                System.err.println("Native manifest extraction failed: " + failure.getClass().getSimpleName());
                System.exit(1);
            }
            return;
        }
        if (args.length != 2) {
            System.err.println("Expected release APK and AAB paths");
            System.exit(2);
        }
        try {
            verify(Path.of(args[0]), false);
            verify(Path.of(args[1]), true);
            System.out.println("APK and AAB native inventories contain required AArch64 libraries");
        } catch (Exception failure) {
            System.err.println("Native inventory verification failed: " + failure.getClass().getSimpleName());
            System.exit(1);
        }
    }

    static void verify(Path archive, boolean bundle) throws IOException {
        String prefix = bundle ? "base/lib/arm64-v8a/" : "lib/arm64-v8a/";
        Set<String> required = Set.of("libapp.so", "libflutter.so", "libllama.so",
                "libggml.so", "libggml-base.so", "libggml-cpu.so");
        Set<String> found = new HashSet<>();
        try (var zip = new ZipFile(archive.toFile())) {
            var entries = zip.entries();
            while (entries.hasMoreElements()) {
                var entry = entries.nextElement();
                String name = entry.getName();
                if (!name.endsWith(".so")) continue;
                if (entry.isDirectory() || !name.startsWith(prefix)) {
                    throw new IOException("Native library outside production ABI layout");
                }
                String library = name.substring(prefix.length());
                if (library.contains("/") || library.isEmpty() || !found.add(library)) {
                    throw new IOException("Invalid or duplicate native library entry");
                }
                try (var stream = zip.getInputStream(entry)) {
                    byte[] header = stream.readNBytes(64);
                    if (header.length != 64 || header[0] != 127 || header[1] != 'E'
                            || header[2] != 'L' || header[3] != 'F' || header[4] != 2
                            || header[5] != 1 || header[6] != 1) {
                        throw new IOException("Invalid ELF64 little-endian library header");
                    }
                    ByteBuffer elf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
                    if (elf.getShort(16) != 3 || Short.toUnsignedInt(elf.getShort(18)) != 183
                            || elf.getInt(20) != 1 || elf.getShort(52) != 64) {
                        throw new IOException("Native library is not an AArch64 shared object");
                    }
                }
            }
        }
        if (!found.containsAll(required)) throw new IOException("Required native library missing");
    }
}
