import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late File launcher;
  late Map<String, String> environment;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('vitalis argument gate ');
    addTearDown(() => sandbox.delete(recursive: true));
    final tool = await Directory('${sandbox.path}/tool').create();
    final name = Platform.isWindows ? 'run_gate.ps1' : 'run_gate.sh';
    launcher = await File('tool/$name').copy('${tool.path}/$name');
    await File(
      'tool/toolchain_policy.json',
    ).copy('${tool.path}/toolchain_policy.json');
    // Observe the real launcher's arguments at the generation-lock boundary.
    await File('${tool.path}/generation_lock.dart').writeAsString('''
import 'dart:convert';
void main(List<String> arguments) => print(jsonEncode(arguments));
''');
    environment = {
      'VITALIS_FLUTTER_SDK':
          Platform.environment['VITALIS_FLUTTER_SDK'] ??
          Platform.environment['FLUTTER_ROOT']!,
      'VITALIS_GENERATION_TOKEN': '',
    };
  });

  const forwarded = [
    'build',
    'apk',
    '--debug',
    '--verbose',
    '--dart-define',
    'EXAMPLE=value with spaces',
  ];

  test(
    'launcher preserves build mode, verbosity and spaced arguments',
    () async {
      final result = await Process.run(Platform.isWindows ? 'pwsh' : 'sh', [
        if (Platform.isWindows) ...['-NoProfile', '-File'],
        launcher.path,
        ...forwarded,
      ], environment: environment);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final arguments = jsonDecode('${result.stdout}'.trim()) as List;
      expect(_forwardedArguments(arguments, forwarded.length), forwarded);
    },
  );

  if (Platform.isWindows) {
    const exactArguments = [
      'test',
      '--coverage',
      r'--coverage-path=D:\fixture output\coverage.lcov',
      '--coverage-package=vitalis_app|llm_llamacpp',
      '--dart-define=ENDPOINT=https://huggingface.co/model',
      r'--dart-define=LITERAL=$HOME;$(Write-Output unexpected)',
      '--dart-define=UNICODE=Hindi हिन्दी emoji 🧪',
      '',
      '''--dart-define=QUOTES=one"two'three''',
    ];
    for (final encodedEntry in [false, true]) {
      test(
        'complete native handoff preserves exact arguments encoded=$encodedEntry',
        () async {
          await _prepareFinalArgumentProbe(sandbox, launcher, environment);
          final quoted = exactArguments
              .map((value) => "'${value.replaceAll("'", "''")}'")
              .join(',');
          final result = await Process.run(
            'pwsh',
            encodedEntry
                ? [
                    '-NoProfile',
                    '-File',
                    launcher.path,
                    '-FlutterArguments',
                    'VITALIS_ARGS64_${base64.encode(utf8.encode(jsonEncode(exactArguments)))}',
                  ]
                : [
                    '-NoProfile',
                    '-Command',
                    "& '${launcher.path.replaceAll("'", "''")}' -FlutterArguments @($quoted)",
                  ],
            // The fixture owns its own lease, not the enclosing test launcher's.
            environment: {...Platform.environment, ...environment}
              ..remove('VITALIS_GENERATION_TOKEN'),
            includeParentEnvironment: false,
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          );
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
          expect(jsonDecode('${result.stdout}'.trim()), exactArguments);
          expect(
            File('${sandbox.path}/.gate-cache/generation.lock').existsSync(),
            isFalse,
          );
        },
      );
    }
    for (final invalid in [
      'null',
      '"PRIVATE_ARG_FIXTURE"',
      '["test",17]',
      '{"command":"test"}',
      'not json',
    ]) {
      test(
        'encoded transport rejects non-string-array input $invalid',
        () async {
          final result = await Process.run('pwsh', [
            '-NoProfile',
            '-File',
            launcher.path,
            '-FlutterArguments',
            'VITALIS_ARGS64_${base64.encode(utf8.encode(invalid))}',
          ], environment: environment);
          expect(result.exitCode, isNot(0));
          expect(
            '${result.stderr}',
            contains(
              'Encoded Flutter arguments must contain a JSON string array',
            ),
          );
          expect('${result.stderr}', isNot(contains('PRIVATE_ARG_FIXTURE')));
          expect(
            File('${sandbox.path}/.gate-cache/generation.lock').existsSync(),
            isFalse,
          );
        },
      );
    }
    test(
      'encoded transport rejects malformed Base64 and mixed arguments',
      () async {
        for (final wireArguments in [
          ['VITALIS_ARGS64_not-base64'],
          ['VITALIS_ARGS64_${base64.encode(utf8.encode('["test"]'))}', 'extra'],
        ]) {
          final result = await Process.run('pwsh', [
            '-NoProfile',
            '-File',
            launcher.path,
            '-FlutterArguments',
            ...wireArguments,
          ], environment: environment);
          expect(result.exitCode, isNot(0));
          expect(
            File('${sandbox.path}/.gate-cache/generation.lock').existsSync(),
            isFalse,
          );
        }
      },
    );
    test(
      'encoded transport rejects invalid UTF8 without replacing argument data',
      () async {
        final wire = base64.encode([
          0x5b,
          0x22,
          0x74,
          0x65,
          0xff,
          0x73,
          0x74,
          0x22,
          0x5d,
        ]);
        final result = await Process.run('pwsh', [
          '-NoProfile',
          '-File',
          launcher.path,
          '-FlutterArguments',
          'VITALIS_ARGS64_$wire',
        ], environment: environment);
        expect(result.exitCode, isNot(0));
        expect(
          '${result.stderr}',
          contains(
            'Encoded Flutter arguments must contain a JSON string array',
          ),
        );
        expect(
          File('${sandbox.path}/.gate-cache/generation.lock').existsSync(),
          isFalse,
        );
      },
    );
    test('rejects implicit tool flags before launching a child', () async {
      final result = await Process.run(
        'pwsh',
        ['-NoProfile', '-File', launcher.path, 'analyze'],
        environment: {...environment, 'FLUTTER_TOOL_ARGS': '--verbose'},
      );
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains('FLUTTER_TOOL_ARGS is unsupported'));
    });

    test(
      'final Flutter invocation preserves regex pipe as one argument',
      () async {
        // Stub preflight only: exercise the actual final Windows CLI boundary.
        // This sandbox owns no application build output or real generation lock.
        for (final name in [
          'generation_lock.dart',
          'verify_toolchain_policy.dart',
          'validate_flutter_version.dart',
          'verify_gate_environment.dart',
          'verify_flutter_selection.dart',
        ]) {
          await File(
            '${sandbox.path}/tool/$name',
          ).writeAsString('void main(List<String> arguments) {}');
        }
        final result = await Process.run(
          'pwsh',
          [
            '-NoProfile',
            '-File',
            launcher.path,
            'test',
            '--help',
            '--coverage-package=vitalis_app|llm_llamacpp',
          ],
          environment: {
            ...environment,
            'JAVA_HOME': Platform.environment['JAVA_HOME']!,
            'VITALIS_GENERATION_TOKEN': 'sandbox-preflight-only',
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('coverage-package'));
        expect('${result.stderr}', isNot(contains('is not recognized')));
      },
    );

    test(
      'PowerShell launcher also preserves its named argument array',
      () async {
        final quoted = forwarded.map(
          (value) => "'${value.replaceAll("'", "''")}'",
        );
        final result = await Process.run('pwsh', [
          '-NoProfile',
          '-Command',
          "& '${launcher.path.replaceAll("'", "''")}' "
              '-FlutterArguments @(${quoted.join(',')})',
        ], environment: environment);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final arguments = jsonDecode('${result.stdout}'.trim()) as List;
        expect(_forwardedArguments(arguments, forwarded.length), forwarded);
      },
    );
  }
}

