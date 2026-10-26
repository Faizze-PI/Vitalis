import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/device_safety_policy.dart';

void main() {
  const policy = DeviceSafetyPolicy();
  final now = DateTime.utc(2026, 9, 2);

  test('charging bypasses only the low-battery rule', () {
    final reason = policy.unsafeReason(
      const DeviceSafetySnapshot(
        batteryLevel: 4,
        isCharging: true,
        batterySaver: true,
      ),
      now,
    );
    expect(reason, contains('Battery Saver'));
  });

  test('unknown telemetry is represented without fake safety values', () {
    final reason = policy.unsafeReason(const DeviceSafetySnapshot(), now);
    expect(reason, isNull);
  });

  test('severe thermal and critical memory start cooldown', () {
    expect(
      policy.shouldStartCooldown(
        const DeviceSafetySnapshot(
          isCharging: true,
          batterySaver: false,
          thermalStatus: 3,
        ),
      ),
      isTrue,
    );
    expect(
      policy.shouldStartCooldown(
        const DeviceSafetySnapshot(
          isCharging: true,
          batterySaver: false,
          trimMemoryLevel: 80,
        ),
      ),
      isTrue,
    );
  });

  test('cooldown uses the injected evaluation time', () {
    final reason = policy.unsafeReason(
      DeviceSafetySnapshot(
        isCharging: true,
        batterySaver: false,
        cooldownUntil: now.add(const Duration(seconds: 1)),
      ),
      now,
    );
    expect(reason, contains('cooldown'));
  });

  test(
    'unplugged low battery is blocked but unknown charging is not guessed',
    () {
      expect(
        policy.unsafeReason(
          const DeviceSafetySnapshot(batteryLevel: 4, isCharging: false),
          now,
        ),
        contains('critically low'),
      );
      expect(
        policy.unsafeReason(const DeviceSafetySnapshot(batteryLevel: 4), now),
        isNull,
      );
    },
  );

  test('critical memory recognizes platform and trim signals', () {
    expect(
      policy.isCriticalMemory(
        const DeviceSafetySnapshot(systemLowMemory: true),
      ),
      isTrue,
    );
    expect(
      policy.isCriticalMemory(const DeviceSafetySnapshot(trimMemoryLevel: 79)),
      isFalse,
    );
    expect(policy.isCriticalMemory(const DeviceSafetySnapshot()), isFalse);
  });

  test('severe thermal and memory return distinct safety reasons', () {
    expect(
      policy.unsafeReason(const DeviceSafetySnapshot(thermalStatus: 3), now),
      contains('temperature'),
    );
    expect(
      policy.unsafeReason(
        const DeviceSafetySnapshot(systemLowMemory: true),
        now,
      ),
      contains('memory'),
    );
  });

  test('expired cooldown does not block', () {
    expect(
      policy.unsafeReason(
        DeviceSafetySnapshot(
          cooldownUntil: now.subtract(const Duration(seconds: 1)),
        ),
        now,
      ),
      isNull,
    );
  });
}
