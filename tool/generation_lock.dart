import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A fail-closed checkout lease. Abnormal process termination leaves the file
/// behind; only a human-verified recovery may remove it after checking children.
class GenerationLock {
  GenerationLock(this.file);
  final File file;
  String? _ownedToken;

  Future<String> acquire() async {
    await file.parent.create(recursive: true);
    await file.create(exclusive: true);
    final token = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    _ownedToken = token;
    await file.writeAsString(
      jsonEncode({'pid': pid, 'token': token}),
      flush: true,
    );
    return token;
  }

  Future<bool> recognizes(String token) async {
    try {
      final data = jsonDecode(await file.readAsString());
      return token.isNotEmpty && data is Map && data['token'] == token;
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
  }

  Future<void> release() async {
    final token = _ownedToken;
    if (token == null || !await recognizes(token)) {
      throw StateError('Checkout lock ownership cannot be confirmed.');
    }
    await file.delete();
    _ownedToken = null;
  }
}

Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent;
  final lease = GenerationLock(
    File('${root.path}/.gate-cache/generation.lock'),
  );
  final inherited = Platform.environment['VITALIS_GENERATION_TOKEN'];
  if (args.length == 1 && args.single == '--verify') {
    if (inherited == null || !await lease.recognizes(inherited)) {
      stderr.writeln('Invalid checkout generation ownership.');
      exitCode = 2;
    }
    return;
  }
  if (args.length < 2 || args.first != '--') {
    stderr.writeln('Usage: generation_lock.dart -- command [arguments]');
    exitCode = 2;
    return;
  }
  if (inherited != null) {
    stderr.writeln('Nested launchers must verify the inherited lease.');
    exitCode = 2;
    return;
  }
  String token;
  try {
    token = await lease.acquire();
  } on FileSystemException {
    stderr.writeln(
      'Checkout is locked. Do not remove the lock until its owner '
      'and build children are confirmed stopped.',
    );
    exitCode = 2;
    return;
  }
  // If the wrapper is killed, no finally handler runs and the checkout stays
  // blocked. A normal command failure releases only after the child exits.
  try {
    final process = await Process.start(
      args[1],
      args.skip(2).toList(),
      mode: ProcessStartMode.inheritStdio,
      environment: {'VITALIS_GENERATION_TOKEN': token},
    );
    exitCode = await process.exitCode;
  } finally {
    await lease.release();
  }
}
