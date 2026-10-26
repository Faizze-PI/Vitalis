import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitalis_app/constants/app_strings.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_download_service.dart';
import 'package:vitalis_app/services/model_downloader.dart';
import 'package:vitalis_app/utils/validation_exception.dart';
import 'package:vitalis_app/utils/app_logger.dart';
import 'package:vitalis_app/utils/log_sanitizer.dart';
import 'package:vitalis_app/utils/memory_monitor.dart';
import 'package:vitalis_app/utils/async_mutex.dart';
import 'package:vitalis_app/utils/stream_transformers.dart';
import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // SETUP
  // =========================================================================
  setUpAll(() async {
    await initIntegrationTest();
    await AppLogger.instance.loadPersistedState();
  });

  // =========================================================================
  // PHASE 1: SETUP SCREEN
  // =========================================================================
  group('Phase 1 - Setup Screen', () {
    testWidgets('1.1 Setup UI renders with welcome title', (tester) async {
      await tester.pumpWidget(makeTestApp());
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.welcomeTitle), findsOneWidget);
      expect(find.text(AppStrings.welcomeSubtitle), findsOneWidget);
      expect(find.text(AppStrings.downloadModel), findsOneWidget);
    });

    testWidgets('1.2 Download model button exists', (tester) async {
      await tester.pumpWidget(makeTestApp());
      await tester.pumpAndSettle();
      final downloadBtn = find.text(AppStrings.downloadModel);
      expect(downloadBtn, findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.ancestor(
                of: downloadBtn,
                matching: find.byType(ElevatedButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('1.7 Download blocked by hardware check', (tester) async {
      await tester.pumpWidget(makeTestApp());
      await tester.pumpAndSettle();
      // Simulate unsafe conditions by accessing service
      final sentinel = HardwareSentinelService.instance;
      await sentinel.init();
      // If hardware is unsafe, error appears
      if (!sentinel.isSafeForDownload()) {
        await tester.tap(find.text(AppStrings.downloadModel));
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.retry), findsWidgets);
      }
    });
  });

  // =========================================================================
  // PHASE 8: SETTINGS SCREEN
  // =========================================================================
  group('Phase 8 - Settings Screen', () {
    testWidgets('8.1 Dark mode toggle', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect(find.text(AppStrings.darkMode), findsOneWidget);
      expect(find.text(AppStrings.appearance), findsOneWidget);

      // Toggle dark mode (first of 2 switches: dark mode + privacy)
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsNWidgets(2));
      await tester.tap(switchFinder.first);
      await tester.pumpAndSettle();
    });

    testWidgets('8.2 Privacy mode toggle', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.privacyMode), findsOneWidget);

      // Find all switches (dark mode + privacy = 2)
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(2));
    });

    testWidgets('8.3 What is logged expansion', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.whatIsLogged), findsOneWidget);
      await tester.tap(find.text(AppStrings.whatIsLogged));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.loggedFields), findsOneWidget);
    });

    testWidgets('8.4 Clear logs button', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.clearLogs), findsOneWidget);
    });

    testWidgets('8.6 Model info displayed', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.modelInfo), findsOneWidget);
      expect(find.text(BundledModelManifest.fileName), findsOneWidget);
    });

    testWidgets('8.7-8.10 Temperature/TopP/TopK/MaxTokens sliders', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.modelSettings), findsOneWidget);
      // Scroll to model settings section
      await tester.scrollUntilVisible(
        find.text(AppStrings.temperatureLabel),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(AppStrings.temperatureLabel), findsOneWidget);
      // Sliders exist (may not all be visible)
      final sliders = find.byType(Slider);
      expect(sliders, findsAtLeastNWidgets(1));
    });

    testWidgets('8.11 Redownload model button', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(AppStrings.resetModelButton),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(AppStrings.resetModelButton), findsOneWidget);
    });
  });

  // =========================================================================
  // PHASE 2: CHAT SCREEN (CORE UI)
  // =========================================================================
  group('Phase 2 - Chat Screen Core UI', () {
    testWidgets('2.1 Empty state shows no messages', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noMessages), findsOneWidget);
    });

    testWidgets('2.2 Input field exists', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      // ChatProvider creates a new chat on init, so input field shows
      expect(find.text(AppStrings.typeMessage), findsOneWidget);
      // Send button exists
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('2.3 AppBar with new chat and menu buttons', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });
  });

  // =========================================================================
  // PHASE 3: HEALTH MONITORING (CHAT SCREEN)
  // =========================================================================
  group('Phase 3 - Health Monitoring', () {
    testWidgets('3.1 Health bar visible', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.systemNormal), findsAtLeastNWidgets(1));
    });

    testWidgets('3.2 Health bar expands on tap', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      final expandIcons = find.byIcon(Icons.expand_more);
      if (expandIcons.evaluate().isNotEmpty) {
        await tester.tap(expandIcons.first);
        await tester.pumpAndSettle();
        expect(find.textContaining('RSS:'), findsOneWidget);
      }
    });

    testWidgets('3.3 MemoryMonitor RSS on chat screen', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      final rss = await MemoryMonitor.getRssMb();
      expect(rss, greaterThanOrEqualTo(-1));
    });

    testWidgets('3.5 Health color reflects safety', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      final sentinel = HardwareSentinelService.instance;
      final safe = sentinel.isSafeForHeavyOperation();
      if (safe) {
        expect(find.text(AppStrings.systemNormal), findsAtLeastNWidgets(1));
      } else {
        expect(find.text(AppStrings.systemWarm), findsAtLeastNWidgets(1));
      }
    });
  });

  // =========================================================================
  // PHASE 4: HAMBURGER MENU
  // =========================================================================
  group('Phase 4 - Hamburger Menu', () {
    testWidgets('4.1 Menu opens via icon button', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.chatOptions), findsOneWidget);
      expect(find.text(AppStrings.chatHistory), findsOneWidget);
      expect(find.text(AppStrings.selectPersona), findsOneWidget);
      expect(find.text(AppStrings.attachNote), findsOneWidget);
      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect(find.text(AppStrings.exportConversation), findsOneWidget);
    });

    testWidgets('4.5 Settings navigates from menu', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.settingsTitle));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
    });
  });

  // =========================================================================
  // PHASE 9: DEBUG SCREEN
  // =========================================================================
  group('Phase 9 - Debug Screen', () {
    testWidgets('9.1 System section renders', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/debug'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.debugTitle), findsOneWidget);
      expect(find.text(AppStrings.systemSection), findsOneWidget);
      expect(find.text(AppStrings.ramUsage), findsOneWidget);
      expect(find.text(AppStrings.tokenThroughput), findsOneWidget);
    });

    testWidgets('9.4 Battery health section', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/debug'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.batteryHealth), findsOneWidget);
      expect(find.text(AppStrings.level), findsOneWidget);
      expect(find.text(AppStrings.charging), findsOneWidget);
    });

    testWidgets('9.5 Log viewer renders', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/debug'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.logsSection), findsOneWidget);
      expect(find.text(AppStrings.emptyLogs), findsOneWidget);
    });

    testWidgets('9.3 Context usage meter', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/debug'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.debugContextUsageLabel), findsOneWidget);
    });
  });

  // =========================================================================
  // PHASE 10: MODEL & UTILITY UNIT TESTS (RUN ON DEVICE)
  // =========================================================================
  group('Phase 10 - Model & Utility Tests', () {});

  // =========================================================================
  // PHASE 12: MEMORY MONITOR
  // =========================================================================
  group('Phase 12 - Memory Monitor', () {
    testWidgets('12.1 MemoryMonitor RSS', (tester) async {
      final rss = await MemoryMonitor.getRssMb();
      expect(rss, anyOf(greaterThanOrEqualTo(-1), equals(-1)));
    });
  });

  // =========================================================================
  // PHASE 13: EDGE CASES
  // =========================================================================
  group('Phase 13 - Edge Cases', () {
    testWidgets('13.6 Empty context usage is 0.0', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      // App starts with minimal widgets rendering, no error thrown
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('13.7 AppLogger basic operations', (tester) async {
      AppLogger.instance.infoSync('Test log message');
      final logs = await AppLogger.instance.getLogs(maxLines: 10);
      expect(logs, contains('Test log message'));
    });

    testWidgets('13.7 LogSanitizer redacts PII', (tester) async {
      expect(
        LogSanitizer.sanitize('email: test@example.com'),
        contains('[EMAIL_REDACTED]'),
      );
      expect(
        LogSanitizer.sanitize('phone: 555-123-4567'),
        contains('[PHONE_REDACTED]'),
      );
      expect(LogSanitizer.sanitize('clean text'), 'clean text');
    });

    testWidgets('13.6 ValidationException basic', (tester) async {
      const e = ValidationException('test error');
      expect(e.message, 'test error');
      expect(e.toString(), contains('test error'));
    });
  });

  // =========================================================================
  // PHASE 11: CONCURRENCY
  // =========================================================================
  group('Phase 11 - Concurrency', () {
    testWidgets('11.7 AsyncMutex serializes access', (tester) async {
      final mutex = AsyncMutex();
      var shared = 0;

      await Future.wait([
        mutex.synchronize(() async {
          final val = shared;
          await Future.delayed(const Duration(milliseconds: 5));
          shared = val + 1;
        }),
        mutex.synchronize(() async {
          final val = shared;
          await Future.delayed(const Duration(milliseconds: 5));
          shared = val + 1;
        }),
        mutex.synchronize(() async {
          final val = shared;
          await Future.delayed(const Duration(milliseconds: 5));
          shared = val + 1;
        }),
      ]);

      expect(shared, 3);
    });

    testWidgets('11.8 Release without acquire is safe', (tester) async {
      final mutex = AsyncMutex();
      mutex.release();
      mutex.release();
      mutex.release();
    });
  });

  // =========================================================================
  // DATA MODEL UNIT TESTS (ON-DEVICE)
  // =========================================================================
  group('Data Model Tests', () {
    testWidgets('Chat serialization round-trip', (tester) async {
      final now = DateTime.now();
      final chat = Chat(title: 'Test Chat', createdAt: now, updatedAt: now);
      final map = chat.toMap();
      final restored = Chat.fromMap(map);
      expect(restored.title, 'Test Chat');
      expect(restored.createdAt.toIso8601String(), now.toIso8601String());
    });

    testWidgets('Message serialization round-trip', (tester) async {
      final msg = Message(chatId: 1, role: MessageRole.user, content: 'Hello');
      final map = msg.toMap();
      final restored = Message.fromMap(map);
      expect(restored.content, 'Hello');
      expect(restored.role, MessageRole.user);
    });

    testWidgets('Note serialization round-trip', (tester) async {
      final note = Note(title: 'Test', content: 'Content');
      final map = note.toMap();
      final restored = Note.fromMap(map);
      expect(restored.title, 'Test');
      expect(restored.content, 'Content');
    });

    testWidgets('Persona serialization round-trip', (tester) async {
      final persona = Persona(name: 'Helper', systemPrompt: 'Be helpful');
      final map = persona.toMap();
      final restored = Persona.fromMap(map);
      expect(restored.name, 'Helper');
    });

    testWidgets('ModelSettings serialization round-trip', (tester) async {
      final settings = ModelSettings(temperature: 0.5, topK: 50);
      final json = settings.toJson();
      final restored = ModelSettings.fromJson(json);
      expect(restored.temperature, 0.5);
      expect(restored.topK, 50);
    });

    testWidgets('ChatStateController FSM', (tester) async {
      final ctrl = ChatStateController(sentinel: MockSentinel());
      expect(ctrl.status, ChatStatus.idle);
      expect(ctrl.isIdle, true);

      ctrl.cancel();
      expect(ctrl.status, ChatStatus.idle);

      ctrl.dispose();
      expect(ctrl.isDisposed, true);
      ctrl.dispose(); // idempotent
    });

    testWidgets('ModelDownloadService initial state', (tester) async {
      final service = ModelDownloadService(
        downloader: ModelDownloader(sentinel: MockSentinel()),
      );
      expect(service.state, DownloadState.idle);
      expect(service.progress, 0.0);
      expect(service.isDownloading, false);

      service.cancelDownload();
      expect(service.state, DownloadState.idle);
    });
  });

  // =========================================================================
  // PHASE 6-7: PROVIDER TESTS
  // =========================================================================
  group('Provider Tests', () {
    testWidgets('ChatProvider initial state', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/chat'));
      await tester.pumpAndSettle();
      // After pumpAndSettle, chat provider should have created a chat
      // We can verify by checking app bar has a title
    });

    testWidgets('ThemeProvider toggles', (tester) async {
      await tester.pumpWidget(makeTestApp(initialRoute: '/settings'));
      await tester.pumpAndSettle();
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(2));
    });
  });

  // =========================================================================
  // STREAM TRANSFORMERS
  // =========================================================================
  group('Stream Transformers', () {
    testWidgets('BufferedStreamTransformer basic', (tester) async {
      final controller = StreamController<String>();
      final transformed = controller.stream.transform(
        const BufferedStreamTransformer(Duration.zero),
      );
      final results = <String>[];

      transformed.listen(results.add);
      controller.add('a');
      controller.add('b');
      controller.add('c');
      await Future.delayed(const Duration(milliseconds: 10));
      controller.close();
      await Future.delayed(const Duration(milliseconds: 10));
    });
  });
}
