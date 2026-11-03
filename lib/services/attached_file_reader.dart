import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../constants/app_constants.dart';
import '../models/file_context.dart';
import 'local_file_workspace.dart';

final class FileAttachmentReadError implements Exception {
  const FileAttachmentReadError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Text is never truncated before the real tokenizer sees it. Binary decoders
/// must explicitly provide another adapter rather than pretending to be UTF-8.
class AttachedFileReader {
  static const textExtensions = {
    'txt',
    'md',
    'csv',
    'json',
    'jsonl',
    'log',
  }; // HC-079
  static bool supportsName(String name) =>
      textExtensions.contains(name.split('.').last.toLowerCase());
  AttachedFileReader({
    InputWorkspaceStore? workspace,
    this.maxBytes = AppConstants.maxStoredTextBytes,
  }) : workspace = workspace ?? LocalFileWorkspace.application();
  final InputWorkspaceStore workspace;
  final int
  maxBytes; // HC-079: bounded total extraction; original copies remain intact.
  Future<List<FileContext>> read(List<WorkspaceFile> files) async {
    var remaining = maxBytes;
    final result = <FileContext>[];
    for (final file in files) {
      if (!supportsName(file.name)) {
        throw FileAttachmentReadError(
          '${file.name} needs a compatible decoder or vision backend. Remove it from this text chat or use Files and algorithms.',
        );
      }
      if (file.bytes < 0 || file.bytes > remaining)
        throw const FileAttachmentReadError(
          'Attached text exceeds the 1 MiB processing safety budget. Remove a file or use a smaller input; stored originals are unchanged.',
        );
      final bytes = await workspace.withFile(file.id, (source) async {
        final data = <int>[];
        await for (final chunk in source.openRead()) {
          if (chunk.length > file.bytes - data.length)
            throw const FileAttachmentReadError(
              'An attached file changed. Re-import it before continuing.',
            );
          data.addAll(chunk);
        }
        return data;
      });
      if (bytes.length != file.bytes ||
          sha256.convert(bytes).toString() != file.sha256)
        throw const FileAttachmentReadError(
          'An attached file changed. Re-import it before continuing.',
        );
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw FileAttachmentReadError(
          '${file.name} is not UTF-8 text. Use a compatible decoder instead.',
        );
      }
      remaining -= bytes.length;
      result.add(FileContext(name: file.name, text: text));
    }
    return result;
  }
}
