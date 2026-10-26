import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: probe wrapper.jar java-executable');
    exitCode = 2;
    return;
  }
  final fixture = await Directory.systemTemp.createTemp(
    'vitalis_wrapper_timeout_',
  );
  final fixtureCanonical = await fixture.resolveSymbolicLinks();
  final temporaryCanonical = await Directory.systemTemp.resolveSymbolicLinks();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  var disconnects = 0;
  final subscription = server.listen((request) async {
    requests++;
    request.response.statusCode = HttpStatus.ok;
    request.response.contentLength = 1024;
    try {
      await request.response.flush();
      // Deliberately withhold the body until the client's read deadline.
    } on HttpException {
      disconnects++;
    }
  });
  Process? process;
  var processEnded = false;
  try {
    final wrapper = File('${fixture.path}/gradle/wrapper/gradle-wrapper.jar');
    await wrapper.parent.create(recursive: true);
    await File(arguments[0]).copy(wrapper.path);
    await File(
      '${wrapper.parent.path}/gradle-wrapper.properties',
    ).writeAsString(
      'distributionUrl=http\\://127.0.0.1:${server.port}/gradle-timeout-fixture.zip\n'
      'distributionSha256Sum=${'0' * 64}\n'
      'networkTimeout=250\n',
      flush: true,
    );
    final clock = Stopwatch()..start();
    process = await Process.start(
      arguments[1],
      [
        '-cp',
        wrapper.path,
        'org.gradle.wrapper.GradleWrapperMain',
        '--version',
      ],
      workingDirectory: fixture.path,
      environment: {'GRADLE_USER_HOME': '${fixture.path}/cache'},
    );
    final output = utf8.decoder.bind(process.stdout).join();
    final error = utf8.decoder.bind(process.stderr).join();
    var watchdogExpired = false;
    int result;
    try {
      result = await process.exitCode.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      watchdogExpired = true;
      process.kill();
      result = await process.exitCode;
    }
    processEnded = true;
    clock.stop();
    final diagnostics = '${await output}\n${await error}';
    final nativeTimeout =
        diagnostics.contains('timed out') ||
        diagnostics.contains('SocketTimeoutException');
    stdout.writeln(
      'requests=$requests watchdogExpired=$watchdogExpired '
      'exit=$result nativeTimeout=$nativeTimeout elapsedMs=${clock.elapsedMilliseconds}',
    );
    if (watchdogExpired || requests == 0 || result == 0 || !nativeTimeout) {
      stderr.writeln(diagnostics);
      exitCode = 1;
    }
  } finally {
    if (!processEnded && process != null) {
      process.kill();
      await process.exitCode;
    }
    await server.close(force: true);
    await subscription.cancel();
    if (!fixtureCanonical.toLowerCase().startsWith(
          '${temporaryCanonical.toLowerCase()}${Platform.pathSeparator}',
        ) ||
        !fixture.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last
            .startsWith('vitalis_wrapper_timeout_')) {
      throw StateError('Refusing cleanup outside owned temporary fixture');
    }
    await fixture.delete(recursive: true);
    stdout.writeln('Owned fixture cleaned; disconnects=$disconnects');
  }
}
