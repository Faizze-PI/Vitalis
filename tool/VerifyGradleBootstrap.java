import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/** Dependency-free publisher identity check, before Pub/Gradle resolution. */
public final class VerifyGradleBootstrap {
    public static void main(String[] args) throws NoSuchAlgorithmException {
        if (args.length != 2 || !args[0].matches("[a-fA-F0-9]{64}")) {
            System.err.println("Expected publisher SHA-256 and bootstrap JAR.");
            System.exit(2);
            return;
        }
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(Path.of(args[1]))) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        } catch (IOException unavailable) {
            System.err.println("Cannot read Gradle bootstrap JAR.");
            System.exit(1);
            return;
        }
        if (!MessageDigest.isEqual(digest.digest(), HexFormat.of().parseHex(args[0]))) {
            System.err.println("Gradle bootstrap differs from publisher SHA-256.");
            System.exit(1);
            return;
        }
        System.out.println("Gradle bootstrap publisher SHA-256 matches.");
    }
}
