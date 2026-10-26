import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/providers/chat_provider.dart';

void main() {
  test(
    'history failures clear independently of unrelated chat errors on retry',
    () async {
      final database = _Database();
      final provider = ChatProvider(database: database);
      addTearDown(provider.close);
      await provider.updateChatTitle(1, 'x' * 257);
      expect(provider.hasError, isTrue);
      await provider.loadChats();
      expect(provider.hasHistoryError, isFalse);
      database.fail = true;
      await provider.loadChats();
      expect(provider.hasHistoryError, isTrue);
      database.fail = false;
      await provider.loadChats();
      expect(provider.hasHistoryError, isFalse);
      expect(provider.chats, hasLength(1));
    },
  );
}

class _Database implements DatabaseHelper {
  bool fail = false;
  @override
  Future<List<Chat>> getChats() async {
    if (fail) throw StateError('fixture storage failure');
    return [
      Chat(
        id: 1,
        title: 'Fixture',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
