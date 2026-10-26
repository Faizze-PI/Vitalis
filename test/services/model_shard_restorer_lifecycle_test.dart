import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/services/model_registry_service.dart';

import '../support/shard_restore_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ShardRestoreFixture fixture;
  setUp(() async {
    fixture = ShardRestoreFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.destroy());

  test(
    'disposal retains pending selection and rejects its late completion',
    () async {
      final entered = Completer<void>();
      final selected = Completer<List<ImportedModelFile>?>();
      final owner = fixture.registry(
        picker: () {
          entered.complete();
          return selected.future;
        },
      );
      final result = expectLater(
        owner.restoreMissingFile('fixture'),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await entered.future;
      final closing = owner.close();
      await expectLater(
        owner.restoreMissingFile('fixture'),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      selected.complete(fixture.picked());
      await result;
      await closing;
      expect(fixture.probes, 0);
      expect(await fixture.storage.getModel('fixture'), fixture.beforeModel);
      expect(
        await fixture.storage.getModelFiles('fixture'),
        fixture.beforeFiles,
      );
    },
  );

  test(
    'competing registry recovery cannot disturb the admitted picker owner',
    () async {
      final entered = Completer<void>();
      final selected = Completer<List<ImportedModelFile>?>();
      final owner = fixture.registry(
        picker: () {
          entered.complete();
          return selected.future;
        },
      );
      final operation = owner.restoreMissingFile('fixture');
      await entered.future;
      final competitor = fixture.registry();
      await expectLater(
        competitor.restoreMissingFile('fixture'),
        throwsA(isA<ModelStorageBusy>()),
      );
      await competitor.close();
      expect(fixture.picks, 1);
      expect(fixture.probes, 0);
      selected.complete(fixture.picked());
      expect((await operation)?.isInstalled, isTrue);
      await owner.close();
      expect(fixture.picks, 1);
      expect(fixture.probes, 1);
      expect(
        await fixture.storage.getModelSettings(fixture.chatId),
        fixture.beforeSettings,
      );
    },
  );
}
