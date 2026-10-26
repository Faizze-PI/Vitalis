import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Kill only the wrapper created by this test, using the actual owner PID in
/// its isolated lease. Keep its child's streams until termination is observed.
Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('vitalis forced owner ');
  final tool = await Directory('${temp.path}/tool').create();
  final script = await File.fromUri(
    Platform.script.resolve('generation_lock.dart'),
  ).copy('${tool.path}/generation_lock.dart');
  final child = File('${tool.path}/child.dart');
  await child.writeAsString('''
import 'dart:io';
Future<void> main() async {
  stdout.writeln('ready');
  await stdin.drain<void>();
}
''');
  Process? owner;
  StreamIterator<String>? output;
  try {
    owner = await Process.start(Platform.resolvedExecutable, [
      script.path,
      '--',
      Platform.resolvedExecutable,
      child.path,
    ]);
    output = StreamIterator(
      owner.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    if (!await output.moveNext().timeout(const Duration(seconds: 30)) ||
        output.current != 'ready') {
      throw StateError('Disposable child failed to start.');
    }
    final lock = File('${temp.path}/.gate-cache/generation.lock');
    final metadata = jsonDecode(await lock.readAsString()) as Map;
    final ownerPid = metadata['pid'] as int;
    if (ownerPid == pid || !Process.killPid(ownerPid, ProcessSignal.sigkill)) {
      throw StateError('Could not terminate the disposable owner.');
    }
    final result = await owner.exitCode.timeout(const Duration(seconds: 30));
    if (result == 0) throw StateError('Forced owner reported success.');
    // The child survives its owner while the test keeps stdin open. A fresh
    // invocation must not enter the checkout in this dangerous interval.
    final competitor = await Process.run(Platform.resolvedExecutable, [
      script.path,
      '--',
      Platform.resolvedExecutable,
      child.path,
    ]);
    if (competitor.exitCode != 2 || !await lock.exists()) {
      throw StateError('Killed owner allowed a competing invocation.');
    }
    await owner.stdin.close();
    if (await output.moveNext().timeout(const Duration(seconds: 30))) {
      throw StateError('Unexpected child output after termination.');
    }
    await output.cancel();
    output = null;
    owner = null;
    stdout.writeln(
      'PASS: forced owner termination retains lease; competing '
      'invocation rejected; disposable child streams closed before cleanup.',
    );
  } finally {
    if (owner != null) {
      await owner.stdin.close();
      await owner.exitCode.timeout(const Duration(seconds: 30));
    }
    await output?.cancel();
    await temp.delete(recursive: true);
  }
}
