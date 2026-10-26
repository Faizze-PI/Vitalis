import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.GZIPOutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class VerifyFlutterNoticesTest {
    public static void main(String[] args) throws Exception {
        Path directory = Files.createTempDirectory("vitalis-notices-");
        try {
            Path license = directory.resolve("LICENSE");
            Files.writeString(license, "Copyright Example\nPermission granted.\n");
            for (boolean bundle : new boolean[] {false, true}) {
                Path archive = directory.resolve(bundle ? "fixture.aab" : "fixture.apk");
                write(archive, bundle, "llm_core\n\nCopyright Example\nPermission granted.\n");
                VerifyFlutterNotices.verify(archive, bundle, "llm_core", license);
                write(archive, bundle, "llm_core\nllm_llamacpp\n\nCopyright Example\nPermission granted.\n");
                VerifyFlutterNotices.verify(archive, bundle, "llm_core", license);
                VerifyFlutterNotices.verify(archive, bundle, "llm_llamacpp", license);
                write(archive, bundle, "llm_core\n");
                rejects(archive, bundle, license);
                write(archive, bundle, "another_package\n\nCopyright Example\nPermission granted.\n");
                rejects(archive, bundle, license);
                write(archive, bundle, "llm_core\r\n\r\nCopyright Example\r\nPermission granted.\r\n");
                VerifyFlutterNotices.verify(archive, bundle, "llm_core", license);
                try (var zip = new ZipOutputStream(Files.newOutputStream(archive))) {
                    zip.putNextEntry(new ZipEntry("unrelated"));
                    zip.write(1);
                }
                rejects(archive, bundle, license);
            }
            System.out.println("Flutter notice fixtures pass: APK/AAB, missing body, attribution, line endings and missing asset");
        } finally {
            try (var files = Files.list(directory)) {
                for (Path file : files.toList()) Files.delete(file);
            }
            Files.delete(directory);
        }
    }

    private static void rejects(Path archive, boolean bundle, Path license) throws Exception {
        try {
            VerifyFlutterNotices.verify(archive, bundle, "llm_core", license);
        } catch (java.io.IOException expected) {
            return;
        }
        throw new AssertionError("Missing notice was accepted");
    }

    private static void write(Path archive, boolean bundle, String text) throws Exception {
        try (var zip = new ZipOutputStream(Files.newOutputStream(archive))) {
            zip.putNextEntry(new ZipEntry((bundle ? "base/" : "") + "assets/flutter_assets/NOTICES.Z"));
            var compressed = new java.io.ByteArrayOutputStream();
            try (var gzip = new GZIPOutputStream(compressed)) {
                gzip.write(text.getBytes(StandardCharsets.UTF_8));
            }
            zip.write(compressed.toByteArray());
        }
    }
}
