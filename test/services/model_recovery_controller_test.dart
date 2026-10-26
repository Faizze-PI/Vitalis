import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/services/model_recovery_controller.dart';
import 'package:vitalis_app/models/model_verification_phase.dart';
import 'package:vitalis_app/models/model_storage_error.dart';

const fixture = ModelDescriptor(
  id: 'fixture',
  displayName: 'Disposable',
  source: 'local',
  compatibilityStatus: 'compatible',
);

void main() {
  test(
    'phase reporter rejects late events from an earlier recovery attempt',
    () async {
      final completions = [
        Completer<ModelDescriptor>(),
        Completer<ModelDescriptor>(),
      ];
      var attempt = 0;
      final state = ModelRecoveryController(
        (_) => completions[attempt++].future,
      );
      addTearDown(state.dispose);
      final first = state.recover('fixture');
      final stale = state.phaseReporter('fixture');
      stale(ModelVerificationPhase.hashing);
      expect(state.phaseFor('fixture'), ModelVerificationPhase.hashing);
      completions.first.complete(fixture);
      await first;
      final second = state.recover('fixture');
      final current = state.phaseReporter('fixture');
      current(ModelVerificationPhase.metadata);
      stale(ModelVerificationPhase.inferenceCheck);
      expect(state.phaseFor('fixture'), ModelVerificationPhase.metadata);
      await Future<void>.delayed(Duration.zero);
      state.dispose();
      current(ModelVerificationPhase.inferenceCheck);
      expect(state.phaseFor('fixture'), ModelVerificationPhase.metadata);
      completions.last.complete(fixture);
      await second;
    },
  );
  test(
    'recovery rejects a different model identity instead of reporting success',
    () async {
      final state = ModelRecoveryController(
        (_) async => const ModelDescriptor(
          id: 'different',
          displayName: 'Disposable',
          source: 'local',
          compatibilityStatus: 'compatible',
        ),
      );
      addTearDown(state.dispose);
      await expectLater(state.recover('fixture'), throwsStateError);
      expect(state.stateFor('fixture'), ModelRecoveryState.failed);
    },
  );
  test(
    'synchronous failure releases admission for an explicit retry',
    () async {
      var attempts = 0;
      final state = ModelRecoveryController((_) {
        if (++attempts == 1) throw StateError('fixture synchronous failure');
        return Future.value(fixture);
      });
      addTearDown(state.dispose);
      await expectLater(state.recover('fixture'), throwsStateError);
      expect(await state.recover('fixture'), fixture);
      expect(attempts, 2);
      expect(state.stateFor('fixture'), ModelRecoveryState.succeeded);
    },
  );
  test(
    'disposal before scheduled verification prevents new underlying work',
    () async {
      var calls = 0;
      final state = ModelRecoveryController((_) async {
        calls++;
        return fixture;
      });
      final pending = state.recover('fixture');
      state.dispose();
      await expectLater(pending, throwsStateError);
      expect(calls, 0);
    },
  );
  test(
    'duplicate recovery shares verification and does not activate',
    () async {
      final done = Completer<ModelDescriptor>();
      var calls = 0;
      final state = ModelRecoveryController((_) {
        calls++;
        return done.future;
      });
      addTearDown(state.dispose);
      final first = state.recover('fixture');
      expect(state.recover('fixture'), same(first));
      expect(state.stateFor('fixture'), ModelRecoveryState.verifying);
      done.complete(fixture);
      expect(await first, same(fixture));
      expect(calls, 1);
      expect(state.stateFor('fixture'), ModelRecoveryState.succeeded);
    },
  );
  for (final fault in [
    ModelProbeSafetyStop(),
    ModelStorageBusy(),
    InferenceRuntimeBusy(),
    InferenceRecoveryRequired(),
    StateError('fixture'),
  ]) {
    test(
      'classifies ${fault.runtimeType} without changing model identity',
      () async {
        final state = ModelRecoveryController((_) async => throw fault);
        addTearDown(state.dispose);
        await expectLater(state.recover('fixture'), throwsA(same(fault)));
        expect(
          state.stateFor('fixture'),
          fault is ModelProbeSafetyStop
              ? ModelRecoveryState.safetyStopped
              : fault is ModelStorageBusy
              ? ModelRecoveryState.storageBusy
              : fault is InferenceRuntimeBusy
              ? ModelRecoveryState.runtimeBusy
              : fault is InferenceRecoveryRequired
              ? ModelRecoveryState.recoveryRequired
              : ModelRecoveryState.failed,
        );
      },
    );
  }
  test(
    'disposal rejects admission but retains pending verification completion',
    () async {
      final done = Completer<ModelDescriptor>();
      final state = ModelRecoveryController((_) => done.future);
      final pending = state.recover('fixture');
      await Future<void>.delayed(Duration.zero);
      state.dispose();
      await expectLater(state.recover('fixture'), throwsStateError);
      done.complete(fixture);
      expect(await pending, fixture);
      expect(state.stateFor('fixture'), ModelRecoveryState.verifying);
    },
  );
}
