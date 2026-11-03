import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

void main() {
  late Directory root;
  late ChatProvider chat;
  late WorkspaceFile file;
  late LocalFileWorkspace workspace;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp(
      'vitalis-chat-files-provider-',
    );
    await databaseFactory.setDatabasesPath(root.path);
    workspace = LocalFileWorkspace(
      root: () async => Directory('${root.path}/inputs'),
      availableBytes: () async => 1000000,
    );
    file = await workspace.import(
      name: 'fact.txt',
      expectedBytes: 4,
      source: Stream.value([102, 97, 99, 116]),
    );
    chat = ChatProvider(
      database: DatabaseHelper.instance,
      fileWorkspace: workspace,
    );
  });
  tearDown(() async {
    await chat.close();
    await DatabaseHelper.instance.close();
    await root.delete(recursive: true);
  });
  test(
    'file selection persists per chat and detaching preserves other chats',
    () async {
      await chat.createChat(title: 'First');
      final first = chat.currentChat!.id!;
      await chat.attachFile(file);
      await chat.attachFile(file);
      expect(chat.attachedFiles, hasLength(1));
      await chat.createChat(title: 'Second');
      expect(chat.attachedFiles, isEmpty);
      await chat.attachFile(file);
      await chat.selectChat(first);
      expect(chat.attachedFiles.single.name, 'fact.txt');
      await chat.detachFile(file.id);
      expect(chat.attachedFiles, isEmpty);
      expect(await DatabaseHelper.instance.fileAttachmentCount(file.id), 1);
    },
  );
  test(
    'selected files reach generation without being cleared after response',
    () async {
      final generation = _Generation();
      chat.setGenerationProvider(generation);
      await chat.createChat(title: 'Fixture');
      await chat.attachFile(file);
      expect(await chat.submitMessage('Read the file'), isTrue);
      expect(generation.files.single.id, file.id);
      expect(chat.attachedFiles.single.id, file.id);
    },
  );
  test('failed attachment write cannot publish a chip', () async {
    await chat.createChat(title: 'Fixture');
    await (await DatabaseHelper.instance.database).execute(
      "CREATE TEMP TRIGGER reject_file BEFORE INSERT ON chat_file_attachments BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );
    await expectLater(chat.attachFile(file), throwsA(anything));
    expect(chat.attachedFiles, isEmpty);
  });
  test('a removed copy cannot become a dangling chat attachment', () async {
    await chat.createChat(title: 'Fixture');
    await workspace.remove(file.id);
    await expectLater(
      chat.attachFile(file),
      throwsA(isA<WorkspaceImportException>()),
    );
    expect(chat.attachedFiles, isEmpty);
    expect(
      await DatabaseHelper.instance.getAttachedFiles(chat.currentChat!.id!),
      isEmpty,
    );
  });
}

final class _Generation implements GenerationProvider {
  List<WorkspaceFile> files = [];
  @override
  bool get isSending => false;
  @override
  void Function(String)? onGenerationComplete;
  @override
  void Function(String)? onError;
  @override
  Future<void> startGeneration({
    required List<Message> messages,
    required ModelSettings settings,
    Persona? persona,
    List<Note> attachedNotes = const [],
    List<WorkspaceFile> attachedFiles = const [],
  }) async {
    files = attachedFiles;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
