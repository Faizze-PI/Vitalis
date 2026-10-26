import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';
import 'package:vitalis_app/services/startup_capability_source.dart';
import 'package:vitalis_app/services/startup_coordinator.dart';

void main() {
  test('timed-out bootstrap completion cannot enable inference', () async {
    final pending = Completer<StartupModelReadiness>();
    final selected = SelectedModelReadiness((_) => pending.future);
    final coordinator = StartupCoordinator(
      openDatabase: () async {},
      loadLogger: () async {},
      migrateLegacyPreferences: () async {},
      initializeSafety: () async {},
      assessModel: () => selected.assessForBootstrap('bundled'),
      optionalTaskTimeout: const Duration(milliseconds: 5),
    );
    addTearDown(coordinator.dispose);
    addTearDown(selected.dispose);
    final source = StartupCapabilitySource(coordinator, selected);
    await coordinator.start();
    expect(coordinator.canRetry, isFalse);
    expect(source.snapshot().canInfer, isFalse);
    pending.complete(StartupModelReadiness.ready);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.canRetry, isTrue);
    expect(source.snapshot().canBrowse, isTrue);
    expect(source.snapshot().canInfer, isFalse);
    expect(selected.modelId, isNull);
  });
  test(
    'current chat model readiness controls inference without changing browse',
    () async {
      final coordinator = StartupCoordinator(
        openDatabase: () async {},
        loadLogger: () async {},
        migrateLegacyPreferences: () async {},
        initializeSafety: () async {},
        assessModel: () async => StartupModelReadiness.ready,
      );
      final selected = SelectedModelReadiness(
        (id) async => id == 'available'
            ? StartupModelReadiness.ready
            : StartupModelReadiness.missing,
      );
      addTearDown(coordinator.dispose);
      addTearDown(selected.dispose);
      final source = StartupCapabilitySource(coordinator, selected);

      await coordinator.start();
      expect(source.snapshot().canBrowse, isTrue);
      expect(source.snapshot().canInfer, isFalse);

      await selected.select('missing');
      expect(source.snapshot().canBrowse, isTrue);
      expect(source.snapshot().canInfer, isFalse);
      expect(source.snapshot().readOnly, isTrue);

      final checking = selected.select('available');
      expect(source.snapshot().canInfer, isFalse);
      await checking;
      expect(source.snapshot().canInfer, isTrue);

      selected.invalidate();
      expect(source.snapshot().canInfer, isFalse);
    },
  );
}
