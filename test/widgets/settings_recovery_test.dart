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
      await _pump(tester, ready: true, appSettings: true);
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
      expect(copy, isNot(contains('support@vitalis.app')));
    },
  );
  testWidgets(
    'app Settings hides controls that would edit the current conversation',
    (tester) async {
      final fixture = await _pump(tester, ready: true, appSettings: true);
      expect(find.text(AppStrings.appearance), findsOneWidget);
      expect(find.text(AppStrings.privacy), findsOneWidget);
      expect(find.text('System prompt'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('Thinking mode'), findsNothing);
      expect(fixture.chat.updates, 0);
    },
  );

  testWidgets('chat Settings excludes app preferences and global model reset', (
    tester,
  ) async {
    await _pump(tester, ready: true);
    expect(find.text('Chat settings'), findsOneWidget);
    expect(find.text('System prompt'), findsOneWidget);
    expect(find.text(AppStrings.appearance), findsNothing);
    expect(find.text(AppStrings.privacy), findsNothing);
    expect(find.text('Import local GGUF model'), findsNothing);
    expect(find.text(AppStrings.resetModelButton), findsNothing);
  });

  testWidgets(
    'changing model cannot borrow the previous template thinking capability',
    (tester) async {
      final fixture = await _pump(tester, ready: true);
      final finder = find.widgetWithText(SwitchListTile, 'Thinking mode');
      expect(tester.widget<SwitchListTile>(finder).onChanged, isNotNull);
      final pending = Completer<ModelDescriptor?>();
      fixture.registry.lookupGate = pending;
      fixture.chat.value = fixture.chat.value.copyWith(
        modelId: 'unverified-template',
      );
      fixture.chat.notifyListeners();
      await tester.pump();
      expect(tester.widget<SwitchListTile>(finder).onChanged, isNull);
      pending.complete(
        const ModelDescriptor(
          id: 'unverified-template',
          displayName: 'Unknown template',
          source: 'imported',
          compatibilityStatus: 'unknown',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(finder).onChanged, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chat Settings without a selected conversation cannot edit defaults',
    (tester) async {
      final fixture = await _pump(tester, ready: true);
      fixture.chat.selectedChat = null;
      fixture.chat.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a conversation to edit its settings.'),
        findsOneWidget,
      );
      expect(find.text('System prompt'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(fixture.chat.updates, 0);
    },
  );

  testWidgets(
    'chat Settings supports narrow large-text layouts without truncating metadata',
    (tester) async {
      await _pump(
        tester,
        ready: true,
        viewSize: const Size(320, 1800),
        textScale: 2,
      );
      expect(find.text(_model.displayName), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in <String, ModelSettings Function(ModelSettings)>{
    'output above the legacy ceiling': (value) =>
        value.copyWith(maxTokens: 8192),
    'short output request': (value) => value.copyWith(maxTokens: 1),
    'temperature above the legacy ceiling': (value) =>
        value.copyWith(temperature: 3),
    'top-k above the legacy ceiling': (value) => value.copyWith(topK: 256),
    'unrestricted top-k': (value) => value.copyWith(topK: 0),
  }.entries) {
    testWidgets('stored ${entry.key} remains visible and editable', (
      tester,
    ) async {
      final fixture = await _pump(tester, ready: true);
      final stored = entry.value(fixture.chat.value);
      fixture.chat.value = stored;
      fixture.chat.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.somethingWentWrong), findsNothing);
      expect(find.text('System prompt'), findsOneWidget);
      expect(fixture.chat.settings, same(stored));
      expect(fixture.chat.updates, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'numeric editor retains rejected input then commits only the selected setting',
    (tester) async {
      final fixture = await _pump(tester, ready: true);
      await tester.tap(
        find.widgetWithText(ListTile, AppStrings.maxTokensLabel),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a whole number greater than zero.'),
        findsOneWidget,
      );
      expect(fixture.chat.saveAttempts, 0);
      await tester.enterText(find.byType(TextField), '8192');
      fixture.chat.value = fixture.chat.value.copyWith(topP: 0.5);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(fixture.chat.settings.maxTokens, 8192);
      expect(fixture.chat.settings.topP, 0.5);
      expect(fixture.chat.updates, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'numeric presets only fill a draft and Cancel preserves saved values',
    (tester) async {
      final fixture = await _pump(tester, ready: true);
      final original = fixture.chat.settings;
      await tester.tap(
        find.widgetWithText(ListTile, AppStrings.maxTokensLabel),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '4096'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '4096',
      );
      expect(fixture.chat.saveAttempts, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.chat.settings, same(original));
    },
  );

  testWidgets('numeric save failure keeps the draft for a redacted retry', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    fixture.chat.saveFailure = StateError('/private/token=secret');
    await tester.tap(
      find.widgetWithText(ListTile, AppStrings.temperatureLabel),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('The change could not be saved. Your draft is retained.'),
      findsOneWidget,
    );
    expect(find.textContaining('/private'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '3',
    );
    fixture.chat.saveFailure = null;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fixture.chat.settings.temperature, 3);
    expect(fixture.chat.updates, 1);
  });

  testWidgets('an old numeric editor cannot save into a different chat', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    await tester.tap(find.widgetWithText(ListTile, AppStrings.topKLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '256');
    fixture.chat.selectedChat = Chat(
      id: 2,
      title: 'Different fixture',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fixture.chat.saveAttempts, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '256',
    );
    expect(
      find.text('The change could not be saved. Your draft is retained.'),
      findsOneWidget,
    );
  });

  for (final label in [AppStrings.topKLabel, 'System prompt']) {
    testWidgets(
      'a stale $label action cannot open an editor for a newly selected chat',
      (tester) async {
        final fixture = await _pump(tester, ready: true);
        final open = tester
            .widget<ListTile>(find.widgetWithText(ListTile, label))
            .onTap!;
        fixture.chat.selectedChat = Chat(
          id: 2,
          title: 'Different fixture',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        open();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.chat.saveAttempts, 0);
      },
    );
  }

  testWidgets(
    'invalid stored probability shows corrective guidance without discarding it',
    (tester) async {
      final fixture = await _pump(tester, ready: true);
      fixture.chat.value = fixture.chat.value.copyWith(topP: 1.2);
      fixture.chat.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a probability from zero to one.'),
        findsOneWidget,
      );
      expect(fixture.chat.settings.topP, 1.2);
      expect(fixture.chat.saveAttempts, 0);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, AppStrings.topPLabel),
            )
            .onTap,
        isNotNull,
      );
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
      expect(sliders, hasLength(3));
      for (final label in [
        'Context tokens',
        'CPU threads',
        'Prompt batch size',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in [
        AppStrings.temperatureLabel,
        AppStrings.topPLabel,
        AppStrings.topKLabel,
        AppStrings.maxTokensLabel,
      ]) {
        expect(
          tester.widget<ListTile>(find.widgetWithText(ListTile, label)).onTap,
          isNull,
        );
      }
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
    expect(find.text('Import local GGUF model'), findsNothing);
    final app = await _pump(tester, ready: false, appSettings: true);
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'Import local GGUF model'),
          )
          .onTap,
      isNotNull,
    );
    expect(app.chat.updates, 0);
    expect(fixture.chat.updates, 0);
  });

  testWidgets('Settings import never activates or assigns the new model', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true, appSettings: true);
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
    final fixture = await _pump(tester, ready: false, appSettings: true);
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
    final fixture = await _pump(tester, ready: false, appSettings: true);
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
  bool appSettings = false,
  StartupAccessGuard? access,
  ModelWarmupService? runtime,
  ThemeProvider? appearance,
  ModelDownloadService? transfers,
  SelectedModelReadiness? readiness,
  AppLogger? logging,
  Size? viewSize,
  double textScale = 1,
}) async {
  tester.view.physicalSize = viewSize ?? const Size(1100, 2600);
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
  final chat = _Chat(guard)
    ..selectedChat = Chat(
      id: 1,
      title: 'Fixture chat',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
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
        if (!appSettings)
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<ModelDownloadService>.value(value: downloads),
        ChangeNotifierProvider<ModelWarmupService>.value(value: warmup),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: appSettings
            ? SettingsScreen(logger: logging)
            : SettingsScreen.chat(logger: logging),
      ),
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
  Completer<ModelDescriptor?>? lookupGate;

  @override
  Future<ModelDescriptor?> findById(String id) async =>
      lookupGate == null ? _model : lookupGate!.future;

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
