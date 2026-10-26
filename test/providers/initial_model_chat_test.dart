import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';

void main() {
  final database = DatabaseHelper.instance;
  late Directory sandbox;
  late ChatProvider chat;
  late SelectedModelReadiness readiness;
  late _Registry registry;
  var safetyReady = true;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = await Directory.systemTemp.createTemp('vitalis_first_model_');
    await databaseFactory.setDatabasesPath(sandbox.path);
  });
  setUp(() async {
    await database.close();
    await databaseFactory.deleteDatabase(
      p.join(sandbox.path, AppConstants.databaseName),
    );
    safetyReady = true;
    registry = _Registry();
    readiness = SelectedModelReadiness(
      (id) async => id == 'disposable-model'
          ? StartupModelReadiness.ready
          : StartupModelReadiness.missing,
    );
    await readiness.select('missing-default');
    chat = ChatProvider(
      database: database,
      modelRegistry: registry,
      modelReadiness: readiness,
      startupAccess: StartupAccessGuard(
        () => StartupCapabilities(
          databaseReady: true,
          migrationReady: true,
          safetyReady: safetyReady,
          modelReadiness: readiness.readiness,
        ),
      ),
    );
  });
  tearDown(() async {
    await chat.close();
    readiness.dispose();
    await database.close();
  });
  tearDownAll(() async {
    await database.close();
    await sandbox.delete(recursive: true);
  });

  test(
    'explicit verified model starts the first chat from read-only recovery',
    () async {
      expect(chat.currentChat, isNull);
      await chat.switchModel('disposable-model');
      expect(chat.currentChat, isNotNull);
      expect(chat.settings.modelId, 'disposable-model');
      final chats = await database.getChats();
      expect(chats, hasLength(1));
      expect(
        (await database.getModelSettings(chats.single.id!))!['model_id'],
        'disposable-model',
      );
      expect(readiness.readiness, StartupModelReadiness.ready);
    },
  );

  test('first model chat requires established safety readiness', () async {
    safetyReady = false;
    await expectLater(
      chat.switchModel('disposable-model'),
      throwsA(isA<StartupAccessDenied>()),
    );
    expect(await database.getChats(), isEmpty);
    expect(chat.currentChat, isNull);
  });

  test(
    'failed settings persistence rolls back the new chat and readiness',
    () async {
      final db = await database.database;
      await db.execute(
        'CREATE TRIGGER reject_first_model BEFORE INSERT ON '
        'model_settings BEGIN SELECT RAISE(ABORT, "fixture failure"); END',
      );
      await expectLater(
        chat.switchModel('disposable-model'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.getChats(), isEmpty);
      expect(await db.query('model_settings'), isEmpty);
      expect(chat.currentChat, isNull);
      expect(readiness.readiness, StartupModelReadiness.missing);
    },
  );
  test(
    'recovery creates a new chat without changing saved chat settings',
    () async {
      final now = DateTime(2026).toIso8601String();
      final saved = await database.insertChat({
        'title': 'Saved fixture',
        'created_at': now,
        'updated_at': now,
      });
      await database.assignModelForChat(saved, 'missing-saved-model');
      final before = await database.getModelSettings(saved);
      await chat.switchModel('disposable-model');
      expect(await database.getChats(), hasLength(2));
      expect(chat.currentChat!.id, isNot(saved));
      expect(await database.getModelSettings(saved), before);
    },
  );

  test('duplicate first-model actions cannot create two chats', () async {
    registry.gate = Completer<void>();
    final first = chat.switchModel('disposable-model');
    final rejected = expectLater(
      chat.switchModel('disposable-model'),
      throwsStateError,
    );
    registry.gate!.complete();
    await first;
    await rejected;
    expect(registry.calls, 1);
    expect(await database.getChats(), hasLength(1));
  });

  test('disposal during verification cannot create a chat', () async {
    registry.gate = Completer<void>();
    final rejected = expectLater(
      chat.switchModel('disposable-model'),
      throwsStateError,
    );
    await chat.close();
    registry.gate!.complete();
    await rejected;
    expect(await database.getChats(), isEmpty);
  });

  test('unverified model cannot unlock recovery mutations', () async {
    registry.compatibility = 'unvalidated';
    await expectLater(chat.switchModel('disposable-model'), throwsStateError);
    expect(await database.getChats(), isEmpty);
    expect(readiness.readiness, StartupModelReadiness.missing);
  });

  test('revoked commit authorization rolls back both new records', () async {
    var checks = 0;
    final now = DateTime(2026).toIso8601String();
    await expectLater(
      database.insertChatWithModel(
        {'title': 'Revoked fixture', 'created_at': now, 'updated_at': now},
        'disposable-model',
        beforeCommit: () {
          if (++checks == 2) throw StateError('revoked');
        },
      ),
      throwsStateError,
    );
    expect(await database.getChats(), isEmpty);
    expect(await (await database.database).query('model_settings'), isEmpty);
  });
}

class _Registry implements ModelRegistryService {
  Completer<void>? gate;
  int calls = 0;
  String compatibility = 'compatible';
  @override
  Future<ModelDescriptor> requireInstalled(String id) async {
    calls++;
    await gate?.future;
    return ModelDescriptor(
      id: id,
      displayName: 'Disposable verified model',
      source: 'local_import',
      compatibilityStatus: compatibility,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected registry operation');
}
