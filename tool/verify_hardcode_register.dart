import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const _registerPath = 'docs/remediation/HARDCODE_DISPOSITION_REGISTER.csv';
const _allowedDispositions = {
  'REMOVE_HARMFUL',
  'CENTRALIZE_POLICY',
  'DEVICE_OR_MODEL_DERIVED',
  'USER_OVERRIDE',
  'PLATFORM_ADAPTER',
  'KEEP_SAFEGUARD',
};

void main() {
  final failures = verifyHardcodes();
  if (failures.isNotEmpty) {
    stderr.writeln('Hardcode register verification failed:');
    for (final failure in failures) {
      stderr.writeln(' - $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Hardcode register verification passed '
    '(${_registeredCount(_registerPath)} dispositions).',
  );
}

List<String> verifyHardcodes({
  String registerPath = _registerPath,
  Iterable<File>? dartTargets,
  Iterable<File>? javaTargets,
}) {
  final failures = <String>[];
  final ids = _readRegister(registerPath, failures);
  final targets =
      dartTargets ?? discoverDartHardcodeSources(Directory.current, failures);
  for (final file in targets) {
    if (!file.existsSync()) {
      failures.add('Required hardcode source is missing: ${file.path}');
      continue;
    }
    final content = file.readAsStringSync();
    final result = parseString(content: content, path: file.path);
    result.unit.accept(
      _BehavioralConstantVisitor(
        path: file.path,
        content: content,
        registeredIds: ids,
        failures: failures,
      ),
    );
  }
  final java =
      javaTargets?.toList() ??
      (dartTargets == null
          ? discoverJavaHardcodeSources(Directory.current, failures)
          : <File>[]);
  _verifyJavaConstants(java, ids, failures);
  return failures;
}

List<File> discoverJavaHardcodeSources(Directory root, List<String> failures) {
  final directory = Directory(
    '${root.path}/android/app/src/main/java/com/vitalis/vitalis_app',
  );
  if (!directory.existsSync()) {
    failures.add(
      'Required Java hardcode source root is missing: ${directory.path}',
    );
    return [];
  }
  final files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.java'))
      .toList();
  if (files.isEmpty) {
    failures.add(
      'Required Java hardcode source root is empty: ${directory.path}',
    );
  }
  return files;
}

void _verifyJavaConstants(
  List<File> files,
  Set<String> ids,
  List<String> failures,
) {
  if (files.isEmpty) return;
  if (files.any((file) => !file.existsSync())) {
    for (final file in files.where((file) => !file.existsSync())) {
      failures.add('Required Java hardcode source is missing: ${file.path}');
    }
    return;
  }
  final jdk = Platform.environment['JAVA_HOME'];
  if (jdk == null || jdk.isEmpty) {
    failures.add('JAVA_HOME must select a JDK for Java hardcode parsing');
    return;
  }
  final result =
      Process.runSync('$jdk/bin/java${Platform.isWindows ? '.exe' : ''}', [
        File('tool/JavaHardcodeScanner.java').absolute.path,
        ...files.map((file) => file.absolute.path),
      ]);
  if (result.exitCode != 0) {
    failures.add(
      'Java hardcode parser failed (${result.exitCode}): ${result.stderr}',
    );
    return;
  }
  for (final line in (result.stdout as String).split('\n')) {
    if (line.trim().isEmpty) continue;
    final columns = line.trimRight().split('\t');
    final index = columns.isEmpty ? null : int.tryParse(columns[0]);
    if (columns.length != 4 ||
        index == null ||
        index < 0 ||
        index >= files.length) {
      failures.add('Malformed Java hardcode parser output');
      continue;
    }
    final location = '${files[index].path}:${columns[1]} ${columns[2]}';
    if (columns[3] == '-') {
      failures.add('$location is an unclassified behavioral constant');
    } else if (!ids.contains(columns[3])) {
      failures.add('$location references unknown ${columns[3]}');
    }
  }
}

int _registeredCount(String registerPath) {
  final failures = <String>[];
  return _readRegister(registerPath, failures).length;
}

List<File> discoverDartHardcodeSources(Directory root, List<String> failures) {
  final sources = <File>[];
  for (final relative in ['lib', 'third_party/llm_llamacpp/lib']) {
    final directory = Directory('${root.path}/$relative');
    if (!directory.existsSync()) {
      failures.add(
        'Required hardcode source root is missing: ${directory.path}',
      );
      continue;
    }
    final maintained = _dartFiles(
      directory,
    ).where((file) => !_isExplicitlyExcluded(file.path)).toList();
    if (maintained.isEmpty) {
      failures.add('Required hardcode source root is empty: ${directory.path}');
    }
    sources.addAll(maintained);
  }
  final hook = File('${root.path}/third_party/llm_llamacpp/hook/build.dart');
  if (!hook.existsSync()) {
    failures.add('Required hardcode source is missing: ${hook.path}');
  } else {
    sources.add(hook);
  }
  return sources;
}

bool _isExplicitlyExcluded(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.endsWith('/constants/app_metrics.dart') ||
      normalized.endsWith('/constants/app_strings.dart') ||
      normalized.contains('/src/bindings/');
}

Set<String> _readRegister(String registerPath, List<String> failures) {
  final file = File(registerPath);
  if (!file.existsSync()) {
    failures.add('Missing $registerPath');
    return {};
  }
  final lines = file.readAsLinesSync();
  if (lines.isEmpty || !lines.first.startsWith('id,')) {
    failures.add('Hardcode register header is invalid');
    return {};
  }
  final ids = <String>{};
  for (final line in lines.skip(1).where((line) => line.trim().isNotEmpty)) {
    final columns = line.split(',');
    if (columns.length < 8) {
      failures.add('Malformed register row: $line');
      continue;
    }
    final id = columns[0];
    final disposition = columns[4];
    if (!RegExp(r'^HC-\d{3}$').hasMatch(id)) {
      failures.add('Invalid disposition ID: $id');
    } else if (!ids.add(id)) {
      failures.add('Duplicate disposition ID: $id');
    }
    if (!_allowedDispositions.contains(disposition)) {
      failures.add('$id has unknown disposition $disposition');
    }
    if (columns[5].trim().isEmpty || columns[6].trim().isEmpty) {
      failures.add('$id must name a replacement and verification');
    }
  }
  return ids;
}

Iterable<File> _dartFiles(Directory directory) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

class _BehavioralConstantVisitor extends RecursiveAstVisitor<void> {
  _BehavioralConstantVisitor({
    required this.path,
    required this.content,
    required this.registeredIds,
    required this.failures,
  });

  final String path;
  final String content;
  final Set<String> registeredIds;
  final List<String> failures;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final declaration = node.parent;
    if (declaration is! VariableDeclarationList || !declaration.isConst) {
      return super.visitVariableDeclaration(node);
    }
    if (!_isBehavioralLiteral(node.initializer)) {
      return super.visitVariableDeclaration(node);
    }
    final source = _declarationSource(declaration);
    final annotation = RegExp(r'hardcode:\s*(HC-\d{3})').firstMatch(source);
    final lineNumber = _lineNumber(node.offset);
    if (annotation == null) {
      failures.add(
        '$path:$lineNumber ${node.name.lexeme} is an unclassified behavioral constant',
      );
    } else if (!registeredIds.contains(annotation.group(1))) {
      failures.add(
        '$path:$lineNumber references unknown ${annotation.group(1)}',
      );
    }
    super.visitVariableDeclaration(node);
  }

  bool _isBehavioralLiteral(Expression? expression) =>
      expression is IntegerLiteral ||
      expression is DoubleLiteral ||
      expression is SimpleStringLiteral ||
      (expression is InstanceCreationExpression &&
          expression.constructorName.type.name.lexeme == 'Duration');

  String _declarationSource(VariableDeclarationList declaration) {
    final lineEnd = content.indexOf('\n', declaration.end);
    return content.substring(
      declaration.offset,
      lineEnd < 0 ? content.length : lineEnd,
    );
  }

  int _lineNumber(int offset) =>
      '\n'.allMatches(content.substring(0, offset)).length + 1;
}
