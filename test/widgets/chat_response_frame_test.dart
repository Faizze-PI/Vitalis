import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/providers/health_provider.dart';
import 'package:vitalis_app/providers/theme_provider.dart';
import 'package:vitalis_app/screens/chat_screen.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/services/response_frame_timing.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:vitalis_app/widgets/message_bubble.dart';
import 'package:vitalis_app/constants/app_strings.dart';

void main() {
  test(
    'delayed attachment removal cannot change a newly selected chat',
    () async {
      final note = Note(id: 1, title: 'Shared note', content: 'Test');
      final database = _Database()
        ..chatNotes[1] = [note]
        ..chatNotes[2] = [note]
        ..detachGate = Completer<void>();
      final chat = ChatProvider(database: database);
      addTearDown(chat.dispose);
      await chat.selectChat(1);
      final removing = chat.clearAttachedNote(note);
      await chat.selectChat(2);
      database.detachGate!.complete();
      await removing;
      expect(database.chatNotes[1], isEmpty);
      expect(database.chatNotes[2]!.map((note) => note.id), [1]);
      expect(chat.attachedNotes.map((note) => note.id), [1]);
    },
  );

  testWidgets(
    'failed attachment removal preserves both notes and reports a redacted error',
    (tester) async {
      final database = _Database()
        ..notes.addAll([
          Note(id: 1, title: 'First', content: 'A'),
          Note(id: 2, title: 'Second', content: 'B'),
        ])
        ..detachFailure = StateError('Private fixture failure');
      final chat = await _pumpChat(tester, database);
      await tester.tap(find.byTooltip('Remove attached note: First'));
      await tester.pumpAndSettle();
      expect(chat.attachedNotes, hasLength(2));
      expect(
        find.text('The note could not be detached. Please retry.'),
        findsOneWidget,
      );
      expect(find.textContaining('Private fixture failure'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed export does not replace the clipboard or report success',
    (tester) async {
      final database = _Database()
        ..exportFailure = StateError('Private export failure');
      var clipboardWrites = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardWrites++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pumpChat(tester, database);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.exportConversation));
      await tester.pumpAndSettle();
      expect(clipboardWrites, 0);
      expect(
        find.text('Conversation could not be copied. Please retry.'),
        findsOneWidget,
      );
      expect(find.textContaining('Private export failure'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('export copies stored history beyond the loaded page', (
    tester,
  ) async {
    final database = _Database();
    database.rows
      ..clear()
      ..addAll(
        List.generate(
          130,
          (index) => Message(
            id: index + 1,
            chatId: 1,
            role: index.isEven ? MessageRole.user : MessageRole.assistant,
            content: 'Export fixture ${index + 1}',
          ),
        ),
      );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final chat = await _pumpChat(tester, database);
    expect(chat.messages, hasLength(100));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.exportConversation));
    await tester.pumpAndSettle();
    expect(copied, contains('Export fixture 1\n'));
    expect(copied, contains('Export fixture 130\n'));
    expect(RegExp(r'Export fixture \d+\n').allMatches(copied!), hasLength(130));
    expect(chat.messages, hasLength(100));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'each attachment is visible and removal preserves its neighbour',
    (tester) async {
      final database = _Database()
        ..notes.addAll([
          Note(id: 1, title: 'First test note', content: 'Alpha'),
          Note(id: 2, title: 'Second test note', content: 'Beta'),
        ]);
      final chat = await _pumpChat(tester, database);
      expect(find.text('Note: First test note'), findsOneWidget);
      expect(find.text('Note: Second test note'), findsOneWidget);
      await tester.ensureVisible(
        find.byTooltip('Remove attached note: First test note'),
      );
      await tester.tap(find.byTooltip('Remove attached note: First test note'));
      await tester.pumpAndSettle();
      expect(chat.attachedNotes.map((note) => note.id), [2]);
      expect(database.notes.map((note) => note.id), [2]);
      expect(find.text('Note: Second test note'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('attached note text has readable contrast in $brightness', (
      tester,
    ) async {
      final database = _Database()
        ..notes.add(Note(id: 1, title: 'Contrast note', content: 'Test'));
      await _pumpChat(tester, database, brightness: brightness);
      final label = find.text('Note: Contrast note');
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final foreground = paragraph.text.style!.color!;
      final chips = find.ancestor(of: label, matching: find.byType(InputChip));
      final background = chips.evaluate().isNotEmpty
          ? tester.widget<InputChip>(chips).backgroundColor!
          : tester
                .widgetList<Container>(
                  find.ancestor(of: label, matching: find.byType(Container)),
                )
                .firstWhere((container) => container.color != null)
                .color!;
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      final contrast =
          (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final completeBeforeFrame in [false, true]) {
    testWidgets(
      'ChatScreen records ${completeBeforeFrame ? 'saved' : 'streamed'} response paint',
      (tester) async {
        final chat = ChatProvider(database: _Database());
        final generation = _Generation();
        final health = _Health();
        final warmup = _Warmup();
        final readiness = SelectedModelReadiness(
          (_) async => StartupModelReadiness.ready,
        );
        addTearDown(chat.dispose);
        addTearDown(generation.dispose);
        addTearDown(health.dispose);
        addTearDown(warmup.dispose);
        addTearDown(readiness.dispose);
        await chat.selectChat(1);
        chat.setGenerationProvider(generation);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatProvider>.value(value: chat),
              ChangeNotifierProvider<GenerationProvider>.value(
                value: generation,
              ),
              ChangeNotifierProvider<HealthProvider>.value(value: health),
              ChangeNotifierProvider<ModelWarmupService>.value(value: warmup),
              ChangeNotifierProvider<SelectedModelReadiness>.value(
                value: readiness,
              ),
              Provider<StartupAccessGuard?>.value(value: null),
            ],
            child: const MaterialApp(home: ChatScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(generation.lastResponseFrameTiming, isNull);
        generation.clock = 100;
        generation.begin();
        generation.clock = 140;
        generation.receive('Disposable generated response');
        expect(
          generation.lastResponseFrameTiming!.firstRenderedFrameMicros,
          isNull,
        );
        if (completeBeforeFrame) {
          generation.finish();
          await chat.drainPendingPersistence();
          expect(chat.messages.last.content, 'Disposable generated response');
        }
        generation.clock = 170;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widgetList<MessageBubble>(find.byType(MessageBubble))
              .where(
                (bubble) =>
                    bubble.message.content == 'Disposable generated response',
              ),
          hasLength(1),
        );
        expect(generation.lastResponseFrameTiming!.firstReceivedTextMicros, 40);
        expect(
          generation.lastResponseFrameTiming!.firstRenderedFrameMicros,
          70,
        );
        generation.clock = 900;
        generation.refresh();
        await tester.pumpAndSettle();
        expect(
          generation.lastResponseFrameTiming!.firstRenderedFrameMicros,
          70,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<ChatProvider> _pumpChat(
  WidgetTester tester,
  _Database database, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeProvider();
  addTearDown(theme.dispose);
  final chat = ChatProvider(database: database);
  final generation = _Generation();
  final health = _Health();
  final warmup = _Warmup();
  final readiness = SelectedModelReadiness(
    (_) async => StartupModelReadiness.ready,
  );
  addTearDown(chat.dispose);
  addTearDown(generation.dispose);
  addTearDown(health.dispose);
  addTearDown(warmup.dispose);
  addTearDown(readiness.dispose);
  await chat.selectChat(1);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider<GenerationProvider>.value(value: generation),
        ChangeNotifierProvider<HealthProvider>.value(value: health),
        ChangeNotifierProvider<ModelWarmupService>.value(value: warmup),
        ChangeNotifierProvider<SelectedModelReadiness>.value(value: readiness),
        Provider<StartupAccessGuard?>.value(value: null),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return chat;
}

final class _Generation extends ChangeNotifier implements GenerationProvider {
  int clock = 0;
  late final timing = ResponseFrameTimingTracker(() => clock);
  bool sending = false;
  String text = '';
  @override
  void Function(String)? onGenerationComplete;
  @override
  void Function(String)? onError;
  void begin() {
    timing.begin();
    sending = true;
  }

  void receive(String value) {
    text = value;
    timing.receivedText();
    notifyListeners();
  }

  void finish() {
    sending = false;
    onGenerationComplete?.call(text);
    notifyListeners();
  }

  void refresh() => notifyListeners();
  @override
  bool get isSending => sending;
  @override
  String get streamText => sending ? text : '';
  @override
  ChatStatus get chatStatus =>
      sending ? ChatStatus.generating : ChatStatus.idle;
  @override
  int get lastTokenCount => 0;
  @override
  double get lastTps => 0;
  @override
  double get lastContextUsage => 0;
  @override
  bool get showTruncationWarning => false;
  @override
  Object? get responseFrameIdentity => timing.identity;
  @override
  ResponseFrameTiming? get lastResponseFrameTiming => timing.snapshot;
  @override
  void recordResponseFrame(Object identity) => timing.recordFrame(identity);
  @override
  void abandonResponseFrameObservation() => timing.invalidate();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected generation fixture call: ${invocation.memberName}',
  );
}

final class _Health extends ChangeNotifier implements HealthProvider {
  @override
  bool get isSafeForHeavy => true;
  @override
  int get rssMb => 0;
  @override
  int get batteryLevel => 100;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected health fixture call: ${invocation.memberName}',
  );
}

final class _Warmup extends ChangeNotifier implements ModelWarmupService {
  @override
  bool get isWarmedUp => true;
  @override
  bool get isWarmingUp => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected warmup fixture call: ${invocation.memberName}',
  );
}

final class _Database implements DatabaseHelper {
  final notes = <Note>[];
  final chatNotes = <int, List<Note>>{};
  Completer<void>? detachGate;
  Object? detachFailure;
  Object? exportFailure;
  final rows = [
    Message(
      id: 1,
      chatId: 1,
      role: MessageRole.assistant,
      content: 'Disposable prior response',
    ),
  ];
  @override
  Future<Chat?> getChat(int id) async => Chat(
    id: id,
    title: 'Disposable chat',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  @override
  Future<List<Chat>> getChats() async => [(await getChat(1))!];
  @override
  Future<List<Message>> getMessagesForChatPaginated(
    int chatId, {
    int limit = 50,
    int? beforeId,
  }) async {
    final selected = rows
        .where(
          (row) =>
              row.chatId == chatId && (beforeId == null || row.id! < beforeId),
        )
        .toList();
    return selected.length <= limit
        ? selected
        : selected.sublist(selected.length - limit);
  }

  @override
  Future<List<Message>> getAllMessagesForExport(int chatId) async {
    if (exportFailure case final Object error) throw error;
    return rows.where((row) => row.chatId == chatId).toList();
  }

  @override
  Future<List<Note>> getAttachedNotes(int chatId) async =>
      List.of(chatNotes[chatId] ?? notes);
  @override
  Future<void> detachNote(int chatId, int noteId) async {
    await detachGate?.future;
    if (detachFailure case final Object error) throw error;
    (chatNotes[chatId] ?? notes).removeWhere((note) => note.id == noteId);
  }

  @override
  Future<Map<String, dynamic>?> getModelSettings(int chatId) async => null;
  @override
  Future<int?> getChatPersona(int chatId) async => null;
  @override
  Future<int> insertMessage(Map<String, dynamic> message) async {
    final id = rows.length + 1;
    rows.add(Message.fromMap({...message, 'id': id}));
    return id;
  }

  @override
  Future<int> updateChat(int id, Map<String, dynamic> values) async => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected database fixture call: ${invocation.memberName}',
  );
}
