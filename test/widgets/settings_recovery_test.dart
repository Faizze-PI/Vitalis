import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalis_app/utils/app_logger.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart' show InferenceRuntimeBusy;
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';
import 'package:vitalis_app/constants/app_strings.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/theme_provider.dart';
import 'package:vitalis_app/screens/settings_screen.dart';
import 'package:vitalis_app/services/model_download_service.dart';
import 'package:vitalis_app/services/model_downloader.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/models/chat.dart';

part 'settings_dialog_recovery_cases.dart';
part 'settings_mutation_recovery_cases.dart';
part 'settings_auto_reset_recovery_cases.dart';
part 'settings_preference_recovery_cases.dart';
part 'settings_model_reset_recovery_cases.dart';
part 'settings_log_recovery_cases.dart';

const _model = ModelDescriptor(
  id: 'imported-disposable',
  displayName: 'Disposable imported model',
  source: 'imported',
  compatibilityStatus: 'compatible',
  supportsThinking: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'privacy policy distinguishes local conversations from model networking',
    (tester) async {
      await _pump(tester, ready: true);
      await tester.tap(find.text(AppStrings.privacyPolicy));
      await tester.pumpAndSettle();
      final copy = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join('\n');
      expect(
        copy,
        contains(
          'Conversations, notes, personas, and settings stay on your device',
        ),
      );
      expect(copy, contains('Hugging Face'));
      expect(copy, contains('search text'));
      expect(copy, isNot(contains('No data is transmitted to any server')));
      expect(copy, contains('No cloud inference'));
    },
  );
  _registerDialogRecoveryCases();
  _registerSettingsMutationCases();
  _registerAutoResetCases();
  _registerPreferenceRecoveryCases();
  _registerModelResetCases();
  _registerLogRecoveryCases();

  testWidgets(
    'read-only advanced settings cannot change or reset the runtime',
    (tester) async {
      final fixture = await _pump(tester, ready: false, advanced: true);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.length, greaterThan(4));
      for (final slider in sliders) {
        expect(slider.onChanged, isNull);
        expect(slider.onChangeEnd, isNull);
      }
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Reset to Auto'),
            )
            .onPressed,
        isNull,
      );
      expect(fixture.chat.updates, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read-only Settings disables chat mutations, not recovery', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: false);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'System prompt'))
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<TuningMode>>(
            find.byType(DropdownButtonFormField<TuningMode>),
          )
          .onChanged,
      isNull,
    );
    for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
      expect(slider.onChanged, isNull);
    }
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'Import local GGUF model'),
          )
          .onTap,
      isNotNull,
    );
    expect(fixture.chat.updates, 0);
  });

  testWidgets('Settings import never activates or assigns the new model', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    await tester.tap(find.text('Import local GGUF model'));
    await tester.pumpAndSettle();
    expect(fixture.registry.imports, 1);
    expect(fixture.registry.activations, 0);
    expect(fixture.chat.updates, 0);
    expect(fixture.chat.settings.modelId, 'original-chat-model');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings import errors do not display private exception text', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: false);
    fixture.registry.failure = StateError(
      '/private/personal-model token=secret',
    );
    await tester.tap(find.text('Import local GGUF model'));
    await tester.pumpAndSettle();
    expect(find.textContaining('personal-model'), findsNothing);
    expect(find.textContaining('token=secret'), findsNothing);
    expect(
      find.text('Model import failed. Please retry in Model Library.'),
      findsOneWidget,
    );
    expect(fixture.chat.updates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings rejects repeated import while the picker is pending', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: false);
    final pending = Completer<ModelDescriptor?>();
    fixture.registry.pending = pending;
    final action = tester
        .widget<ListTile>(
          find.widgetWithText(ListTile, 'Import local GGUF model'),
        )
        .onTap!;
    action();
    action();
    await tester.pump();
    expect(fixture.registry.imports, 1);
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'Import local GGUF model'),
          )
          .onTap,
      isNull,
    );
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 0);
  });
}

Future<({_Registry registry, _Chat chat})> _pump(
  WidgetTester tester, {
  required bool ready,
  bool advanced = false,
  StartupAccessGuard? access,
  ModelWarmupService? runtime,
  ThemeProvider? appearance,
  ModelDownloadService? transfers,
  SelectedModelReadiness? readiness,
  AppLogger? logging,
}) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final guard =
      access ??
      StartupAccessGuard(
        () => StartupCapabilities(
          databaseReady: true,
          migrationReady: true,
          safetyReady: true,
          modelReadiness: ready
              ? StartupModelReadiness.ready
              : StartupModelReadiness.missing,
        ),
      );
  final registry = _Registry();
  final chat = _Chat(guard);
  if (advanced)
    chat.value = chat.value.copyWith(tuningMode: TuningMode.advanced);
  final warmup = runtime ?? _Warmup();
  final theme = appearance ?? ThemeProvider();
  final downloads =
      transfers ??
      ModelDownloadService(
        downloader: ModelDownloader(sentinel: _UnusedSafety()),
      );
  addTearDown(chat.dispose);
  addTearDown(theme.dispose);
  addTearDown(downloads.dispose);
  addTearDown(warmup.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<StartupAccessGuard?>.value(value: guard),
        if (readiness != null)
          ChangeNotifierProvider<SelectedModelReadiness>.value(
            value: readiness,
          ),
        Provider<ModelRegistryService>.value(value: registry),
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<ModelDownloadService>.value(value: downloads),
        ChangeNotifierProvider<ModelWarmupService>.value(value: warmup),
      ],
      child: MaterialApp(home: SettingsScreen(logger: logging)),
    ),
  );
  await tester.pumpAndSettle();
  return (registry: registry, chat: chat);
}

final class _Warmup extends ChangeNotifier implements ModelWarmupService {
  @override
  RuntimeProfile? get effectiveProfile => null;
  @override
  String? get fallbackReason => 'Presentation-only fixture';
  @override
  DateTime? get lastTunedAt => null;
  @override
  RuntimeTuningStatus get tuningStatus => RuntimeTuningStatus.idle;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected native operation in a presentation-only test',
  );
}

final class _UnusedSafety implements HardwareSentinelService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected telemetry in a presentation-only test');
}

final class _Registry extends ModelRegistryService {
  int imports = 0;
  int activations = 0;
  Object? failure;
  Completer<ModelDescriptor?>? pending;

  @override
  Future<ModelDescriptor?> findById(String id) async => _model;

  @override
  Future<ModelDescriptor?> importGguf() async {
    imports++;
    if (failure case final Object error) throw error;
    if (pending case final pending?) return pending.future;
    return _model;
  }

  @override
  Future<void> activate(ModelDescriptor model) async => activations++;
}

final class _Chat extends ChatProvider {
  _Chat(this.guard) : super(startupAccess: guard);
  final StartupAccessGuard guard;
  int updates = 0;
  int saveAttempts = 0;
  int previews = 0;
  Chat? selectedChat;
  Object? saveFailure;
  Completer<void>? pendingSave;
  ModelSettings value = ModelSettings(modelId: 'original-chat-model');

  @override
  ModelSettings get settings => value;

  @override
  Chat? get currentChat => selectedChat;

  @override
  void updateSettingsLocally(ModelSettings settings) {
    guard.require(StartupAccessOperation.mutateContent);
    previews++;
    value = settings;
    notifyListeners();
  }

  @override
  Future<void> updateSettings(ModelSettings settings) async {
    guard.require(StartupAccessOperation.mutateContent);
    saveAttempts++;
    await pendingSave?.future;
    if (saveFailure case final Object error) throw error;
    updates++;
    value = settings;
    notifyListeners();
  }
}
