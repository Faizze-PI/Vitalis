import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/device_safety_policy.dart';
import 'package:vitalis_app/services/memory_pressure_service.dart';

void main() {
  test('projects trim-memory events and critical threshold', () async {
    final events = StreamController<dynamic>();
    final service = MemoryPressureService(
      policy: const DeviceSafetyPolicy(criticalTrimMemoryLevel: 80),
      eventStream: () => events.stream,
    );
    addTearDown(() async {
      service.dispose();
      await events.close();
    });
    final observed = <int>[];
    final subscription = service.onMemoryPressure.listen(observed.add);
    addTearDown(subscription.cancel);

    service.startListening();
    events.add({'trimMemoryLevel': 40});
    events.add({'trimMemoryLevel': 80});
    await Future<void>.delayed(Duration.zero);

    expect(observed, [40, 80]);
    expect(service.currentLevel, 80);
    expect(service.isCritical, isTrue);
  });

  test('ignores unrelated and malformed events', () async {
    final events = StreamController<dynamic>();
    final service = MemoryPressureService(eventStream: () => events.stream);
    addTearDown(() async {
      service.dispose();
      await events.close();
    });
    service.startListening();

    events.add('not-a-map');
    events.add({'other': 12});
    events.add({'trimMemoryLevel': null});
    await Future<void>.delayed(Duration.zero);

    expect(service.currentLevel, 0);
    expect(service.isCritical, isFalse);
  });

  test('stream construction failure is contained', () {
    final service = MemoryPressureService(
      eventStream: () => throw StateError('fixture failure'),
    );
    addTearDown(service.dispose);

    expect(service.startListening, returnsNormally);
    expect(service.currentLevel, 0);
  });
}
