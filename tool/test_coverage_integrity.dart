import 'dart:io';

import 'verify_coverage.dart';

void main() {
  final invalid = <List<String>>[
    ['SF:lib/a.dart', 'LF:10', 'LH:10', 'end_of_record'],
    ['SF:lib/a.dart', 'DA:1,0', 'LF:1', 'LH:1', 'end_of_record'],
    ['SF:lib/a.dart', 'DA:1,1', 'LF:1', 'LH:-1', 'end_of_record'],
    ['SF:lib/a.dart', 'DA:1,1'],
  ];
  for (final lines in invalid) {
    var rejected = false;
    try {
      parseCoverage(lines);
    } on FormatException {
      rejected = true;
    }
    if (!rejected) throw StateError('Invalid coverage accepted: $lines');
  }
  final valid = parseCoverage([
    'SF:lib/a.dart',
    'DA:1,1',
    'DA:2,0',
    'LF:2',
    'LH:1',
    'end_of_record',
  ]);
  if (valid['lib/a.dart'] != (found: 2, hit: 1)) {
    throw StateError('Valid line-level coverage was not retained');
  }
  stdout.writeln(
    'Coverage integrity: valid lines and 4 invalid reports checked',
  );
}
