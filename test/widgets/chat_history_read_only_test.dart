import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vitalis_app/constants/app_strings.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/chat_deletion_error.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/screens/modals/chat_history_modal.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';

StartupCapabilities _capabilities(bool ready) => StartupCapabilities(
  databaseReady: true,
  migrationReady: true,
  safetyReady: true,
  modelReadiness: ready
      ? StartupModelReadiness.ready
      : StartupModelReadiness.missing,
);

void main() {
  testWidgets('history reports committed deletion without suggesting retry', (
    tester,
  ) async {
    final guard = StartupAccessGuard(() => _capabilities(true));
    final history = _History(guard)
      ..failure = ChatDeletionError(deletionCommitted: true);
    addTearDown(history.dispose);
    await _pump(tester, history, guard);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Chat was deleted, but history could not be refreshed. Please reopen history.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('The change could not be saved. Please retry.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history never displays arbitrary private failure text', (
    tester,
  ) async {
    final guard = StartupAccessGuard(() => _capabilities(true));
    final history = _History(guard)
      ..failure = StateError('/private-secret/chat');
    addTearDown(history.dispose);
    await _pump(tester, history, guard);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();
    expect(find.textContaining('private-secret'), findsNothing);
    expect(
      find.text('The change could not be saved. Please retry.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history rejects repeated delete confirmation actions', (
    tester,
  ) async {
    final guard = StartupAccessGuard(() => _capabilities(true));
    final history = _History(guard);
    addTearDown(history.dispose);
    await _pump(tester, history, guard);
    final action = tester
        .widget<IconButton>(find.byType(IconButton))
        .onPressed!;
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    expect(history.deletions, 0);
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(history.deletions, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('read-only history disables deletion but keeps browsing', (
    tester,
  ) async {
    final guard = StartupAccessGuard(() => _capabilities(false));
    final history = _History(guard);
    addTearDown(history.dispose);
    await _pump(tester, history, guard);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Disposable chat'))
          .onTap,
      isNotNull,
    );
    expect(history.deletions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open history follows live mutation permission changes', (
    tester,
  ) async {
    var ready = true;
    final changes = _Signal();
    addTearDown(changes.dispose);
    final guard = StartupAccessGuard(
      () => _capabilities(ready),
      changes: changes,
    );
    final history = _History(guard);
    addTearDown(history.dispose);
    await _pump(tester, history, guard);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
    ready = false;
    changes.emit();
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(history.deletions, 0);
  });

  testWidgets('permission revoked during confirmation preserves the chat', (
    tester,
  ) async {
    var ready = true;
    final guard = StartupAccessGuard(() => _capabilities(ready));
    final history = _History(guard);
    addTearDown(history.dispose);
    await _pump(tester, history, guard);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    ready = false;
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();
    expect(history.deletions, 0);
    expect(history.chats, hasLength(1));
    expect(tester.takeException(), isNull);
    expect(
      find.text('Editing is unavailable while the app is recovering.'),
      findsOneWidget,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  _History history,
  StartupAccessGuard guard,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<StartupAccessGuard?>.value(value: guard),
        ChangeNotifierProvider<ChatProvider>.value(value: history),
      ],
      child: const MaterialApp(home: Scaffold(body: ChatHistoryModal())),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Signal extends ChangeNotifier {
  void emit() => notifyListeners();
}

final class _History extends ChatProvider {
  _History(this.guard) : super(startupAccess: guard);

  final StartupAccessGuard guard;
  int deletions = 0;
  Object? failure;
  final List<Chat> records = [
    Chat(
      id: 1,
      title: 'Disposable chat',
      createdAt: DateTime(2026, 10, 13),
      updatedAt: DateTime(2026, 10, 13),
    ),
  ];

  @override
  List<Chat> get chats => List.unmodifiable(records);

  @override
  Future<void> deleteChat(int id) async {
    guard.require(StartupAccessOperation.mutateContent);
    if (failure case final Object error) throw error;
    deletions++;
    records.removeWhere((chat) => chat.id == id);
    notifyListeners();
  }
}
