import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/screens/model_library_screen.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/providers/model_library_provider.dart';
import 'package:vitalis_app/services/model_recovery_controller.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/model_download_manager.dart';
import 'package:vitalis_app/services/model_hub_client.dart';
import 'package:vitalis_app/models/model_download_job.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/services/model_update_service.dart';
import 'package:vitalis_app/models/model_verification_phase.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';

const model = ModelDescriptor(
  id: 'fixture',
  displayName: 'Disposable',
  source: 'local',
  compatibilityStatus: 'compatible',
);
void main() {
  test('late restoration snapshot preserves newer durable progress', () async {
    final downloads = _DelayedRestoration();
    final library = ModelLibraryProvider(
      hub: _Hub(),
      registry: _Registry(),
      downloads: downloads,
    );
    addTearDown(library.dispose);
    final loading = library.initialize();
    await downloads.entered.future;
    downloads.publish(
      downloads.original.copyWith(
        state: ModelDownloadJobState.downloading,
        downloadedBytes: 40,
      ),
    );
    downloads.result.complete([downloads.original]);
    await loading;
    expect(library.jobs.single.state, ModelDownloadJobState.downloading);
    expect(library.jobs.single.downloadedBytes, 40);
  });

  test(
    'failed completed-job refresh retains models and reports a redacted error',
    () async {
      final downloads = _WorkingDownloads();
      final registry = _Registry();
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: downloads,
      );
      addTearDown(library.dispose);
      await library.initialize();
      final failed = Completer<List<ModelDescriptor>>();
      registry.listing = failed.future;
      downloads.publish(
        downloads.original.copyWith(state: ModelDownloadJobState.completed),
      );
      failed.completeError(StateError('private fixture details'));
      await Future<void>.delayed(Duration.zero);
      expect(library.installed, [model]);
      expect(library.status, ModelLibraryStatus.error);
      expect(library.error, isNot(contains('private fixture')));
    },
  );
  testWidgets('persisted transfer updates expose Pause before completion', (
    tester,
  ) async {
    final downloads = _WorkingDownloads();
    final library = ModelLibraryProvider(
      hub: _Hub(),
      registry: _Registry(),
      downloads: downloads,
    );
    addTearDown(library.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: library,
        child: const MaterialApp(home: ModelLibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause download'), findsNothing);
    downloads.publish(
      downloads.original.copyWith(
        state: ModelDownloadJobState.downloading,
        downloadedBytes: 40,
        totalBytes: 100,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause download'), findsOneWidget);
    expect(library.jobs.single.downloadedBytes, 40);
    await tester.tap(find.byTooltip('Pause download'));
    expect(downloads.pauses, [downloads.original.id]);
    expect(find.byTooltip('Pause download'), findsOneWidget);
    expect(find.byTooltip('Resume download'), findsNothing);
    downloads.publish(
      downloads.original.copyWith(state: ModelDownloadJobState.paused),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Resume download'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    library.dispose();
    expect(downloads.listeners, isEmpty);
    downloads.publish(
      downloads.original.copyWith(state: ModelDownloadJobState.failed),
    );
    expect(tester.takeException(), isNull);
  });
  for (final dispose in [false, true]) {
    test(
      'background completion refreshes models without late disposed publication $dispose',
      () async {
        final downloads = _WorkingDownloads();
        final registry = _Registry();
        final pending = Completer<List<ModelDescriptor>>();
        registry.listing = pending.future;
        final library = ModelLibraryProvider(
          hub: _Hub(),
          registry: registry,
          downloads: downloads,
        );
        addTearDown(library.dispose);
        var notifications = 0;
        library.addListener(() => notifications++);
        downloads.publish(
          downloads.original.copyWith(state: ModelDownloadJobState.completed),
        );
        expect(registry.reads, 1);
        final before = notifications;
        if (dispose) library.dispose();
        pending.complete([model]);
        await Future<void>.delayed(Duration.zero);
        expect(library.installed, dispose ? isEmpty : [model]);
        expect(notifications, dispose ? before : greaterThan(before));
      },
    );
  }

  test(
    'late installed snapshot cannot replace a newer completed-job refresh',
    () async {
      final downloads = _WorkingDownloads();
      final registry = _Registry();
      final first = Completer<List<ModelDescriptor>>();
      final second = Completer<List<ModelDescriptor>>();
      registry.listing = first.future;
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: downloads,
      );
      addTearDown(library.dispose);
      downloads.publish(
        downloads.original.copyWith(state: ModelDownloadJobState.completed),
      );
      registry.listing = second.future;
      downloads.publish(
        downloads.original.copyWith(state: ModelDownloadJobState.completed),
      );
      second.complete([model]);
      await Future<void>.delayed(Duration.zero);
      first.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(library.installed, [model]);
    },
  );
  for (final leaveScreen in [false, true]) {
    testWidgets(
      'Model Library observes initialization failures (leave: $leaveScreen)',
      (tester) async {
        final registry = _Registry();
        final listing = Completer<List<ModelDescriptor>>();
        registry.listing = listing.future;
        final library = ModelLibraryProvider(
          hub: _Hub(),
          registry: registry,
          downloads: _WorkingDownloads(),
        );
        addTearDown(library.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: library,
            child: const MaterialApp(home: ModelLibraryScreen()),
          ),
        );
        expect(registry.reads, 1);
        if (leaveScreen) await tester.pumpWidget(const SizedBox.shrink());
        listing.completeError(
          StateError('private fixture path and diagnostic'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('private fixture'), findsNothing);
        if (!leaveScreen) {
          expect(
            find.text('Could not load Model Library. Try again.'),
            findsOneWidget,
          );
          registry.listing = Future.value([model]);
          await tester.tap(find.text('Retry'));
          await tester.pumpAndSettle();
          expect(registry.reads, 2);
          expect(library.installed, [model]);
          expect(registry.verifications, 0);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final fail in [false, true]) {
    test(
      'library initialization shares pending work and permits retry ($fail)',
      () async {
        final registry = _Registry();
        final listing = Completer<List<ModelDescriptor>>();
        registry.listing = listing.future;
        final downloads = _WorkingDownloads();
        final library = ModelLibraryProvider(
          hub: _Hub(),
          registry: registry,
          downloads: downloads,
        );
        addTearDown(library.dispose);
        final first = library.initialize();
        final second = library.initialize();
        final observedFirst = fail
            ? expectLater(first, throwsStateError)
            : first;
        final observedSecond = fail
            ? expectLater(second, throwsStateError)
            : second;
        final readsWhilePending = registry.reads;
        if (fail) {
          listing.completeError(StateError('private fixture failure'));
        } else {
          listing.complete([model]);
        }
        await Future.wait([observedFirst, observedSecond]);
        expect(readsWhilePending, 1);
        expect(downloads.restorations, fail ? 0 : 1);
        if (fail) {
          registry.listing = Future.value([model]);
          await library.initialize();
          expect(registry.reads, 2);
          expect(downloads.restorations, 1);
        }
        expect(library.installed, [model]);
      },
    );
  }

  for (final action in [
    'download',
    'resume',
    'cancel',
    'import',
    'checkUpdate',
    'downloadUpdate',
  ]) {
    test('disposed library completion starts no refresh ($action)', () async {
      final gate = _CompletionGate();
      final registry = _GatedRegistry(gate);
      final downloads = _GatedDownloads(gate);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: downloads,
        updates: _GatedUpdates(downloads.original, gate),
      );
      final Future<dynamic> operation = switch (action) {
        'download' => library.download(
          library.bundledRecommendation,
          library.bundledVariant,
        ),
        'resume' => library.resume(downloads.original),
        'cancel' => library.cancel(downloads.original.id),
        'import' => library.importLocal(),
        'checkUpdate' => library.checkUpdate(model),
        _ => library.downloadUpdate(model),
      };
      await gate.entered.future;
      final visibleJobs = library.jobs;
      library.dispose();
      gate.release.complete();
      await operation;
      expect(registry.reads, 0);
      expect(downloads.restorations, 0);
      expect(library.jobs, visibleJobs);
      expect(library.installed, isEmpty);
    });
  }

  test(
    'disposed library initialization does not project reconciliation results',
    () async {
      final downloads = _DelayedRestoration();
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: _Registry(),
        downloads: downloads,
      );
      final initializing = library.initialize();
      await downloads.entered.future;
      library.dispose();
      downloads.result.complete([downloads.original]);
      await initializing;
      expect(library.installed, isEmpty);
      expect(library.jobs, isEmpty);
      expect(library.status, ModelLibraryStatus.idle);
    },
  );

  test(
    'disposed library initialization does not begin download reconciliation',
    () async {
      final registry = _Registry();
      final listing = Completer<List<ModelDescriptor>>();
      registry.listing = listing.future;
      final downloads = _WorkingDownloads();
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: downloads,
      );
      final initializing = library.initialize();
      expect(registry.reads, 1);
      library.dispose();
      listing.complete([model]);
      await initializing;
      expect(downloads.restorations, 0);
      expect(library.installed, isEmpty);
      expect(library.jobs, isEmpty);
      expect(library.status, ModelLibraryStatus.idle);
    },
  );

  for (final failRefresh in [false, true]) {
    test(
      'removal refresh handles disposal or failure ($failRefresh)',
      () async {
        final registry = _Registry();
        final listing = Completer<List<ModelDescriptor>>();
        registry.listing = listing.future;
        final selected = SelectedModelReadiness(
          (_) async => StartupModelReadiness.ready,
        );
        await selected.select(model.id);
        final library = ModelLibraryProvider(
          hub: _Hub(),
          registry: registry,
          downloads: _Downloads(),
          selectedModel: selected,
        );
        addTearDown(selected.dispose);
        var notifications = 0;
        library.addListener(() => notifications++);
        final operation = library.uninstall(model);
        final result = failRefresh
            ? expectLater(operation, throwsStateError)
            : operation;
        await Future<void>.delayed(Duration.zero);
        expect(selected.readiness, StartupModelReadiness.unknown);
        expect(registry.reads, 1);
        library.dispose();
        if (failRefresh) {
          listing.completeError(StateError('refresh failed'));
        } else {
          listing.complete([model]);
        }
        await result;
        expect(library.installed, isEmpty);
        expect(notifications, 0);
        expect(selected.modelId, model.id);
        expect(selected.readiness, StartupModelReadiness.unknown);
      },
    );
  }

  for (final failure in [
    ModelStorageBusy(),
    InferenceRuntimeBusy(),
    InferenceRecoveryRequired(),
    StateError('projection failed'),
  ]) {
    test(
      'removal failure ${failure.runtimeType} preserves accurate readiness',
      () async {
        final registry = _Registry();
        final stopped = Completer<void>();
        registry.removal = stopped.future;
        final selected = SelectedModelReadiness(
          (_) async => StartupModelReadiness.ready,
        );
        await selected.select(model.id);
        final library = ModelLibraryProvider(
          hub: _Hub(),
          registry: registry,
          downloads: _Downloads(),
          selectedModel: selected,
        );
        addTearDown(library.dispose);
        addTearDown(selected.dispose);
        final result = expectLater(
          library.uninstall(model),
          throwsA(same(failure)),
        );
        stopped.completeError(failure);
        await result;
        expect(selected.modelId, model.id);
        expect(
          selected.readiness,
          failure is ModelStorageBusy ||
                  failure is InferenceRuntimeBusy ||
                  failure is InferenceRecoveryRequired
              ? StartupModelReadiness.ready
              : StartupModelReadiness.unknown,
        );
        expect(registry.reads, 0);
      },
    );
  }

  test(
    'removal never invalidates another model selected while waiting',
    () async {
      final registry = _Registry();
      final stopped = Completer<void>();
      registry.removal = stopped.future;
      final selected = SelectedModelReadiness(
        (_) async => StartupModelReadiness.ready,
      );
      await selected.select(model.id);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _Downloads(),
        selectedModel: selected,
      );
      addTearDown(library.dispose);
      addTearDown(selected.dispose);
      final operation = library.uninstall(model);
      await selected.select('unrelated');
      stopped.complete();
      await operation;
      expect(selected.modelId, 'unrelated');
      expect(selected.readiness, StartupModelReadiness.ready);
    },
  );

  test(
    'removing selected model invalidates readiness without substitution',
    () async {
      final registry = _Registry();
      final selected = SelectedModelReadiness(
        (_) async => StartupModelReadiness.ready,
      );
      await selected.select(model.id);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _Downloads(),
        selectedModel: selected,
      );
      addTearDown(library.dispose);
      addTearDown(selected.dispose);
      await library.uninstall(model);
      expect(selected.modelId, model.id);
      expect(selected.readiness, StartupModelReadiness.unknown);
      expect(registry.removed, [model.id]);
    },
  );

  test(
    'removal settling after disposal invalidates without registry refresh',
    () async {
      final registry = _Registry();
      final stopped = Completer<void>();
      registry.removal = stopped.future;
      final selected = SelectedModelReadiness(
        (_) async => StartupModelReadiness.ready,
      );
      await selected.select(model.id);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _Downloads(),
        selectedModel: selected,
      );
      addTearDown(selected.dispose);
      final operation = library.uninstall(model);
      library.dispose();
      stopped.complete();
      await operation;
      expect(selected.modelId, model.id);
      expect(selected.readiness, StartupModelReadiness.unknown);
      expect(registry.reads, 0);
    },
  );

  for (final source in ['local_import', 'huggingface']) {
    testWidgets('model actions distinguish $source recovery', (tester) async {
      final registry = _Registry();
      registry.models = [
        ModelDescriptor(
          id: model.id,
          displayName: model.displayName,
          source: source,
          compatibilityStatus: 'verification_failed',
          localPath: 'recorded-missing.gguf',
          sha256: 'recorded-hash',
        ),
      ];
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _WorkingDownloads(),
      );
      addTearDown(library.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: library,
          child: const MaterialApp(home: ModelLibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Installed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Model actions'));
      await tester.pumpAndSettle();
      expect(find.text('Find missing model file'), findsOneWidget);
      expect(
        find.text('Download again'),
        source == 'huggingface' ? findsOneWidget : findsNothing,
      );
      expect(find.text('Use for this chat'), findsNothing);
      await tester.tap(find.text('Find missing model file'));
      await tester.pumpAndSettle();
      expect(registry.restorations, 1);
      registry.replacement.complete(null);
      await tester.pumpAndSettle();
      expect(
        find.text('File selection cancelled. Your model is unchanged.'),
        findsOneWidget,
      );
      expect(registry.reads, 1);
    });
  }
  test(
    'replacement is single-flight and refreshes only selected readiness',
    () async {
      final registry = _Registry();
      final selected = SelectedModelReadiness(
        (_) async => StartupModelReadiness.ready,
      );
      await selected.select(model.id);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _Downloads(),
        selectedModel: selected,
      );
      addTearDown(library.dispose);
      addTearDown(selected.dispose);
      final first = library.restoreMissingFile(model);
      final second = library.restoreMissingFile(model);
      await Future<void>.delayed(Duration.zero);
      expect(registry.restorations, 1);
      registry.replacement.complete(model);
      expect(await first, model);
      expect(await second, model);
      expect(library.installed, [model]);
      expect(selected.modelId, model.id);
      expect(registry.verifications, 0);
    },
  );

  test(
    'cancelled replacement does not refresh registry or selection',
    () async {
      final registry = _Registry();
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _Downloads(),
      );
      addTearDown(library.dispose);
      final operation = library.restoreMissingFile(model);
      registry.replacement.complete(null);
      expect(await operation, isNull);
      expect(library.recoveryState(model.id), ModelRecoveryState.cancelled);
      expect(registry.reads, 0);
      expect(library.installed, isEmpty);
    },
  );

  test(
    'replacement finishing after disposal cannot publish or reassess',
    () async {
      final registry = _Registry();
      var inspections = 0;
      final selected = SelectedModelReadiness((_) async {
        inspections++;
        return StartupModelReadiness.ready;
      });
      await selected.select(model.id);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _Downloads(),
        selectedModel: selected,
      );
      addTearDown(selected.dispose);
      final operation = library.restoreMissingFile(model);
      await Future<void>.delayed(Duration.zero);
      library.dispose();
      registry.replacement.complete(model);
      expect(await operation, model);
      expect(registry.reads, 0);
      expect(inspections, 1);
    },
  );
  test(
    'verified current model refreshes readiness without selecting a chat',
    () async {
      var inspections = 0;
      final selected = SelectedModelReadiness(
        (_) async => ++inspections == 1
            ? StartupModelReadiness.missing
            : StartupModelReadiness.ready,
      );
      await selected.select(model.id);
      final registry = _Registry();
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: _Downloads(),
        selectedModel: selected,
      );
      addTearDown(library.dispose);
      addTearDown(selected.dispose);

      final recovery = library.verify(model);
      registry.complete.complete(model);
      expect(await recovery, model);
      expect(selected.modelId, model.id);
      expect(selected.readiness, StartupModelReadiness.ready);
      expect(inspections, 2);
    },
  );

  test(
    'explicit import update and uninstall refresh library without implicit selection',
    () async {
      final registry = _Registry();
      final downloads = _WorkingDownloads();
      final updates = _Updates(downloads.original);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: downloads,
        updates: updates,
      );
      addTearDown(library.dispose);
      expect(await library.importLocal(), model);
      expect(registry.imports, 1);
      expect(library.installed, [model]);
      final available = await library.checkUpdate(model);
      expect(available.available, isTrue);
      expect(updates.checked, [model.id]);
      final job = await library.downloadUpdate(model);
      expect(job.revision, 'new-immutable');
      expect(library.jobs.single.revision, 'new-immutable');
      expect(updates.applied, [model.id]);
      await library.uninstall(model);
      expect(registry.removed, [model.id]);
      expect(library.installed, isEmpty);
      expect(registry.verifications, 0);
      expect(registry.unexpectedCalls, 0);
    },
  );
  test(
    'download controls project jobs and refresh registry without activation',
    () async {
      final registry = _Registry();
      final downloads = _WorkingDownloads();
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: registry,
        downloads: downloads,
      );
      addTearDown(library.dispose);
      await library.initialize();
      expect(library.status, ModelLibraryStatus.ready);
      expect(library.jobs, [downloads.original]);
      final completed = await library.download(
        library.bundledRecommendation,
        library.bundledVariant,
      );
      expect(completed.state, ModelDownloadJobState.completed);
      expect(library.jobs, [completed]);
      expect(library.installed, [model]);
      expect(downloads.enqueued, [library.bundledRecommendation.id]);
      library.pause(completed.id);
      expect(downloads.pauses, [completed.id]);
      await library.resume(downloads.original);
      expect(downloads.runs, [completed.id, completed.id]);
      await library.cancel(completed.id);
      expect(downloads.cancelled, [completed.id]);
      expect(
        library.jobs.single.toMap(),
        downloads.original
            .copyWith(state: ModelDownloadJobState.cancelled)
            .toMap(),
      );
      expect(registry.verifications, 0);
      expect(registry.unexpectedCalls, 0);
    },
  );
  test(
    'all disposed library actions reject before dependency access',
    () async {
      final registry = _Registry();
      final downloads = _Downloads();
      final hub = _Hub();
      final library = ModelLibraryProvider(
        hub: hub,
        registry: registry,
        downloads: downloads,
      );
      final summary = library.bundledRecommendation;
      final variant = library.bundledVariant;
      final job = ModelDownloadJob(
        id: 'fixture',
        modelId: model.id,
        repository: summary.id,
        revision: summary.revision,
        state: ModelDownloadJobState.paused,
        downloadedBytes: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      library.dispose();
      final actions = <Future<dynamic> Function()>[
        library.initialize,
        () => library.search('fixture'),
        library.loadMore,
        () => library.variants(summary),
        () => library.assessFit(summary, variant),
        () => library.inspectRemote(variant),
        () => library.download(summary, variant),
        () => library.cancel('fixture'),
        () => library.resume(job),
        library.importLocal,
        library.openModelFolder,
        () => library.verify(model),
        () => library.checkUpdate(model),
        () => library.downloadUpdate(model),
        () => library.uninstall(model),
        () => library.repair(model),
      ];
      for (final action in actions) {
        await expectLater(Future<dynamic>.sync(action), throwsStateError);
      }
      expect(registry.verifications, 0);
      expect(registry.reads, 0);
      expect(registry.unexpectedCalls, 0);
      expect(downloads.unexpectedCalls, 0);
      expect(hub.unexpectedCalls, 0);
    },
  );
  test('disposed library rejects transfer controls before calling manager', () {
    final downloads = _Downloads();
    final library = ModelLibraryProvider(
      hub: _Hub(),
      registry: _Registry(),
      downloads: downloads,
    );
    library.dispose();
    expect(() => library.pause('fixture'), throwsStateError);
    expect(downloads.pauseCalls, 0);
  });
  for (final dispose in [false, true]) {
    test(
      'library verification shares work and ${dispose ? 'suppresses disposed publication' : 'refreshes installed records'}',
      () async {
        final registry = _Registry();
        final library = ModelLibraryProvider(
          hub: _Hub(),
          registry: registry,
          downloads: _Downloads(),
        );
        addTearDown(library.dispose);
        var publications = 0;
        library.addListener(() => publications++);
        final pending = library.verify(model);
        expect(library.verify(model), same(pending));
        expect(library.recoveryState(model.id), ModelRecoveryState.verifying);
        await Future<void>.delayed(Duration.zero);
        final before = publications;
        if (dispose) library.dispose();
        registry.complete.complete(model);
        expect(await pending, model);
        expect(registry.verifications, 1);
        expect(registry.reads, dispose ? 0 : 1);
        if (dispose) {
          expect(publications, before);
          await expectLater(library.verify(model), throwsStateError);
        } else {
          expect(library.installed, [model]);
          expect(library.recoveryState(model.id), ModelRecoveryState.succeeded);
        }
      },
    );
  }
}