List<dynamic> _forwardedArguments(List<dynamic> boundary, int ordinaryCount) {
  final encoded = boundary.indexOf('-FlutterArguments');
  if (encoded >= 0) {
    return jsonDecode(
          utf8.decode(
            base64.decode(
              (boundary[encoded + 1] as String).substring(
                'VITALIS_ARGS64_'.length,
              ),
            ),
          ),
        )
        as List;
  }
  return boundary.skip(boundary.length - ordinaryCount).toList();
}

Future<void> _prepareFinalArgumentProbe(
  Directory sandbox,
  File launcher,
  Map<String, String> environment,
) async {
  await File(
    'tool/generation_lock.dart',
  ).copy('${sandbox.path}/tool/generation_lock.dart');
  for (final name in [
    'verify_toolchain_policy.dart',
    'validate_flutter_version.dart',
    'verify_gate_environment.dart',
    'verify_flutter_selection.dart',
  ]) {
    await File(
      '${sandbox.path}/tool/$name',
    ).writeAsString('void main(List<String> arguments) {}');
  }
  final program = File('${sandbox.path}/argument_probe.dart');
  await program.writeAsString(
    "import 'dart:convert'; void main(List<String> args) => print(jsonEncode(args));",
  );
  final kernel = '${sandbox.path}/argument_probe.dill';
  final sdk = environment['VITALIS_FLUTTER_SDK']!;
  final compiled = await Process.run('$sdk/bin/cache/dart-sdk/bin/dart.exe', [
    'compile',
    'kernel',
    program.path,
    '-o',
    kernel,
  ]);
  expect(
    compiled.exitCode,
    0,
    reason: '${compiled.stdout}\n${compiled.stderr}',
  );
  final source = await launcher.readAsString();
  const original =
      r"$FlutterSnapshot = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'";
  expect(original.allMatches(source), hasLength(1));
  // Replace only the CLI payload, retaining both actual PowerShell/lock hops.
  await launcher.writeAsString(
    source.replaceFirst(
      original,
      "\$FlutterSnapshot = '${kernel.replaceAll("'", "''")}'",
    ),
  );
}
