/// Identity of an immutable app-owned file; never a user-supplied filesystem path.
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
