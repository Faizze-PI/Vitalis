import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Standalone process regression: run with the pinned Dart executable, without
/// Flutter/native generation (which is the resource being protected).
Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('vitalis lock process ');
  final tool = await Directory('${temp.path}/tool').create();
  final source = File.fromUri(Platform.script.resolve('generation_lock.dart'));
  final script = await source.copy('${tool.path}/generation_lock.dart');
  final child = File('${tool.path}/child.dart');
  await child.writeAsString('''
import 'dart:io';
import 'dart:convert';
Future<void> main(List<String> args) async {
  if (args.single == 'fail') { exitCode = 7; return; }
  stdout.writeln('ready');
  await stdin.transform(utf8.decoder).first;
}
''');
  final arguments = [
    script.path,
    '--',
    Platform.resolvedExecutable,
    child.path,
  ];
  Process? owner;
  try {
    final failed = await Process.run(Platform.resolvedExecutable, [
      ...arguments,
      'fail',
    ]);
    if (failed.exitCode != 7)
      throw StateError('Child failure code was lost: ${failed.stderr}');
    final lock = File('${temp.path}/.gate-cache/generation.lock');
    if (await lock.exists())
      throw StateError('Completed failed command retained lease');
    owner = await Process.start(Platform.resolvedExecutable, [
      ...arguments,
      'hold',
    ]);
    final ready = await owner.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 30));
    if (ready != 'ready') throw StateError('Owner child did not start');
    final competing = await Process.run(Platform.resolvedExecutable, [
      ...arguments,
      'fail',
    ]);
    if (competing.exitCode != 2)
      throw StateError('Competing command acquired checkout');
    final token =
        (jsonDecode(await lock.readAsString()) as Map)['token'] as String;
    final nested = await Process.run(
      Platform.resolvedExecutable,
      [script.path, '--verify'],
      environment: {'VITALIS_GENERATION_TOKEN': token},
    );
    if (nested.exitCode != 0) throw StateError('Nested lease rejected');
    owner.stdin.writeln('finish');
    await owner.stdin.close();
    if (await owner.exitCode != 0 || await lock.exists()) {
      throw StateError('Completed owner failed to release lease');
    }
    owner = null;
    // An interrupted owner's persistent file is intentionally NOT reclaimed.
    await lock.writeAsString('');
    final interrupted = await Process.run(Platform.resolvedExecutable, [
      ...arguments,
      'fail',
    ]);
    if (interrupted.exitCode != 2 || !await lock.exists()) {
      throw StateError('Interrupted lease was automatically stolen');
    }
    stdout.writeln(
      'PASS: child failure, contention, nested ownership, normal release, interrupted lease; paths contain spaces.',
    );
  } finally {
    if (owner != null) {
      owner.stdin.writeln('finish');
      await owner.stdin.close();
      await owner.exitCode;
    }
    await temp.delete(recursive: true);
  }
}
