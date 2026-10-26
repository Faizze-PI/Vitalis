import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class VerifyUnsignedArtifactsTest {
    public static void main(String[] args) throws Exception {
        Path directory = Files.createTempDirectory("vitalis-unsigned-test-");
        try {
            Path valid = directory.resolve("unsigned.apk");
            archive(valid, "AndroidManifest.xml");
            VerifyUnsignedArtifacts.verify(valid);
            Path caseDistinct = directory.resolve("case-distinct.apk");
            try (var output = new ZipOutputStream(Files.newOutputStream(caseDistinct))) {
                for (String name : new String[] {"res/A.png", "res/a.png"}) {
                    output.putNextEntry(new ZipEntry(name));
                    output.write(new byte[] {1, 2, 3});
                    output.closeEntry();
                }
            }
            VerifyUnsignedArtifacts.verify(caseDistinct);
            Path jarSigned = directory.resolve("signed.aab");
            archive(jarSigned, "META-INF/TEST.RSA");
            rejects(jarSigned);
            Path sfSigned = directory.resolve("signed-sf.apk");
            archive(sfSigned, "META-INF/test.sf");
            rejects(sfSigned);
            Path malformed = directory.resolve("malformed.apk");
            Files.write(malformed, new byte[] {1, 2, 3});
            rejects(malformed);
            rejects(directory.resolve("missing.apk"));

            byte[] bytes = Files.readAllBytes(valid);
            int eocd = bytes.length - 22;
            int central = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).getInt(eocd + 16);
            byte[] block = new byte[32];
            ByteBuffer.wrap(block).order(ByteOrder.LITTLE_ENDIAN).putLong(24L).putLong(24L)
                    .put("APK Sig Block 42".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            byte[] signed = new byte[bytes.length + block.length];
            System.arraycopy(bytes, 0, signed, 0, central);
            System.arraycopy(block, 0, signed, central, block.length);
            System.arraycopy(bytes, central, signed, central + block.length, bytes.length - central);
            ByteBuffer.wrap(signed).order(ByteOrder.LITTLE_ENDIAN).putInt(eocd + block.length + 16, central + block.length);
            Path v2 = directory.resolve("signing-block.apk");
            Files.write(v2, signed);
            rejects(v2);
            Path truncated = directory.resolve("truncated.apk");
            Files.write(truncated, Arrays.copyOf(bytes, bytes.length - 1));
            rejects(truncated);
            System.out.println("Unsigned archive fixtures pass: unsigned, JAR signatures, signing block, malformed, missing and truncated");
        } finally {
            try (var files = Files.list(directory)) {
                for (Path file : files.toList()) Files.delete(file);
            }
            Files.delete(directory);
        }
    }

    private static void archive(Path path, String entry) throws Exception {
        try (var output = new ZipOutputStream(Files.newOutputStream(path))) {
            output.putNextEntry(new ZipEntry(entry));
            output.write(new byte[] {1, 2, 3});
            output.closeEntry();
        }
    }

    private static void rejects(Path path) throws Exception {
        try {
            VerifyUnsignedArtifacts.verify(path);
        } catch (java.io.IOException expected) {
            return;
        }
        throw new AssertionError("Signed or invalid archive accepted: " + path.getFileName());
    }
}
