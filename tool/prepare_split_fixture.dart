import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../lib/models/bundled_model_manifest.dart';

/// Fixture preparation only: never modifies the original immutable model and
/// never overwrites an existing output directory or deletes partial evidence.
Future<void> main(List<String> arguments) async {
  final options = parseSplitFixtureOptions(arguments);
  final repository = File.fromUri(Platform.script).parent.parent;
  final lockFile = File(
    '${repository.path}/third_party/llm_llamacpp/native/llama_cpp.lock.json',
  );
  final lock =
      jsonDecode(await lockFile.readAsString()) as Map<String, dynamic>;
  final model = File(options['--model']!);
  if (await model.length() != BundledModelManifest.byteSize ||
      await _digest(model) != BundledModelManifest.sha256) {
    throw StateError('Immutable source model identity mismatch');
  }
  final splitter = File(options['--splitter']!);
  final provenance =
      jsonDecode(await File(options['--provenance']!).readAsString()) as Map;
  final toolHash = await _digest(splitter);
  if (provenance['commit'] != lock['commit'] ||
      '${provenance['archiveSha256']}'.toLowerCase() != lock['archiveSha256'] ||
      '${provenance['sourceLockSha256']}'.toLowerCase() !=
          await _digest(lockFile) ||
      provenance['toolSha256'] != toolHash) {
    throw StateError('Split helper provenance mismatch');
  }
  final output = Directory(options['--output']!);
  if (await output.exists() || await File(output.path).exists()) {
    throw StateError('Split fixture output must be a new directory');
  }
  await output.create(recursive: true);
  final invocation = [
    '--split',
    '--split-max-size',
    options['--max-shard-size']!,
    model.absolute.path,
    '${output.absolute.path}/fixture',
  ];
  final result = await Process.run(splitter.absolute.path, invocation);
  await File(
    '${output.path}/split.stdout.txt',
  ).writeAsString('${result.stdout}', flush: true);
  await File(
    '${output.path}/split.stderr.txt',
  ).writeAsString('${result.stderr}', flush: true);
  if (result.exitCode != 0)
    throw StateError('Split helper failed (${result.exitCode})');
  if (await _digest(model) != BundledModelManifest.sha256) {
    throw StateError(
      'Immutable source model changed during fixture preparation',
    );
  }
  final files = await output
      .list(followLinks: false)
      .where((entry) => entry is File && entry.path.endsWith('.gguf'))
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  if (files.length < 2)
    throw StateError('Fixture must contain multiple shards');
  final artifacts = <Map<String, Object?>>[];
  for (final (index, file) in files.indexed) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(
      r'^fixture-(\d{5})-of-(\d{5})\.gguf$',
    ).firstMatch(name);
    if (match == null ||
        int.parse(match.group(1)!) != index + 1 ||
        int.parse(match.group(2)!) != files.length) {
      throw StateError('Split helper produced an incomplete shard set');
    }
    artifacts.add({
      'name': name,
      'byteSize': await file.length(),
      'sha256': await _digest(file),
      'shardIndex': index,
      'shardCount': files.length,
    });
  }
  final manifest = {
    'formatVersion': 1,
    'source': {
      'modelId': BundledModelManifest.id,
      'repository': BundledModelManifest.repository,
      'revision': BundledModelManifest.revision,
      'sha256': BundledModelManifest.sha256,
      'byteSize': BundledModelManifest.byteSize,
    },
    'native': {
      'commit': lock['commit'],
      'archiveSha256': lock['archiveSha256'],
      'sourceLockSha256': await _digest(lockFile),
      'toolSha256': toolHash,
    },
    'maxShardSize': options['--max-shard-size'],
    'hashAuthority': 'locallyDerivedFromVerifiedImmutableFixture',
    'files': artifacts,
  };
  final pending = File('${output.path}/manifest.json.part');
  await pending.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  final installed = await pending.rename('${output.path}/manifest.json');
  stdout.writeln(installed.absolute.path);
}

Map<String, String> parseSplitFixtureOptions(List<String> arguments) {
  const keys = {
    '--model',
    '--splitter',
    '--provenance',
    '--output',
    '--max-shard-size',
  };
  if (arguments.length != keys.length * 2)
    throw const FormatException('Missing split fixture options');
  final parsed = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    final key = arguments[i];
    final value = arguments[i + 1];
    if (!keys.contains(key) ||
        parsed.containsKey(key) ||
        value.isEmpty ||
        RegExp(r'[\x00-\x1f]').hasMatch(value)) {
      throw const FormatException('Invalid split fixture option');
    }
    parsed[key] = value;
  }
  if (!RegExp(r'^[1-9]\d*[MG]$').hasMatch(parsed['--max-shard-size']!)) {
    throw const FormatException('Split size must be a positive M/G value');
  }
  return Map.unmodifiable(parsed);
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
