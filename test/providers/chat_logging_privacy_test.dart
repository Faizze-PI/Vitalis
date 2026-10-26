import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/persistence_policy.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/utils/app_logger.dart';

const privateMarker = 'PRIVATE_CHAT_BOUND_VALUE_FIXTURE';

void main() {
  for (final privacy in [true, false]) {
    for (final operation in [
      'list',
      'history',
      'send',
      'rename',
      'setPersona',
      'removePersona',
      'create',
    ]) {
      test(
        'chat $operation excludes exception text privacy=$privacy',
        () async {
          final parent = await Directory.systemTemp.resolveSymbolicLinks();
          final root = await Directory(parent).createTemp('vitalis_chat_logs_');
          final owned = await root.resolveSymbolicLinks();
          if (!owned.startsWith('$parent${Platform.pathSeparator}')) {
            throw StateError('Log fixture escaped temporary parent');
          }
          final logger = AppLogger.forTesting(
            directoryResolver: () async => root,
            privacyLoader: () async => privacy,
            privacySaver: (_) async {},
            clock: () => DateTime.utc(2026, 10, 25),
          );
          final provider = ChatProvider(
            database: _Database(operation),
            logger: logger,
          );
          addTearDown(() async {
            provider.dispose();
            await logger.flush();
            if (await root.resolveSymbolicLinks() != owned) {
              throw StateError('Log fixture ownership changed');
            }
            await root.delete(recursive: true);
          });
          await logger.loadPersistedState();
          if (operation != 'list' && operation != 'create')
            await provider.selectChat(1);
          switch (operation) {
            case 'list':
              await provider.loadChats();
            case 'history':
              await provider.loadOlderMessages();
            case 'send':
              await provider.sendMessage(privateMarker);
            case 'rename':
              await provider.updateChatTitle(1, 'Disposable');
            case 'setPersona':
              await provider.setPersona(
                Persona(id: 1, name: 'Disposable', systemPrompt: privateMarker),
              );
            case 'removePersona':
              await provider.removePersona();
            case 'create':
              await provider.createChat(title: 'Disposable');
          }
          await logger.flush();
          final logs = await logger.getLogs();
          expect(logs, contains('[ERROR]'));
          expect(logs, contains('_ChatLogFailure'));
          final files = await root
              .list(recursive: true)
              .where((item) => item is File)
              .cast<File>()
              .toList();
          expect(files, isNotEmpty);
          for (final file in files) {
            expect(await file.readAsString(), isNot(contains(privateMarker)));
          }
          expect(logs, isNot(contains(privateMarker)));
        },
      );
    }
  }
}

final class _ChatLogFailure implements Exception {
  @override
  String toString() => '_ChatLogFailure SQL boundValues=[$privateMarker]';
}

final class _Database implements DatabaseHelper {
  _Database(this.operation);
  final String operation;
  @override
  Future<Chat?> getChat(int id) async => Chat(
    id: id,
    title: 'Disposable',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  @override
  Future<List<Message>> getMessagesForChatPaginated(
    int id, {
    int limit = 50,
    int? beforeId,
  }) async {
    if (beforeId != null) throw _ChatLogFailure();
    return operation == 'history'
        ? List.generate(
            PaginationPolicy.messagePageSize,
            (index) => Message(
              id: index + 1,
              chatId: id,
              role: MessageRole.assistant,
              content: 'Disposable prior response',
            ),
          )
        : [];
  }

  @override
  Future<List<Note>> getAttachedNotes(int id) async => [];
  @override
  Future<Map<String, dynamic>?> getModelSettings(int id) async => null;
  @override
  Future<int?> getChatPersona(int id) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw _ChatLogFailure();
}