class _Registry implements ModelRegistryService {
  List<ModelDescriptor> models = [model];
  int restorations = 0;
  final replacement = Completer<ModelDescriptor?>();
  @override
  Future<ModelDescriptor?> restoreMissingFile(
    String id, {
    ModelVerificationPhaseSink? onPhase,
  }) {
    restorations++;
    onPhase?.call(ModelVerificationPhase.hashing);
    return replacement.future;
  }

  int unexpectedCalls = 0;
  final complete = Completer<ModelDescriptor>();
  int verifications = 0;
  int reads = 0;
  Future<List<ModelDescriptor>>? listing;
  int imports = 0;
  final removed = <String>[];
  @override
  Future<ModelDescriptor?> importGguf() async {
    imports++;
    return model;
  }

  Future<void>? removal;
  @override
  Future<void> uninstall(String id) async {
    await removal;
    removed.add(id);
  }

  @override
  Future<ModelDescriptor> verifyInstallation(
    String id, {
    ModelVerificationPhaseSink? onPhase,
  }) {
    onPhase?.call(ModelVerificationPhase.hashing);
    verifications++;
    return complete.future;
  }

  @override
  Future<List<ModelDescriptor>> listModels() async {
    reads++;
    if (listing case final pending?) return pending;
    return removed.isEmpty ? models : [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected registry operation');
  }
}

class _Hub implements ModelHubClient {
  int unexpectedCalls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected Hub operation');
  }
}

