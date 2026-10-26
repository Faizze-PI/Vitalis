import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (!Platform.isWindows || arguments.length != 3) {
    throw ArgumentError(
      'Windows probe requires wrapper, JDK and fixture parent',
    );
  }
  final parent = Directory(arguments[2]);
  final parentPath = await parent.resolveSymbolicLinks();
  final fixture = await Directory(parentPath).createTemp('vitalis socket ');
  final fixturePath = await fixture.resolveSymbolicLinks();
  if (!fixturePath.startsWith('$parentPath${Platform.pathSeparator}')) {
    throw StateError('Fixture escaped its owned parent');
  }
  Future<void> run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    if (result.exitCode != 0) {
      throw StateError('${result.stdout}\n${result.stderr}');
    }
  }

  try {
    final wrapper = File('$fixturePath/android/gradlew.bat');
    await wrapper.parent.create(recursive: true);
    await File(arguments[0]).copy(wrapper.path);
    final source = File('$fixturePath/GradleWrapperMain.java');
    await source.writeAsString(r'''
package org.gradle.wrapper;
import java.nio.channels.Selector;
import java.nio.file.Files;
import java.nio.file.Path;
import java.lang.management.ManagementFactory;
public class GradleWrapperMain {
  public static void main(String[] args) throws Exception {
    String socketDirectory = System.getProperty("jdk.net.unixdomain.tmpdir");
    if (socketDirectory == null) throw new AssertionError("Scoped socket directory missing");
    if (!Files.isSameFile(Path.of(socketDirectory), Path.of(args[0]))) throw new AssertionError("Wrong scoped directory");
    if (!Boolean.getBoolean("fixture.preserved")) throw new AssertionError("Inherited JVM options lost");
    if (ManagementFactory.getRuntimeMXBean().getInputArguments().stream().anyMatch(x -> x.startsWith("--patch-module"))) throw new AssertionError("Core JDK was patched");
    try (Selector selector = Selector.open()) { selector.wakeup().selectNow(); }
    if (args.length == 1) {
      Process child = new ProcessBuilder(Path.of(System.getProperty("java.home"), "bin", "java.exe").toString(), "-cp", System.getProperty("java.class.path"), "org.gradle.wrapper.GradleWrapperMain", args[0], "child").inheritIO().start();
      if (child.waitFor() != 0) throw new AssertionError("Child JVM selector failed");
    }
    System.out.println("Unpatched selector and inherited options passed");
  }
}
''');
    final classes = Directory('$fixturePath/classes');
    await classes.create();
    await run('${arguments[1]}/bin/javac.exe', [
      '-d',
      classes.path,
      source.path,
    ]);
    final jar = File('$fixturePath/android/gradle/wrapper/gradle-wrapper.jar');
    await jar.parent.create(recursive: true);
    await run('${arguments[1]}/bin/jar.exe', [
      '--create',
      '--file',
      jar.path,
      '-C',
      classes.path,
      '.',
    ]);
    final invoke = File('$fixturePath/invoke.ps1');
    await invoke.writeAsString(r'''
param([string]$Wrapper, [string]$SocketDirectory)
& $Wrapper $SocketDirectory
exit $LASTEXITCODE
''');
    final result = await Process.run(
      'pwsh.exe',
      [
        '-NoProfile',
        '-File',
        invoke.path,
        wrapper.path,
        '$fixturePath/.gate-cache/java-sockets',
      ],
      environment: {
        'VITALIS_JAVA_HOME': arguments[1],
        'JAVA_HOME': arguments[1],
        'JAVA_TOOL_OPTIONS': '-Dfixture.preserved=true',
      },
    );
    if (result.exitCode != 0) {
      throw StateError('${result.stdout}\n${result.stderr}');
    }
    stdout.writeln(
      'Windows wrapper: spaced paths, unpatched parent/child selectors and inherited options pass',
    );
  } finally {
    await fixture.delete(recursive: true);
  }
}
