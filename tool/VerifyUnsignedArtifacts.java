import java.nio.file.Path;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.zip.CRC32;
import java.util.zip.ZipFile;

public final class VerifyUnsignedArtifacts {
    public static void main(String[] args) {
        if (args.length != 2) {
            System.err.println("Expected release APK and AAB paths");
            System.exit(2);
        }
        try {
            for (String argument : args) verify(Path.of(argument));
            System.out.println("Both release archives contain no JAR signatures or APK signing block");
        } catch (Exception failure) {
            System.err.println("Unsigned archive verification failed: " + failure.getClass().getSimpleName());
            System.exit(1);
        }
    }

    static void verify(Path path) throws IOException {
        // APK uses ordinary ZIP; reject unsupported ZIP64/multipart structures.
        try (var input = new RandomAccessFile(path.toFile(), "r")) {
            long length = input.length();
            if (length < 22) throw new IOException("Missing ZIP footer");
            byte[] tail = new byte[(int) Math.min(length, 22L + 65535L)];
            input.seek(length - tail.length);
            input.readFully(tail);
            ByteBuffer data = ByteBuffer.wrap(tail).order(ByteOrder.LITTLE_ENDIAN);
            int footer = -1;
            for (int index = tail.length - 22; index >= 0; index--) {
                if (data.getInt(index) == 0x06054b50
                        && index + 22 + Short.toUnsignedInt(data.getShort(index + 20)) == tail.length) {
                    footer = index;
                    break;
                }
            }
            if (footer < 0 || data.getShort(footer + 4) != 0 || data.getShort(footer + 6) != 0
                    || data.getShort(footer + 8) != data.getShort(footer + 10)
                    || Short.toUnsignedInt(data.getShort(footer + 10)) == 65535) {
                throw new IOException("Invalid or unsupported ZIP footer");
            }
            long central = Integer.toUnsignedLong(data.getInt(footer + 16));
            long centralSize = Integer.toUnsignedLong(data.getInt(footer + 12));
            long footerOffset = length - tail.length + footer;
            if (central + centralSize != footerOffset) throw new IOException("Invalid ZIP directory bounds");
            if (central >= 16) {
                byte[] magic = new byte[16];
                input.seek(central - magic.length);
                input.readFully(magic);
                if (Arrays.equals(magic, "APK Sig Block 42".getBytes(StandardCharsets.US_ASCII))) {
                    throw new IOException("APK signing block present");
                }
            }
        }
        try (var archive = new ZipFile(path.toFile())) {
            var names = new HashSet<String>();
            var entries = archive.entries();
            byte[] buffer = new byte[65536];
            while (entries.hasMoreElements()) {
                var entry = entries.nextElement();
                String name = entry.getName().toUpperCase(Locale.ROOT);
                if (!names.add(entry.getName())) throw new IOException("Duplicate archive entry");
                if (name.matches("META-INF/[^/]+\\.(SF|RSA|DSA|EC)")
                        || name.startsWith("META-INF/SIG-")) throw new IOException("JAR signature present");
                if (entry.isDirectory()) continue;
                CRC32 checksum = new CRC32();
                long size = 0;
                try (var stream = archive.getInputStream(entry)) {
                    int count;
                    while ((count = stream.read(buffer)) != -1) {
                        checksum.update(buffer, 0, count);
                        size = Math.addExact(size, count);
                    }
                }
                if (size != entry.getSize() || checksum.getValue() != entry.getCrc()) {
                    throw new IOException("Invalid archive entry");
                }
            }
        }
    }
}