class _Downloads implements ModelDownloadManager {
  final listeners = <void Function(ModelDownloadJob)>{};
  @override
  void addJobListener(void Function(ModelDownloadJob) listener) =>
      listeners.add(listener);
  @override
  void removeJobListener(void Function(ModelDownloadJob) listener) =>
      listeners.remove(listener);
  void publish(ModelDownloadJob job) {
    for (final listener in listeners.toList()) {
      listener(job);
    }
  }

  int unexpectedCalls = 0;
  int pauseCalls = 0;
  @override
  void pause(String jobId) {
    pauseCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected download operation');
  }
}

class _WorkingDownloads extends _Downloads {
  int restorations = 0;
  final original = ModelDownloadJob(
    id: 'fixture-job',
    modelId: model.id,
    repository: 'publisher/fixture',
    revision: 'immutable',
    state: ModelDownloadJobState.queued,
    downloadedBytes: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final enqueued = <String>[];
  final runs = <String>[];
  final pauses = <String>[];
  final cancelled = <String>[];
  @override
  Future<List<ModelDownloadJob>> restoreJobs() async {
    restorations++;
    return [
      cancelled.isEmpty
          ? original
          : original.copyWith(state: ModelDownloadJobState.cancelled),
    ];
  }

  @override
  Future<ModelDownloadJob> enqueue({
    required HubModelSummary model,
    required GgufVariant variant,
  }) async {
    enqueued.add(model.id);
    return original;
  }

  @override
  Future<ModelDownloadJob> run(ModelDownloadJob job) async {
    runs.add(job.id);
    return job.copyWith(state: ModelDownloadJobState.completed);
  }

  @override
  void pause(String jobId) => pauses.add(jobId);
  @override
  Future<void> cancel(String jobId) async => cancelled.add(jobId);
}

class _CompletionGate {
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> wait() async {
    entered.complete();
    await release.future;
  }
}

class _GatedRegistry extends _Registry {
  _GatedRegistry(this.gate);
  final _CompletionGate gate;
  @override
  Future<ModelDescriptor?> importGguf() async {
    await gate.wait();
    return super.importGguf();
  }
}

class _GatedDownloads extends _WorkingDownloads {
  _GatedDownloads(this.gate);
  final _CompletionGate gate;
  @override
  Future<ModelDownloadJob> run(ModelDownloadJob job) async {
    await gate.wait();
    return super.run(job);
  }

