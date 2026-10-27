import 'dart:convert';
import 'dart:io';

/// Simulates a clean checkout followed by Flutter's LF-only regeneration.
/// Generated files remain tracked; real content changes must still be dirty.
void main() {
  final sourceRoot = Directory.current;
  final temporary = Directory.systemTemp.createTempSync('vitalis-eol-');
  final generated = [
    'windows/flutter/generated_plugin_registrant.cc',
    'windows/flutter/generated_plugin_registrant.h',
    'windows/flutter/generated_plugins.cmake',
  ];
  String git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: temporary.path,
    );
    if (result.exitCode != 0) {
      throw StateError('Git fixture failed: ${result.stderr}');
    }
    return '${result.stdout}';
  }

  try {
    git(['init', '--quiet']);
    git(['config', 'core.autocrlf', 'true']);
    git(['config', 'core.safecrlf', 'false']);
    File(
      '${sourceRoot.path}/.gitattributes',
    ).copySync('${temporary.path}/.gitattributes');
    for (final name in generated) {
      final file = File('${temporary.path}/$name');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('// generated fixture\n', encoding: utf8);
    }
    git(['add', '.']);
    git([
      '-c',
      'user.name=VITALIS fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '--quiet',
      '-m',
      'fixture',
    ]);
    for (final name in generated) {
      File('${temporary.path}/$name').deleteSync();
    }
    git(['checkout-index', '--all', '--force']);
    for (final name in generated) {
      final file = File('${temporary.path}/$name');
      if (file.readAsBytesSync().contains(13)) {
        throw StateError('Generated checkout is not LF-stable: $name');
      }
      file.writeAsStringSync('// generated fixture\n', encoding: utf8);
    }
    if (git(['status', '--porcelain']).trim().isNotEmpty) {
      throw StateError('LF-only regeneration dirtied the checkout');
    }
    File(
      '${temporary.path}/${generated.first}',
    ).writeAsStringSync('// actual changed content\n');
    if (!git(['status', '--porcelain']).contains(generated.first)) {
      throw StateError('Real generated content drift was hidden');
    }
    stdout.writeln(
      'Windows generated-file EOL policy: clean regeneration; real drift detected.',
    );
  } finally {
    final canonical = temporary.resolveSymbolicLinksSync();
    final bound =
        '${Directory.systemTemp.resolveSymbolicLinksSync()}${Platform.pathSeparator}vitalis-eol-';
    if (!canonical.toLowerCase().startsWith(bound.toLowerCase())) {
      throw StateError('Fixture cleanup escaped the owned temporary directory');
    }
    temporary.deleteSync(recursive: true);
  }
}
