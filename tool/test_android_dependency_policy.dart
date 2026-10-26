import 'dart:io';

Future<void> main() async {
  final repository = File.fromUri(Platform.script).parent.parent;
  final fixture = Directory.systemTemp.createTempSync(
    'vitalis test dependency ',
  );
  try {
    File('${fixture.path}/settings.gradle').writeAsStringSync(
      "rootProject.name = 'dependency-policy-fixture'\ninclude 'plugin'\n",
    );
    Directory('${fixture.path}/plugin').createSync();
    for (final artifact in [
      ('androidx/test', 'runner', '1.7.0'),
      ('androidx/test/ext', 'junit', '1.3.0'),
      ('androidx/test', 'rules', '1.2.0'),
      ('androidx/test/espresso', 'espresso-core', '3.3.0'),
    ]) {
      final dir = Directory(
        '${fixture.path}/maven/${artifact.$1}/${artifact.$2}/${artifact.$3}',
      )..createSync(recursive: true);
      File('${dir.path}/${artifact.$2}-${artifact.$3}.pom').writeAsStringSync(
        '''<project><modelVersion>4.0.0</modelVersion><groupId>${artifact.$1.replaceAll('/', '.')}</groupId><artifactId>${artifact.$2}</artifactId><version>${artifact.$3}</version><packaging>pom</packaging></project>''',
      );
    }
    final policyPath = File(
      '${repository.path}/tool/toolchain_policy.json',
    ).uri.toString();
    final scriptPath = File(
      '${repository.path}/android/test-dependency-policy.gradle',
    ).uri.toString();
    File('${fixture.path}/build.gradle').writeAsStringSync('''
ext.vitalisToolchainPolicy = new File(new URI('$policyPath'))
apply from: new File(new URI('$scriptPath'))
allprojects {
  repositories { maven { url = rootProject.file('maven').toURI() } }
  configurations { probe }
  dependencies {
    probe 'androidx.test:runner:9.+'
    probe 'androidx.test.ext:junit:9.+'
    probe 'androidx.test:rules:9.+'
    probe 'androidx.test.espresso:espresso-core:9.+'
  }
  tasks.register('verifyPolicy') {
    doLast {
      def modules = configurations.probe.resolvedConfiguration.firstLevelModuleDependencies.collect { it.moduleGroup + ':' + it.moduleName + ':' + it.moduleVersion }.toSet()
      assert modules == ['androidx.test:runner:1.7.0', 'androidx.test.ext:junit:1.3.0', 'androidx.test:rules:1.2.0', 'androidx.test.espresso:espresso-core:3.3.0'].toSet(): modules
    }
  }
}
''');
    final wrapper =
        '${repository.path}/android/gradlew${Platform.isWindows ? '.bat' : ''}';
    final process = await Process.start(
      wrapper,
      [
        '-p',
        fixture.path,
        '--offline',
        '--no-daemon',
        'verifyPolicy',
        ':plugin:verifyPolicy',
      ],
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
    if (exitCode == 0)
      stdout.writeln('Root and plugin floating selectors pinned offline.');
  } finally {
    fixture.deleteSync(recursive: true);
  }
}