  @override
  Future<void> cancel(String id) async {
    await gate.wait();
    await super.cancel(id);
  }
}

class _GatedUpdates extends _Updates {
  _GatedUpdates(super.original, this.gate);
  final _CompletionGate gate;
  @override
  Future<ModelUpdateAvailability> check(ModelDescriptor model) async {
    await gate.wait();
    return super.check(model);
  }

  @override
  Future<ModelDownloadJob> apply(ModelDescriptor model) async {
    await gate.wait();
    return super.apply(model);
  }
}

class _DelayedRestoration extends _WorkingDownloads {
  final entered = Completer<void>();
  final result = Completer<List<ModelDownloadJob>>();
  @override
  Future<List<ModelDownloadJob>> restoreJobs() async {
    restorations++;
    entered.complete();
    return result.future;
  }
}

class _Updates implements ModelUpdateService {
  _Updates(this.original);
  final ModelDownloadJob original;
  final checked = <String>[];
  final applied = <String>[];
  @override
  Future<ModelUpdateAvailability> check(ModelDescriptor model) async {
    checked.add(model.id);
    return ModelUpdateAvailability(
      available: true,
      currentRevision: model.revision,
    );
  }

  @override
  Future<ModelDownloadJob> apply(ModelDescriptor model) async {
    applied.add(model.id);
    return ModelDownloadJob.fromMap({
      ...original.toMap(),
      'revision': 'new-immutable',
    });
  }
}
