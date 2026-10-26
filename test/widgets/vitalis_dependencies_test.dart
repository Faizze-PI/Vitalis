import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/widgets/vitalis_dependencies.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';

void main() {
  testWidgets('dependency graph forwards committed persona changes to chat', (
    tester,
  ) async {
    late BuildContext scope;
    await tester.pumpWidget(
      VitalisDependencies(
        sentinel: _Sentinel(),
        child: Builder(
          builder: (context) {
            scope = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final chat = scope.read<ChatProvider>();
    final personas = scope.read<PersonaProvider>();
    final original = Persona(id: 7, name: 'Disposable', systemPrompt: 'Old');
    expect(await chat.setPersona(original), isTrue);
    expect(personas.onCommittedChange, isNotNull);
    personas.onCommittedChange!(7, original.copyWith(systemPrompt: 'New'));
    expect(chat.currentPersona?.systemPrompt, 'New');
    personas.onCommittedChange!(8, null);
    expect(chat.currentPersona?.id, 7);
    personas.onCommittedChange!(7, null);
    expect(chat.currentPersona, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('dependency graph exposes the selected model and live guard', (
    tester,
  ) async {
    final selected = SelectedModelReadiness(
      (_) async => StartupModelReadiness.missing,
    );
    final guard = StartupAccessGuard(
      () => StartupCapabilities(
        databaseReady: true,
        migrationReady: true,
        safetyReady: true,
        modelReadiness: selected.readiness,
      ),
    );
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      VitalisDependencies(
        sentinel: _Sentinel(),
        selectedModel: selected,
        startupAccess: guard,
        child: Builder(
          builder: (context) {
            expect(context.watch<SelectedModelReadiness>(), same(selected));
            expect(context.read<StartupAccessGuard?>(), same(guard));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(guard.snapshot().canInfer, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'dependency graph forwards current startup permissions to all content providers',
    (tester) async {
      late BuildContext scope;
      await tester.pumpWidget(
        VitalisDependencies(
          sentinel: _Sentinel(),
          startupAccess: StartupAccessGuard(
            () => const StartupCapabilities(
              databaseReady: false,
              migrationReady: false,
              safetyReady: false,
              modelReadiness: StartupModelReadiness.unknown,
            ),
          ),
          child: Builder(
            builder: (context) {
              scope = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await expectLater(
        scope.read<ChatProvider>().createChat(),
        throwsA(isA<StartupAccessDenied>()),
      );
      await expectLater(
        scope.read<NoteProvider>().loadNotes(),
        throwsA(isA<StartupAccessDenied>()),
      );
      await expectLater(
        scope.read<PersonaProvider>().loadPersonas(),
        throwsA(isA<StartupAccessDenied>()),
      );
      await expectLater(
        scope.read<GenerationProvider>().prepareModel(ModelSettings()),
        throwsA(isA<StartupAccessDenied>()),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unused scope does not create runtime dependencies', (
    tester,
  ) async {
    await tester.pumpWidget(
      VitalisDependencies(
        sentinel: _Sentinel(),
        createWarmup: (_, __) => throw StateError('Unexpected warmup creation'),
        createController: (_) =>
            throw StateError('Unexpected controller creation'),
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuild keeps one runtime service and controller', (
    tester,
  ) async {
    final sentinel = _Sentinel();
    final services = <ModelWarmupService>[];
    final controllers = <ChatStateController>[];
    final observed = <ModelWarmupService>[];
    addTearDown(() {
      for (final service in services) {
        service.dispose();
      }
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    Widget scope() => VitalisDependencies(
      sentinel: sentinel,
      createWarmup: (sentinel, registry) {
        final service = ModelWarmupService(
          sentinel: sentinel,
          modelRegistry: registry,
        );
        services.add(service);
        return service;
      },
      createController: (sentinel) {
        final controller = ChatStateController(sentinel: sentinel);
        controllers.add(controller);
        return controller;
      },
      child: Builder(
        builder: (context) {
          context.read<GenerationProvider>();
          observed.add(context.read<ModelWarmupService>());
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(scope());
    await tester.pumpWidget(scope());
    expect(services, hasLength(1));
    expect(controllers, hasLength(1));
    expect(observed.last, same(observed.first));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing scope starts owned runtime cleanup', (tester) async {
    final sentinel = _Sentinel();
    late ModelWarmupService service;
    late ChatStateController controller;
    late ModelRegistryService registry;
    await tester.pumpWidget(
      VitalisDependencies(
        sentinel: sentinel,
        createWarmup: (sentinel, registry) => service = ModelWarmupService(
          sentinel: sentinel,
          modelRegistry: registry,
        ),
        createController: (sentinel) =>
            controller = ChatStateController(sentinel: sentinel),
        child: Builder(
          builder: (context) {
            context.read<GenerationProvider>();
            context.read<ModelWarmupService>();
            registry = context.read<ModelRegistryService>();
            return const SizedBox();
          },
        ),
      ),
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(const SizedBox());
    expect(controller.isDisposed, isTrue);
    expect(service.isDisposed, isTrue);
    var closed = false;
    service.close().then((_) => closed = true);
    await tester.pump();
    expect(closed, isTrue);
    expect(service.requiresRecovery, isFalse);
    expect(sentinel.disposed, isFalse);
    Object? rejected;
    registry.importGguf().then<void>(
      (_) {},
      onError: (Object error, StackTrace _) => rejected = error,
    );
    await tester.pumpAndSettle();
    expect(rejected, isA<InferenceRepositoryDisposed>());
  });
}

final class _Sentinel implements HardwareSentinelService {
  bool disposed = false;
  @override
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  void checkHeavyOperation() {}
  @override
  void dispose() => disposed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
