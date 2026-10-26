import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final repository = File.fromUri(Platform.script).parent.parent;
  final scratch = await Directory.systemTemp.createTemp('vitalis-fault-modes-');
  final cases = [
    (name: 'normal', requested: false, product: false, profile: false),
    (name: 'explicit-test', requested: true, product: false, profile: false),
    (name: 'product', requested: true, product: true, profile: false),
    (name: 'profile', requested: true, product: false, profile: true),
  ];
  final results = <Map<String, Object>>[];
  try {
    for (final mode in cases) {
      final output = '${scratch.path}/${mode.name}.dill';
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        '--define=VITALIS_RUNTIME_FAULT_TESTS=${mode.requested}',
        '--define=dart.vm.product=${mode.product}',
        '--define=dart.vm.profile=${mode.profile}',
        '--output',
        output,
        'tool/runtime_fault_mode_probe.dart',
      ], workingDirectory: repository.path);
      if (compiled.exitCode != 0) {
        stderr.write(compiled.stdout);
        stderr.write(compiled.stderr);
        throw StateError('Fault-mode compilation failed: ${mode.name}');
      }
      final expected = mode.requested && !mode.product && !mode.profile;
      final executed = await Process.run(Platform.resolvedExecutable, [
        output,
        '$expected',
      ], workingDirectory: repository.path);
      if (executed.exitCode != 0) {
        stderr.write(executed.stdout);
        stderr.write(executed.stderr);
        throw StateError('Compiled fault-mode check failed: ${mode.name}');
      }
      results.add({
        'mode': mode.name,
        'enabled': expected,
        'exitCode': executed.exitCode,
      });
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
  } finally {
    // Unique test-owned kernels only; no repository or model paths are deleted.
    await scratch.delete(recursive: true);
  }
}
