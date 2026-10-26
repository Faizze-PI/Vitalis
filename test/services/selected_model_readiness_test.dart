import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';

void main() {
  test(
    'late bootstrap result cannot publish readiness or overlap selection',
    () async {
      final bootstrap = Completer<StartupModelReadiness>();
      final calls = <String>[];
      final state = SelectedModelReadiness((id) async {
        calls.add(id);
        return calls.length == 1
            ? bootstrap.future
            : StartupModelReadiness.missing;
      });
      addTearDown(state.dispose);
      final initial = state.assessForBootstrap('bundled');
      await Future<void>.delayed(Duration.zero);
      final selection = state.select('chat-model');
      expect(calls, ['bundled']);
      expect(state.readiness, StartupModelReadiness.checking);
      bootstrap.complete(StartupModelReadiness.ready);
      expect(await initial, StartupModelReadiness.ready);
      await selection;
      expect(calls, ['bundled', 'chat-model']);
      expect(state.modelId, 'chat-model');
      expect(state.readiness, StartupModelReadiness.missing);
    },
  );

  test('bootstrap assessment alone never selects or enables a model', () async {
    final state = SelectedModelReadiness(
      (_) async => StartupModelReadiness.ready,
    );
    addTearDown(state.dispose);
    expect(
      await state.assessForBootstrap('bundled'),
      StartupModelReadiness.ready,
    );
    expect(state.modelId, isNull);
    expect(state.readiness, StartupModelReadiness.unknown);
    state.dispose();
    await expectLater(state.assessForBootstrap('bundled'), throwsStateError);
  });

  test(
    'invalidation retains reader ownership and rejects its stale result',
    () async {
      final first = Completer<StartupModelReadiness>();
      var calls = 0;
      final state = SelectedModelReadiness(
        (_) async =>
            ++calls == 1 ? first.future : StartupModelReadiness.invalid,
      );
      addTearDown(state.dispose);
      final pending = state.select('fixture');
      await Future<void>.delayed(Duration.zero);
      state.invalidate();
      expect(state.readiness, StartupModelReadiness.unknown);
      final retry = state.select('fixture');
      expect(calls, 1);
      first.complete(StartupModelReadiness.ready);
      await pending;
      await retry;
      expect(calls, 2);
      expect(state.readiness, StartupModelReadiness.invalid);
      state.dispose();
      state.invalidate();
    },
  );
  test(
    'late prior assessment cannot unlock a different selected model',
    () async {
      final first = Completer<StartupModelReadiness>();
      final calls = <String>[];
      final state = SelectedModelReadiness((id) async {
        calls.add(id);
        return id == 'first' ? first.future : StartupModelReadiness.missing;
      });
      addTearDown(state.dispose);
      final a = state.select('first');
      await Future<void>.delayed(Duration.zero);
      final b = state.select('second');
      expect(state.readiness, StartupModelReadiness.checking);
      first.complete(StartupModelReadiness.ready);
      await a;
      await b;
      expect(state.modelId, 'second');
      expect(state.readiness, StartupModelReadiness.missing);
      expect(calls, ['first', 'second']);
    },
  );
  test('same selection shares work and explicit refresh rechecks', () async {
    var calls = 0;
    final state = SelectedModelReadiness((_) async {
      calls++;
      return StartupModelReadiness.ready;
    });
    addTearDown(state.dispose);
    final first = state.select('fixture');
    expect(state.select('fixture'), same(first));
    await first;
    await state.select('fixture');
    expect(calls, 1);
    await state.select('fixture', refresh: true);
    expect(calls, 2);
  });
  test(
    'assessment errors and disposed completions never grant readiness',
    () async {
      final state = SelectedModelReadiness(
        (_) async => throw StateError('fixture'),
      );
      await state.select('fixture');
      expect(state.readiness, StartupModelReadiness.unknown);
      state.dispose();
      await expectLater(state.select('fixture'), throwsStateError);
      final delayed = Completer<StartupModelReadiness>();
      final owned = SelectedModelReadiness((_) => delayed.future);
      final pending = owned.select('fixture');
      await Future<void>.delayed(Duration.zero);
      owned.dispose();
      delayed.complete(StartupModelReadiness.ready);
      await pending;
      expect(owned.readiness, StartupModelReadiness.unknown);
    },
  );
}
