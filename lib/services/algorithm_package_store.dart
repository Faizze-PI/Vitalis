import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'algorithm_package_zip.dart';
import 'package:crypto/crypto.dart';
import '../models/custom_task_spec.dart';
import 'local_file_workspace.dart';
import 'package:path_provider/path_provider.dart';
import 'model_storage_preflight.dart';

final class AlgorithmPackageError implements Exception {
  const AlgorithmPackageError(this.message);
  final String message;
  @override
  String toString() => message;
}

final class AlgorithmPackage {
  const AlgorithmPackage(
    this.id,
    this.spec,
    this.description,
    this.packageSha256,
  );
  final String id, description, packageSha256;
  final CustomTaskSpec spec;
}

/// Each ready directory is published by a single atomic rename after validation.
class AlgorithmPackageStore {
  static AlgorithmPackageStore? _application;
  factory AlgorithmPackageStore.application() =>
      _application ??= AlgorithmPackageStore(
        root: () async => Directory(
          '${(await getApplicationSupportDirectory()).path}/algorithm_packages',
        ),
        availableBytes: () async =>
            await queryAllocatableModelStorage() ??
            (throw const AlgorithmPackageError(
              'Available storage is unknown.',
            )),
      );
  AlgorithmPackageStore({required this.root, required this.availableBytes});
  final Future<Directory> Function() root;
  final Future<int> Function() availableBytes;
  bool _installing = false;
  final _readers = <String, int>{};
  final _removing = <String>{};
  static final _id = RegExp(r'^[a-f0-9]{32}$');
  Future<Directory> _root() async {
    final directory = (await root()).absolute;
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link)
      throw const AlgorithmPackageError('Package storage is unavailable.');
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _owned(String id) async {
    if (!_id.hasMatch(id))
      throw const AlgorithmPackageError('Invalid package identity.');
    final d = Directory('${(await _root()).path}/$id');
    if (await FileSystemEntity.type(d.path, followLinks: false) !=
        FileSystemEntityType.directory)
      throw const AlgorithmPackageError('Algorithm package is unavailable.');
    return d;
  }

  Future<List<AlgorithmPackage>> list() async {
    final result = <AlgorithmPackage>[];
    await for (final entry in (await _root()).list(followLinks: false)) {
      final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!_id.hasMatch(id)) continue;
      final d = await _owned(id);
      final metadata = File('${d.path}/ready.json');
      if (await FileSystemEntity.type(metadata.path, followLinks: false) !=
          FileSystemEntityType.file)
        throw const AlgorithmPackageError(
          'Package description is unavailable.',
        );
      if (await metadata.length() > InputWorkspacePolicy.metadataBytes)
        throw const AlgorithmPackageError('Package description is too large.');
      final m =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      if (m['id'] != id ||
          m['maxInputElements'] is! int ||
          m['task'] is! Map<String, dynamic> ||
          m['packageSha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(m['packageSha256']))
        throw const AlgorithmPackageError('Package description is invalid.');
      final model = File('${d.path}/model.blob');
      if (await FileSystemEntity.type(model.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await model.length() != m['modelBytes'])
        throw const AlgorithmPackageError(
          'Package model is missing or changed.',
        );
      result.add(
        AlgorithmPackage(
          id,
          CustomTaskSpec.parse(
            m['task'],
            maxInputElements: m['maxInputElements'],
          ),
          m['task']['description'] is String ? m['task']['description'] : '',
          m['packageSha256'],
        ),
      );
    }
    return result;
  }

  Future<T> withModel<T>(String id, Future<T> Function(File) action) async {
    final d = await _owned(id);
    if (_removing.contains(id))
      throw const AlgorithmPackageError('This package is being removed.');
    _readers[id] = (_readers[id] ?? 0) + 1;
    try {
      final model = File('${d.path}/model.blob');
      if (await FileSystemEntity.type(model.path, followLinks: false) !=
          FileSystemEntityType.file)
        throw const AlgorithmPackageError(
          'Package model is unavailable or is not an ordinary file.',
        );
      return await action(model);
    } finally {
      final n = _readers[id]! - 1;
      if (n == 0) {
        _readers.remove(id);
      } else {
        _readers[id] = n;
      }
    }
  }

  Future<void> remove(String id) async {
    if ((_readers[id] ?? 0) > 0 || !_removing.add(id))
      throw const AlgorithmPackageError(
        'This algorithm is in use. Stop it before removing the package.',
      );
    try {
      final d = await _owned(id);
      // _owned accepts only a validated identity under the controlled root.
      await d.delete(recursive: true);
    } finally {
      _removing.remove(id);
    }
  }

  Future<AlgorithmPackage> install(
    File source, {
    required int maxModelBytes,
    required int maxInputElements,
  }) async {
    if (_installing)
      throw const AlgorithmPackageError(
        'Another algorithm package is being imported.',
      );
    _installing = true;
    Directory? staging;
    try {
      if (maxModelBytes <= 0 || maxInputElements <= 0)
        throw const AlgorithmPackageError(
          'Device task limits are unavailable.',
        );
      final digest = (await sha256.bind(source.openRead()).first).toString();
      for (final existing in await list()) {
        if (existing.packageSha256 == digest) return existing;
      }
      final directory = await _root();
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(); // hardcode: HC-082
      final target = Directory('${directory.path}/$id');
      final partial = Directory('${directory.path}/$id.part');
      if (await target.exists() || await partial.exists())
        throw const AlgorithmPackageError(
          'Package identity collision. Retry import.',
        );
      await partial.create();
      staging = partial;
      await extractAlgorithmPackage(
        source.path,
        partial.path,
        maxModelBytes,
        await availableBytes(),
      );
      final task =
          jsonDecode(await File('${partial.path}/task.json').readAsString())
              as Map<String, dynamic>;
      final spec = CustomTaskSpec.parse(
        task,
        maxInputElements: maxInputElements,
      );
      final model = File('${partial.path}/model.blob');
      if ((await sha256.bind(model.openRead()).first).toString() !=
          spec.modelSha256)
        throw const AlgorithmPackageError(
          'The model hash does not match its task description.',
        );
      await File('${partial.path}/ready.json').writeAsString(
        jsonEncode({
          'id': id,
          'task': task,
          'modelBytes': await model.length(),
          'packageSha256': digest,
          'maxInputElements': maxInputElements,
        }),
        flush: true,
      );
      if (await File('${partial.path}/ready.json').length() >
          InputWorkspacePolicy.metadataBytes)
        throw const AlgorithmPackageError('Package metadata is too large.');
      await partial.rename(target.path);
      staging = null;
      return AlgorithmPackage(
        id,
        spec,
        task['description'] is String ? task['description'] : '',
        digest,
      );
    } on AlgorithmPackageError {
      rethrow;
    } catch (_) {
      throw const AlgorithmPackageError(
        'Invalid algorithm package. Include task.json and its single ONNX model in a ZIP.',
      );
    } finally {
      try {
        if (staging != null && await staging.exists())
          await staging.delete(recursive: true);
      } finally {
        _installing = false;
      }
    }
  }
}
