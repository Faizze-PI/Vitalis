import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/model_library_policy.dart';

abstract final class InputWorkspacePolicy {
  static const metadataBytes = 64 * 1024; // hardcode: HC-077
  static const previewBytes = 64 * 1024; // hardcode: HC-077
  static const nameScalars = 256; // hardcode: HC-077
}

final class WorkspaceImportException implements Exception {
  const WorkspaceImportException(this.code);
  final String code;
  @override
  String toString() => 'File operation failed ($code)';
}

final class WorkspaceFile {
  const WorkspaceFile({
    required this.id,
    required this.name,
    required this.bytes,
    required this.sha256,
  });
  final String id, name, sha256;
  final int bytes;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'bytes': bytes,
    'sha256': sha256,
  };
}

/// Immutable app-owned copies. Original picker files are never changed.
/// Metadata is committed last; interrupted copies cannot become usable inputs.
abstract interface class InputWorkspaceStore {
  Future<List<WorkspaceFile>> list();
  Future<WorkspaceFile> import({
    required String name,
    required int expectedBytes,
    required Stream<List<int>> source,
  });
  Future<T> withFile<T>(String id, Future<T> Function(File) action);
  Future<void> remove(String id);
}

final class LocalFileWorkspace implements InputWorkspaceStore {
  LocalFileWorkspace({
    required this.root,
    required this.availableBytes,
    this.nextIdentity,
  });
  final Future<Directory> Function() root;
  final Future<int> Function() availableBytes;
  final String Function()? nextIdentity;
  final _random = Random.secure();
  bool _importing = false;
  bool cleanupPending = false;
  final _readers = <String, int>{};
  final _removing = <String>{};

  static final _identity = RegExp(r'^[a-f0-9]{32}$');
  void _checkId(String id) {
    if (!_identity.hasMatch(id)) throw ArgumentError('Invalid input identity');
  }

  Future<Directory> _directory() async {
    final directory = await root();
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const WorkspaceImportException('workspace_link');
    }
    await directory.create(recursive: true);
    return directory;
  }

  Future<WorkspaceFile> import({
    required String name,
    required int expectedBytes,
    required Stream<List<int>> source,
  }) async {
    if (_importing) throw const WorkspaceImportException('import_busy');
    _importing = true;
    File? partial, blob, metadataPart;
    var committed = false;
    var ownsStaging = false;
    try {
      if (expectedBytes < 0)
        throw const WorkspaceImportException('invalid_size');
      final available = await availableBytes();
      if (available <
          (expectedBytes * ModelLibraryPolicy.downloadStorageHeadroom).ceil()) {
        throw const WorkspaceImportException('insufficient_storage');
      }
      final directory = await _directory();
      final id =
          nextIdentity?.call() ??
          List.generate(
            ModelLibraryPolicy.downloadJobEntropyBytes,
            (_) => _random.nextInt(256),
          ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      _checkId(id);
      blob = File('${directory.path}/$id.blob');
      partial = File('${directory.path}/$id.part');
      metadataPart = File('${directory.path}/$id.json.part');
      final metadata = File('${directory.path}/$id.json');
      if (await blob.exists() ||
          await partial.exists() ||
          await metadata.exists())
        throw const WorkspaceImportException('identity_collision');
      ownsStaging = true;
      var received = 0;
      final writer = await partial.open(mode: FileMode.write);
      try {
        await for (final chunk in source) {
          if (chunk.length > expectedBytes - received)
            throw const WorkspaceImportException('size_mismatch');
          await writer.writeFrom(chunk);
          received += chunk.length;
        }
        if (received != expectedBytes)
          throw const WorkspaceImportException('size_mismatch');
        await writer.flush();
      } finally {
        await writer.close();
      }
      final digest = (await sha256.bind(partial.openRead()).first).toString();
      final basename = name
          .replaceAll('\\', '/')
          .split('/')
          .last
          .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
          .trim();
      final item = WorkspaceFile(
        id: id,
        name: String.fromCharCodes(
          (basename.isEmpty ? 'File' : basename).runes.take(
            InputWorkspacePolicy.nameScalars,
          ),
        ),
        bytes: received,
        sha256: digest,
      );
      await partial.rename(blob.path);
      await metadataPart.writeAsString(jsonEncode(item.toJson()), flush: true);
      await metadataPart.rename(metadata.path);
      committed = true;
      return item;
    } on WorkspaceImportException {
      rethrow;
    } catch (_) {
      throw const WorkspaceImportException('copy_failed');
    } finally {
      if (!committed && ownsStaging) {
        for (final file in [partial, metadataPart, blob].whereType<File>()) {
          try {
            if (await file.exists()) await file.delete();
          } on FileSystemException {
            // Uncommitted files remain invisible; never touch another input.
            cleanupPending = true;
          }
        }
      }
      _importing = false;
    }
  }

  Future<List<WorkspaceFile>> list() async {
    final directory = await _directory();
    final result = <WorkspaceFile>[];
    await for (final entry in directory.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - '.json'.length);
      if (!_identity.hasMatch(id)) continue;
      try {
        if (entry is! File ||
            await entry.length() > InputWorkspacePolicy.metadataBytes)
          throw const FormatException();
        final m =
            jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        if (m['id'] != id ||
            m['name'] is! String ||
            m['bytes'] is! int ||
            (m['bytes'] as int) < 0 ||
            m['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(m['sha256'] as String))
          throw const FormatException();
        final item = WorkspaceFile(
          id: id,
          name: m['name'] as String,
          bytes: m['bytes'] as int,
          sha256: m['sha256'] as String,
        );
        if (await (await file(id)).length() != item.bytes)
          throw const FormatException();
        result.add(item);
      } catch (_) {
        throw const WorkspaceImportException('workspace_record_invalid');
      }
    }
    return result;
  }

  Future<File> file(String id) async {
    _checkId(id);
    final directory = await _directory();
    final path = '${directory.path}/$id.blob';
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file)
      throw const WorkspaceImportException('input_missing');
    return File(path);
  }

  Future<T> withFile<T>(String id, Future<T> Function(File) action) async {
    _checkId(id);
    if (_removing.contains(id))
      throw const WorkspaceImportException('input_in_use');
    _readers[id] = (_readers[id] ?? 0) + 1;
    try {
      return await action(await file(id));
    } finally {
      final remaining = _readers[id]! - 1;
      if (remaining == 0) {
        _readers.remove(id);
      } else {
        _readers[id] = remaining;
      }
    }
  }

  Future<void> remove(String id) async {
    _checkId(id);
    if ((_readers[id] ?? 0) > 0 || !_removing.add(id))
      throw const WorkspaceImportException('input_in_use');
    try {
      final directory = await _directory();
      final metadata = File('${directory.path}/$id.json');
      if (!await metadata.exists())
        throw const WorkspaceImportException('input_missing');
      final data = await file(id);
      final deleting = await metadata.rename(
        '${directory.path}/$id.json.deleting',
      );
      try {
        await data.delete();
      } on FileSystemException {
        await deleting.rename(metadata.path);
        rethrow;
      }
      await deleting.delete();
    } finally {
      _removing.remove(id);
    }
  }
}
