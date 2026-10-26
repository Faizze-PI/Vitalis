import 'dart:convert';
import 'dart:io';

/// Validates machine output without depending on JSON whitespace or key order.
String? validateFlutterVersion(String input, String flutter, String dart) {
  Object? decoded;
  try {
    decoded = jsonDecode(input);
  } on FormatException {
    return 'Flutter returned invalid version JSON.';
  }
  if (decoded is! Map<String, dynamic>) {
    return 'Flutter version output must be a JSON object.';
  }
  final actualDart = decoded['dartSdkVersion'];
  // Stable Flutter can include a parenthesized build timestamp after Dart's
  // version. Do not accept prereleases or numeric-prefix matches (3.12.20).
  final dartMatches =
      actualDart is String &&
      RegExp(
        '^${RegExp.escape(dart)}(?:\\s+\\([^\\r\\n]*\\))?\$',
      ).hasMatch(actualDart);
  if (decoded['frameworkVersion'] != flutter || !dartMatches) {
    return 'VITALIS requires Flutter $flutter / Dart $dart.';
  }
  return null;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Expected toolchain policy path.');
    exitCode = 2;
    return;
  }
  final policy =
      jsonDecode(await File(arguments.single).readAsString())
          as Map<String, dynamic>;
  final input = await stdin.transform(utf8.decoder).join();
  final failure = validateFlutterVersion(
    input,
    policy['flutter'] as String,
    policy['dart'] as String,
  );
  if (failure != null) {
    stderr.writeln(failure);
    exitCode = 2;
  }
}
