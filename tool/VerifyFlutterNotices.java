import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.GZIPInputStream;
import java.util.zip.ZipFile;

public final class VerifyFlutterNotices {
    public static void main(String[] args) throws Exception {
        if (args.length < 4 || args.length % 2 != 0
                || !(args[1].equals("apk") || args[1].equals("aab"))) {
            throw new IllegalArgumentException("Expected archive apk|aab package LICENSE [package LICENSE ...]");
        }
        for (int index = 2; index < args.length; index += 2) {
            verify(Path.of(args[0]), args[1].equals("aab"), args[index], Path.of(args[index + 1]));
        }
        System.out.println("Required inference dependency notices verified: " + args[1]);
    }

    static void verify(Path archive, boolean bundle, String name, Path license) throws IOException {
        String expected = normalize(Files.readString(license, StandardCharsets.UTF_8));
        if (expected.isEmpty()) throw new IOException("Empty source license: " + name);
        try (var zip = new ZipFile(archive.toFile())) {
            var entry = zip.getEntry((bundle ? "base/" : "") + "assets/flutter_assets/NOTICES.Z");
            if (entry == null) throw new IOException("Flutter notices asset missing");
            try (var compressed = zip.getInputStream(entry); var gzip = new GZIPInputStream(compressed)) {
                // HC-059: Bound inspection even when an archive contains a decompression bomb.
                int limit = 32 * 1024 * 1024;
                byte[] bytes = gzip.readNBytes(limit + 1);
                if (bytes.length > limit) throw new IOException("Flutter notices exceed inspection limit");
                String notices = normalize(new String(bytes, StandardCharsets.UTF_8));
                String separator = "-".repeat(80);
                for (String block : notices.split(separator)) {
                    int headerEnd = block.indexOf("\n\n");
                    if (headerEnd < 0) continue;
                    String header = block.substring(0, headerEnd).strip();
                    if (header.lines().anyMatch(line -> line.strip().equals(name))
                            && block.substring(headerEnd).contains(expected)) return;
                }
                throw new IOException("Required license body or attribution missing: " + name);
            }
        }
    }

    private static String normalize(String text) {
        return text.replace("\r\n", "\n").replace('\r', '\n').strip();
    }
}
