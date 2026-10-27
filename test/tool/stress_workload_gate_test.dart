import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_stress_workload.dart' as regression;

void main() {
  test(
    'stress fixture cleanup retains asynchronous ownership',
    regression.main,
  );
}
