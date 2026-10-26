import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class VerifyAndroidNativeInventoryTest {
    public static void main(String[] args) throws Exception {
        Path directory = Files.createTempDirectory("vitalis-native-inventory-");
        try {
            for (boolean bundle : new boolean[] {false, true}) {
                String prefix = bundle ? "base/lib/" : "lib/";
                Path valid = directory.resolve(bundle ? "valid.aab" : "valid.apk");
                List<String> libraries = List.of("libapp.so", "libflutter.so", "libllama.so",
                        "libggml.so", "libggml-base.so", "libggml-cpu.so");
                archive(valid, prefix, libraries, null);
                VerifyAndroidNativeInventory.verify(valid, bundle);
                Path wrongAbi = directory.resolve(bundle ? "wrong.aab" : "wrong.apk");
                archive(wrongAbi, prefix, libraries, prefix + "x86_64/libflutter.so");
                rejects(wrongAbi, bundle);
                Path missing = directory.resolve(bundle ? "missing.aab" : "missing.apk");
                archive(missing, prefix, libraries.subList(0, 5), null);
                rejects(missing, bundle);
                Path outside = directory.resolve(bundle ? "outside.aab" : "outside.apk");
                archive(outside, prefix, libraries, "assets/libhidden.so");
                rejects(outside, bundle);
                rejects(valid, !bundle);
                Path disguised = directory.resolve(bundle ? "disguised.aab" : "disguised.apk");
                try (var output = new ZipOutputStream(Files.newOutputStream(disguised))) {
                    for (String library : libraries) {
                        output.putNextEntry(new ZipEntry(prefix + "arm64-v8a/" + library));
                        byte[] header = elfHeader();
                        if (library.equals("libllama.so")) header[18] = 62; // x86-64 ELF, misleading directory.
                        output.write(header);
                        output.closeEntry();
                    }
                }
                rejects(disguised, bundle);
            }
            Path empty = directory.resolve("empty.apk");
            archive(empty, "lib/", List.of(), null);
            rejects(empty, false);
            String apk = directory.resolve("valid.apk").toString();
            String aab = directory.resolve("valid.aab").toString();
            cli(0, apk, aab);
            cli(1, directory.resolve("wrong.apk").toString(), aab);
            cli(1, apk, directory.resolve("wrong.aab").toString());
            cli(1, directory.resolve("absent.apk").toString(), aab);
            cli(2);
            cli(1, "--manifest", apk, "apk");
            for (boolean bundle : new boolean[] {false, true}) {
                Path manifest = directory.resolve(bundle ? "manifest.aab" : "manifest.apk");
                String name = (bundle ? "base/" : "")
                        + "assets/flutter_assets/NativeAssetsManifest.json";
                try (var output = new ZipOutputStream(Files.newOutputStream(manifest))) {
                    output.putNextEntry(new ZipEntry(name));
                    output.write("{}".getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    output.closeEntry();
                }
                cli(0, "--manifest", manifest.toString(), bundle ? "aab" : "apk");
                cli(1, "--manifest", manifest.toString(), bundle ? "apk" : "aab");
            }
            Path oversized = directory.resolve("oversized.apk");
            try (var output = new ZipOutputStream(Files.newOutputStream(oversized))) {
                output.putNextEntry(new ZipEntry("assets/flutter_assets/NativeAssetsManifest.json"));
                output.write(new byte[1024 * 1024 + 1]);
                output.closeEntry();
            }
            cli(1, "--manifest", oversized.toString(), "apk");
            System.out.println("Native inventory fixtures pass for APK and AAB: required libraries, ABI, layout and empty rejection");
        } finally {
            try (var files = Files.list(directory)) {
                for (Path file : files.toList()) Files.delete(file);
            }
            Files.delete(directory);
        }
    }

    private static void cli(int expected, String... arguments) throws Exception {
        var command = new java.util.ArrayList<String>(List.of(
                Path.of(System.getProperty("java.home"), "bin", "java").toString(),
                "-cp", System.getProperty("java.class.path"), "VerifyAndroidNativeInventory"));
        command.addAll(List.of(arguments));
        Process invocation = new ProcessBuilder(command).redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
        if (!invocation.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)) {
            invocation.destroyForcibly();
            if (!invocation.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)) {
                throw new AssertionError("Native inventory CLI termination unconfirmed");
            }
            throw new AssertionError("Native inventory CLI timed out");
        }
        if (invocation.exitValue() != expected) {
            throw new AssertionError("CLI exit expected " + expected + ", actual " + invocation.exitValue());
        }
    }

    private static void archive(Path path, String prefix, List<String> libraries, String extra) throws IOException {
        try (var output = new ZipOutputStream(Files.newOutputStream(path))) {
            for (String library : libraries) entry(output, prefix + "arm64-v8a/" + library);
            if (extra != null) entry(output, extra);
        }
    }

    private static void entry(ZipOutputStream output, String name) throws IOException {
        output.putNextEntry(new ZipEntry(name));
        output.write(elfHeader());
        output.closeEntry();
    }

    private static byte[] elfHeader() {
        byte[] bytes = new byte[64];
        bytes[0] = 127; bytes[1] = 'E'; bytes[2] = 'L'; bytes[3] = 'F';
        bytes[4] = 2; bytes[5] = 1; bytes[6] = 1;
        bytes[16] = 3; bytes[18] = (byte) 183; bytes[20] = 1; bytes[52] = 64;
        return bytes;
    }

    private static void rejects(Path archive, boolean bundle) throws IOException {
        try {
            VerifyAndroidNativeInventory.verify(archive, bundle);
        } catch (IOException expected) {
            return;
        }
        throw new AssertionError("Invalid native inventory accepted: " + archive.getFileName());
    }
}
