import 'dart:async';
import 'package:provider/provider.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/screens/home_screen.dart';
import 'package:vitalis_app/screens/chats_overview_screen.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/app_router.dart';

void main() {
  testWidgets('home lazily mounts destinations and retains conversation search', (
    tester,
  ) async {
    final history = _History();
    addTearDown(history.dispose);
    await _pump(tester, history, const HomeScreen());
    expect(find.text('Newest fixture'), findsOneWidget);
    // No model, safety, settings or saved providers are supplied: hidden pages must not initialize.
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search conversations'),
      'newest',
    );
    await tester.pumpAndSettle();
    expect(find.text('Older fixture'), findsNothing);
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);
    await tester.tap(find.text('Chats').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Search conversations'),
          )
          .controller!
          .text,
      'newest',
    );
    expect(history.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'read-only overview opens existing chat without creating or selecting a different model',
    (tester) async {
      final history = _History();
      addTearDown(history.dispose);
      await _pump(tester, history, const ChatsOverviewScreen());
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Older fixture'));
      await tester.pumpAndSettle();
      expect(history.selections, [2]);
      expect(find.text('Conversation destination'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delayed selection rejects duplicate opens and cannot navigate after dismissal',
    (tester) async {
      final history = _History()..selectionGate = Completer<void>();
      addTearDown(history.dispose);
      await _pump(tester, history, const ChatsOverviewScreen());
      final tap = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Older fixture'))
          .onTap!;
      tap();
      tap();
      await tester.pump();
      expect(history.selections, [2]);
      await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
      history.selectionGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Replacement'), findsOneWidget);
      expect(find.text('Conversation destination'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'load failure remains recoverable and does not disclose exception text',
    (tester) async {
      final history = _History()..loadFailure = StateError('/private/secret');
      addTearDown(history.dispose);
      await _pump(tester, history, const ChatsOverviewScreen());
      expect(find.text('Could not load conversations.'), findsOneWidget);
      expect(find.textContaining('/private'), findsNothing);
      history.loadFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(history.loads, 2);
      expect(find.text('Could not load conversations.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unrelated conversation error does not mark history loading failed',
    (tester) async {
      final history = _History()..generalError = true;
      addTearDown(history.dispose);
      await _pump(tester, history, const ChatsOverviewScreen());
      expect(find.text('Could not load conversations.'), findsNothing);
      expect(find.text('Newest fixture'), findsOneWidget);
    },
  );

  testWidgets('compact home supports large text and RTL without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = _History();
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: history),
          Provider<StartupAccessGuard>.value(
            value: StartupAccessGuard(
              () => const StartupCapabilities(
                databaseReady: true,
                migrationReady: true,
                safetyReady: true,
                modelReadiness: StartupModelReadiness.missing,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Newest fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a selected chat with a generation error remains openable for recovery',
    (tester) async {
      final history = _History()..generalError = true;
      history.currentChat = history.chats.first;
      addTearDown(history.dispose);
      await _pump(tester, history, const ChatsOverviewScreen());
      await tester.tap(find.text('Older fixture'));
      await tester.pumpAndSettle();
      expect(find.text('Conversation destination'), findsOneWidget);
      expect(history.selections, isEmpty);
    },
  );

  testWidgets('home route resolves to the conversation overview shell', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final route =
        onGenerateRoute(const RouteSettings(name: '/home'))
            as MaterialPageRoute;
    expect(route.builder(context).runtimeType.toString(), 'HomeScreen');
  });
}

Future<void> _pump(WidgetTester tester, _History history, Widget screen) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: history),
        Provider<StartupAccessGuard>.value(
          value: StartupAccessGuard(
            () => const StartupCapabilities(
              databaseReady: true,
              migrationReady: true,
              safetyReady: true,
              modelReadiness: StartupModelReadiness.missing,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        home: screen,
        routes: {
          AppRoutes.chat: (_) =>
              const Scaffold(body: Text('Conversation destination')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _History extends ChangeNotifier implements ChatProvider {
  int loads = 0;
  final selections = <int>[];
  Completer<void>? selectionGate;
  Object? loadFailure;
  bool generalError = false;
  @override
  final chats = [
    Chat(
      id: 2,
      title: 'Older fixture',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    Chat(
      id: 1,
      title: 'Newest fixture',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 10),
    ),
  ];
  @override
  Chat? currentChat;
  @override
  bool get hasError => generalError;
  bool get hasHistoryError => false;
  @override
  Future<void> loadChats() async {
    loads++;
    if (loadFailure != null) throw loadFailure!;
  }

  @override
  Future<void> selectChat(int id) async {
    selections.add(id);
    await selectionGate?.future;
    currentChat = chats.firstWhere((chat) => chat.id == id);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
