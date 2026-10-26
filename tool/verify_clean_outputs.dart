import 'dart:io';

// HC-060: Positive postconditions for generated roots removed by Flutter clean.
List<String> remainingCleanOutputs(Directory root) => [
  for (final name in [
    'build',
    '.dart_tool',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
  ])
    if (FileSystemEntity.typeSync('${root.path}/$name', followLinks: false) !=
        FileSystemEntityType.notFound)
      name,
];

void main(List<String> arguments) {
  final root = arguments.isEmpty
      ? File.fromUri(Platform.script).parent.parent
      : Directory(arguments.single);
  final remaining = remainingCleanOutputs(root);
  if (remaining.isNotEmpty) {
    stderr.writeln(
      'Cleanup incomplete; generated outputs remain: ${remaining.join(', ')}',
    );
    exitCode = 1;
  }
}
