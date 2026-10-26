import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_download_job.dart';
import 'package:vitalis_app/providers/model_library_provider.dart';
import 'package:vitalis_app/screens/model_library_screen.dart';
import 'package:vitalis_app/services/remote_gguf_inspector.dart';

const _model = HubModelSummary(
  id: 'publisher/test-model',
  revision: 'immutable',
  tags: ['gguf'],
  downloads: 1,
  gated: false,
);

class _Library extends ChangeNotifier implements ModelLibraryProvider {
  final downloadGate = Completer<ModelDownloadJob>();
  final storedJobs = <ModelDownloadJob>[];
  @override
  ModelLibraryStatus status = ModelLibraryStatus.idle;
  @override
  List<HubModelSummary> results = [];
  @override
  String? error;
  @override
  bool canLoadMore = false;
  @override
  bool get canOpenModelFolder => false;
  @override
  List<ModelDescriptor> get installed => [];
  @override
  List<ModelDownloadJob> get jobs => storedJobs;
  @override
  HubModelSummary get bundledRecommendation => _model;
  @override
  GgufVariant get bundledVariant => const GgufVariant(
    repository: 'publisher/test-model',
    revision: 'immutable',
    displayName: 'Test GGUF',
    files: [GgufFile(name: 'fixture.gguf', sizeBytes: 4)],
  );
  @override
  Future<void> initialize() async {}
  @override
  Future<DeviceFitAssessment> assessFit(
    HubModelSummary model,
    GgufVariant variant,
  ) async => const DeviceFitAssessment(
    level: DeviceFitLevel.recommended,
    reason: 'Test fixture',
    estimatedMemoryBytes: 4,
    requiresLargeModelWarning: false,
  );
  @override
  Future<RemoteGgufMetadata> inspectRemote(GgufVariant variant) async =>
      RemoteGgufMetadata.unknown;
  @override
  Future<ModelDownloadJob> download(
    HubModelSummary model,
    GgufVariant variant,
  ) {
    storedJobs.add(
      ModelDownloadJob(
        id: 'test-job',
        modelId: 'test-model',
        repository: model.id,
        revision: model.revision,
        state: ModelDownloadJobState.queued,
        downloadedBytes: 0,
        totalBytes: 4,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    notifyListeners();
    return downloadGate.future;
  }

  @override
  Future<void> search(
    String query, {
    HubSort sort = HubSort.downloads,
    String? publisher,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openSearch(WidgetTester tester, _Library library) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ModelLibraryProvider>.value(
      value: library,
      child: const MaterialApp(home: ModelLibraryScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Hugging Face'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accepted download opens progress before transfer completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = _Library();
    addTearDown(library.dispose);
    await _openSearch(tester, library);
    await tester.tap(find.text('Recommended'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_model.id));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test GGUF'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();
    expect(library.storedJobs, hasLength(1));
    expect(find.text('queued'), findsOneWidget);
    library.downloadGate.complete(
      library.storedJobs.single.copyWith(
        state: ModelDownloadJobState.completed,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final action in ['Installed', 'Downloads', 'Search']) {
    testWidgets('search keyboard closes on $action', (tester) async {
      final library = _Library();
      addTearDown(library.dispose);
      await _openSearch(tester, library);
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(
        action == 'Search' ? find.byTooltip('Search') : find.text(action),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
  for (final state in [
    ModelLibraryStatus.ready,
    ModelLibraryStatus.empty,
    ModelLibraryStatus.error,
    ModelLibraryStatus.offline,
  ]) {
    testWidgets('Hub search renders $state without losing navigation', (
      tester,
    ) async {
      final library = _Library()
        ..status = state
        ..error = 'Search unavailable';
      if (state == ModelLibraryStatus.ready ||
          state == ModelLibraryStatus.offline) {
        library.results = [_model];
      }
      addTearDown(library.dispose);
      await _openSearch(tester, library);
      if (state == ModelLibraryStatus.ready ||
          state == ModelLibraryStatus.offline) {
        expect(find.text(_model.id), findsOneWidget);
      }
      if (state == ModelLibraryStatus.error)
        expect(find.text('Search unavailable'), findsOneWidget);
      if (state == ModelLibraryStatus.offline)
        expect(find.text('Showing cached results'), findsOneWidget);
      if (state == ModelLibraryStatus.empty)
        expect(find.text('Search public GGUF models'), findsOneWidget);
      await tester.tap(find.text('Installed'));
      await tester.pumpAndSettle();
      expect(find.text('Import Local GGUF'), findsOneWidget);
      expect(find.text('Open Model Folder'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading indicator clears when Hub results arrive', (
    tester,
  ) async {
    final library = _Library();
    addTearDown(library.dispose);
    await _openSearch(tester, library);
    library.status = ModelLibraryStatus.loading;
    library.notifyListeners();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    library.results = [_model];
    library.status = ModelLibraryStatus.ready;
    library.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(_model.id), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'search controls remain usable in landscape with keyboard space',
    (tester) async {
      tester.view.physicalSize = const Size(900, 450);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final library = _Library()
        ..results = [_model]
        ..status = ModelLibraryStatus.ready;
      addTearDown(library.dispose);
      await _openSearch(tester, library);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text(_model.id),
        100,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
