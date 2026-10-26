// ARCHITECTURE: ChatProvider is the central state manager for chat operations.
// It handles CRUD for chats, messages, settings, personas, and note attachments.
// Injection: Uses DatabaseHelper.instance directly (no ChatRepository).
// State: chats, messages, settings, persona, attachedNote, generatingContent.
// Dependencies: GenerationProvider (set via setGenerationProvider()).
// Note: AppLogger and HardwareSentinelService remain singletons.
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat.dart';
import '../models/chat_deletion_error.dart';
import '../models/message.dart';
import '../models/persona.dart';
import '../models/note.dart';
import '../models/model_settings.dart';
import '../models/startup_capabilities.dart';
import '../models/persistence_policy.dart';
import '../database/database_helper.dart';
import '../utils/app_logger.dart';
import '../utils/text_limits.dart';
import '../constants/app_constants.dart';
import '../constants/app_strings.dart';
import '../services/model_registry_service.dart';
import '../services/startup_access_guard.dart';
import '../services/selected_model_readiness.dart';
import 'generation_provider.dart';

part 'chat_settings_persistence.dart';

class ChatProvider extends ChangeNotifier {
  final DatabaseHelper _db;
  final AppLogger _logger;
  final ModelRegistryService _modelRegistry;
  final StartupAccessGuard? _startupAccess;
  final SelectedModelReadiness? _modelReadiness;

  ChatProvider({
    DatabaseHelper? database,
    ModelRegistryService? modelRegistry,
    StartupAccessGuard? startupAccess,
    SelectedModelReadiness? modelReadiness,
    AppLogger? logger,
  }) : _db = database ?? DatabaseHelper.instance,
       _logger = logger ?? AppLogger.instance,
       _startupAccess = startupAccess,
       _modelReadiness = modelReadiness,
       _modelRegistry =
           modelRegistry ?? ModelRegistryService(database: database);

  List<Chat> _chats = [];
  Chat? _currentChat;
  List<Message> _messages = [];
  // Weak metadata follows each saved message, not save-completion order.
  final _responseFrameIdentities = Expando<Object>();
  bool _isLoading = false;
  bool _hasHistoryError = false;
  bool _hasError = false;
  String _errorMessage = '';
  ModelSettings _settings = ModelSettings();
  ModelSettings _committedSettings = ModelSettings();
  Future<void> _settingsWriteTail = Future<void>.value();
  int _settingsRevision = 0;
  int _settingsWriteFailures = 0;
  Persona? _currentPersona;
  int _personaRevision = 0;
  final _personaWrites = <int?, Future<void>>{};
  List<Note> _attachedNotes = [];
  bool _hasOlderMessages = false;
  double _cachedContextUsage = 0.0;
  bool _contextUsageCacheStale = true;

  GenerationProvider? _generation;
  bool _isDisposed = false;
  int _selectionEpoch = 0;
  final _pendingCompletionSaves = <Future<void>>{};
  final _pendingChatDeletions = <int, Future<void>>{};
  final _deletionSettlements = <Future<void>>{};
  int _deletionFailures = 0;
  Future<void>? _closeFuture;
  bool _modelSwitchInProgress = false;

  void _requireAccess(
    StartupAccessOperation operation, {
    bool allowPendingDeletion = false,
  }) {
    if (_isDisposed) throw StateError('Chat provider is disposed');
    _startupAccess?.require(operation);
    if (!allowPendingDeletion && operation != StartupAccessOperation.browse) {
      _requireChatAvailable(_currentChat?.id);
    }
  }

  void _requireChatAvailable(int? chatId) {
    if (chatId != null && _pendingChatDeletions.containsKey(chatId)) {
      throw ChatDeletionPending();
    }
  }

  double get contextUsage {
    if (_contextUsageCacheStale) {
      _cachedContextUsage = _computeContextUsage();
      _contextUsageCacheStale = false;
    }
    return _cachedContextUsage;
  }

  double _computeContextUsage() {
    return _generation?.lastContextUsage ?? 0.0;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    _contextUsageCacheStale = true;
    super.notifyListeners();
  }

  List<Chat> get chats => _chats;
  Chat? get currentChat => _currentChat;
  List<Message> get messages => _messages;
  Object? responseFrameIdentityFor(Message message) =>
      message.chatId == _currentChat?.id
      ? _responseFrameIdentities[message]
      : null;
  bool get isLoading => _isLoading;
  bool get hasHistoryError => _hasHistoryError;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  ModelSettings get settings => _settings;
  int get settingsPersistenceFailures => _settingsWriteFailures;
  int get deletionFailures => _deletionFailures;
  Persona? get currentPersona => _currentPersona;
  List<Note> get attachedNotes => List.unmodifiable(_attachedNotes);
  Note? get attachedNote => _attachedNotes.firstOrNull;
  bool get hasOlderMessages => _hasOlderMessages;

  Future<String> exportConversation() async {
    _requireAccess(StartupAccessOperation.browse);
    final chat = _currentChat;
    if (chat?.id == null) throw StateError('No conversation selected');
    await drainPendingPersistence();
    final messages = await _db.getAllMessagesForExport(chat!.id!);
    final buffer = StringBuffer()
      ..writeln('${AppStrings.conversationCopied}: ${chat.title}')
      ..writeln('${'=' * 40}\n');
    for (final message in messages) {
      if (message.isError) continue;
      final role = switch (message.role) {
        MessageRole.user => 'You',
        MessageRole.assistant => 'Assistant',
        MessageRole.system => 'System',
      };
      buffer
        ..writeln('[$role]')
        ..writeln(message.content)
        ..writeln();
    }
    return buffer.toString();
  }

  String? get generatingContent =>
      _generation?.isSending == true &&
          (_generation?.streamText ?? '').isNotEmpty
      ? _generation!.streamText
      : null;

  void setGenerationProvider(GenerationProvider provider) {
    if (_isDisposed) throw StateError('Chat provider is disposed');
    if (_generation == provider) return;
    _detachGenerationCallbacks();
    _generation = provider;
    provider.onGenerationComplete = _onGenerationComplete;
    provider.onError = _onGenerationError;
  }

  void _onGenerationComplete(String assistantMessage) {
    if (_isDisposed || _currentChat == null) return;
    final pending = _persistCompletion(
      _currentChat!.id!,
      assistantMessage,
      _selectionEpoch,
      _generation?.responseFrameIdentity,
    );
    _pendingCompletionSaves.add(pending);
    unawaited(
      pending.then<void>((_) => _pendingCompletionSaves.remove(pending)),
    );
  }

  /// Drains already-owned saves without a timing assumption or data deletion.
  Future<void> drainPendingPersistence() => Future.wait<void>([
    ..._pendingCompletionSaves,
    _settingsWriteTail,
    ..._personaWrites.values,
    ..._deletionSettlements,
  ]);

  Future<void> _persistCompletion(
    int chatId,
    String content,
    int selectionEpoch,
    Object? responseFrameIdentity,
  ) async {
    try {
      final msg = Message(
        chatId: chatId,
        role: MessageRole.assistant,
        content: content,
      );
      final msgId = await _db.insertMessage(msg.toMap());
      await _db.updateChat(chatId, {
        'updated_at': DateTime.now().toIso8601String(),
      });
      // Finish the original chat's durable save even after navigation/removal,
      // but never append it to another selection or notify a disposed owner.
      if (_isDisposed ||
          selectionEpoch != _selectionEpoch ||
          _currentChat?.id != chatId)
        return;
      final saved = msg.copyWith(id: msgId);
      _responseFrameIdentities[saved] = responseFrameIdentity;
      _messages.add(saved);
      notifyListeners();
    } catch (e) {
      _logger.error('Error saving generation result (${e.runtimeType})');
      if (selectionEpoch == _selectionEpoch && _currentChat?.id == chatId) {
        _setError(
          'Response persistence did not fully complete. Reopen this chat before retrying.',
        );
      }
    }
  }

  void _onGenerationError(String error) {
    _setError(error);
  }

  void _setError(String msg) {
    if (_isDisposed) return;
    _hasError = true;
    _errorMessage = msg;
    notifyListeners();
  }

  void clearError() {
    _hasError = false;
    _errorMessage = '';
    notifyListeners();
  }

  Future<void> loadChats() async {
    _requireAccess(StartupAccessOperation.browse);
    _hasHistoryError = false;
    _isLoading = true;
    notifyListeners();
    try {
      _chats = await _db.getChats();
    } catch (e) {
      _hasHistoryError = true;
      _logger.error('Failed to load chats (${e.runtimeType})');
      _chats = [];
      _setError('Failed to load chats');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Chat?> createChat({String? title}) async {
    _requireAccess(StartupAccessOperation.mutateContent);
    final modelId = _settings.modelId;
    final epoch = ++_selectionEpoch;
    _generation?.abandonResponseFrameObservation();
    final now = DateTime.now();
    final chat = Chat(
      title: title ?? 'New Chat',
      createdAt: now,
      updatedAt: now,
    );
    try {
      if (_generation?.isSending == true) await _generation!.stopSending();
      if (_isDisposed || epoch != _selectionEpoch) return null;
      _requireAccess(StartupAccessOperation.mutateContent);
      final id = await _db.insertChatWithModel(
        chat.toMap(),
        modelId,
        beforeCommit: () =>
            _requireAccess(StartupAccessOperation.mutateContent),
      );
      if (_isDisposed || epoch != _selectionEpoch) return chat.copyWith(id: id);
      _currentChat = chat.copyWith(id: id);
      _messages = [];
      _attachedNotes = [];
      _currentPersona = null;
      _settings = ModelSettings(modelId: modelId);
      _committedSettings = _settings;
      _settingsRevision++;
      _hasOlderMessages = false;
      _hasError = false;
      _generation?.clearError();
      notifyListeners();
      await _modelReadiness?.select(_settings.modelId);
      return chat.copyWith(id: id);
    } catch (e) {
      if (_isDisposed || epoch != _selectionEpoch) return null;
      _logger.error('Failed to create chat (${e.runtimeType})');
      _setError('Failed to create chat');
      return null;
    }
  }

  Future<void> selectChat(int id) async {
    _requireAccess(StartupAccessOperation.browse);
    final epoch = ++_selectionEpoch;
    _generation?.abandonResponseFrameObservation();
    bool current() => !_isDisposed && epoch == _selectionEpoch;
    _modelReadiness?.invalidate();
    _isLoading = true;
    _hasError = false;
    notifyListeners();
    try {
      if (_generation?.isSending == true) await _generation!.stopSending();
      if (!current()) return;
      final chat = await _db.getChat(id);
      if (!current()) return;
      var messages = <Message>[];
      var notes = <Note>[];
      var settings = ModelSettings();
      Persona? persona;
      if (chat != null) {
        messages = await _db.getMessagesForChatPaginated(
          id,
          limit: PaginationPolicy.messagePageSize,
        );
        notes = await _db.getAttachedNotes(id);
        final settingsMap = await _db.getModelSettings(id);
        settings = settingsMap != null
            ? ModelSettings.fromJson(settingsMap)
            : ModelSettings();
        await _personaWrites[id];
        final personaId = await _db.getChatPersona(id);
        if (personaId != null) {
          persona = await _readPersona(personaId);
        }
      }
      if (!current()) return;
      if (chat != null) {
        final assessment = _modelReadiness?.select(settings.modelId);
        if (assessment != null) {
          // Hashing a large local model must not delay browsing saved messages.
          // Readiness stays checking, so inference remains blocked until it ends.
          unawaited(
            assessment.then<void>(
              (_) {},
              onError: (Object error, StackTrace _) {
                _logger.warning(
                  'Model readiness assessment failed (${error.runtimeType})',
                );
              },
            ),
          );
        }
      }
      if (!current()) return;
      _currentChat = chat;
      _messages = messages;
      _attachedNotes = notes;
      _settings = settings;
      _committedSettings = settings;
      _settingsRevision++;
      _currentPersona = persona;
      _hasOlderMessages = messages.length >= PaginationPolicy.messagePageSize;
    } catch (e) {
      if (!current()) return;
      _logger.error('Failed to load chat (${e.runtimeType})');
      _setError('Failed to load chat');
    }
    if (!current()) return;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadOlderMessages() async {
    _requireAccess(StartupAccessOperation.browse);
    if (_currentChat == null || !_hasOlderMessages) return;
    try {
      final chatId = _currentChat!.id!;
      final olderMessages = await _db.getMessagesForChatPaginated(
        chatId,
        limit: PaginationPolicy.messagePageSize,
        beforeId: _messages.firstOrNull?.id,
      );
      if (olderMessages.isNotEmpty) {
        _messages = [...olderMessages, ..._messages];
        _hasOlderMessages =
            olderMessages.length >= PaginationPolicy.messagePageSize;
        notifyListeners();
      } else {
        _hasOlderMessages = false;
        notifyListeners();
      }
    } catch (e) {
      _logger.error('Failed to load older messages (${e.runtimeType})');
    }
  }

  Future<void> deleteChat(int id) async {
    _requireAccess(
      StartupAccessOperation.mutateContent,
      allowPendingDeletion: true,
    );
    final existing = _pendingChatDeletions[id];
    if (existing != null) return existing;
    final pending = _deleteChat(id);
    _pendingChatDeletions[id] = pending;
    final settlement = pending.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _deletionFailures++;
      },
    );
    _deletionSettlements.add(settlement);
    unawaited(
      settlement.then<void>((_) {
        _deletionSettlements.remove(settlement);
        _pendingChatDeletions.remove(id);
      }),
    );
    return pending;
  }

  Future<void> _deleteChat(int id) async {
    var deletionCommitted = false;
    try {
      if (_currentChat?.id == id) {
        _generation?.abandonResponseFrameObservation();
        // Stop also owns preparation and recovery; isSending alone cannot
        // establish that native work has terminated.
        final generation = _generation;
        if (generation != null) await generation.stopSending();
      }
      // A terminal generation callback or prior settings action can already
      // own a durable save. Finish those writers before removing their chat.
      // Do not drain deletion settlements here: this operation owns one.
      await Future.wait<void>([
        ..._pendingCompletionSaves,
        _settingsWriteTail,
        ..._personaWrites.values,
      ]);
      _requireAccess(
        StartupAccessOperation.mutateContent,
        allowPendingDeletion: true,
      );
      if (await _db.deleteChat(id) != 1) {
        throw StateError('Chat deletion was not acknowledged');
      }
      deletionCommitted = true;
      // The durable write is allowed to settle after disposal, but its owner
      // must never start a fresh read or publish a replacement selection.
      if (_isDisposed) return;
      if (_currentChat?.id == id) {
        _selectionEpoch++;
        _currentChat = null;
        _messages = [];
        _attachedNotes = [];
        _currentPersona = null;
      }
      _requireAccess(StartupAccessOperation.browse);
      final remainingChats = await _db.getChats();
      if (_isDisposed) return;
      _chats = remainingChats;
      notifyListeners();
      if (_currentChat == null && _chats.isNotEmpty) {
        await selectChat(_chats.first.id!);
      } else if (_currentChat == null && _chats.isEmpty) {
        await createChat();
      }
      if (!_isDisposed && _hasError) {
        throw StateError('Remaining chat could not be opened');
      }
    } catch (e) {
      _logger.error('Chat deletion failed (${e.runtimeType})');
      final failure = ChatDeletionError(deletionCommitted: deletionCommitted);
      _setError(failure.message);
      throw failure;
    }
  }

  Future<void> stopSending() async => _generation?.stopSending();

  Future<void> retryLastMessage() async {
    _requireAccess(StartupAccessOperation.inference);
    if (_generation?.isSending == true) return;
    final lastUserMsg = _messages
        .where((m) => m.role == MessageRole.user)
        .lastOrNull;
    if (lastUserMsg == null) return;
    if (_messages.isNotEmpty && _messages.last.isError) {
      _messages.removeLast();
    }
    await sendMessage(lastUserMsg.content);
  }

  Future<void> regenerate() async {
    _requireAccess(StartupAccessOperation.inference);
    if (_generation?.isSending == true || _messages.isEmpty) return;
    final lastMsg = _messages.last;
    if (lastMsg.role != MessageRole.assistant) return;
    _messages.removeLast();
    if (lastMsg.id != null) {
      await _db.deleteMessage(lastMsg.id!);
    }
    _hasError = false;
    notifyListeners();
    await _startGeneration();
  }

  Future<void> sendMessage(String content) async {
    await submitMessage(content);
  }

  /// True means the user message is stored, even if generation later fails.
  /// A composer may restore an unsaved draft only when this returns false.
  Future<bool> submitMessage(String content) async {
    _requireAccess(StartupAccessOperation.inference);
    if (content.trim().isEmpty) return false;
    if (exceedsUtf8Bytes(content, AppConstants.maxStoredTextBytes)) {
      _setError('Message is larger than the 1 MiB storage safety limit');
      return false;
    }
    if (_currentChat == null) {
      _setError('No active chat');
      return false;
    }
    if (_generation?.isSending == true) {
      _setError('Already generating a response');
      return false;
    }
    _hasError = false;
    final chatId = _currentChat!.id!;
    final selectionEpoch = _selectionEpoch;
    bool ownsView() =>
        !_isDisposed &&
        selectionEpoch == _selectionEpoch &&
        _currentChat?.id == chatId;
    final userMessage = Message(
      chatId: chatId,
      role: MessageRole.user,
      content: content,
    );
    var persisted = false;
    try {
      final msgId = await _db.insertMessage(userMessage.toMap());
      persisted = true;
      if (!ownsView()) return true;
      _messages.add(userMessage.copyWith(id: msgId));
      notifyListeners();
      await _startGeneration();
      return true;
    } catch (e) {
      _logger.error('Error sending message (${e.runtimeType})');
      if (!ownsView()) return persisted;
      _setError('Failed to send message');
      notifyListeners();
      return persisted;
    }
  }

  Future<void> _startGeneration() async {
    await _generation?.startGeneration(
      messages: _messages,
      settings: _settings,
      persona: _currentPersona,
      attachedNotes: _attachedNotes,
    );
  }

  Future<void> attachNote(Note? note) async {
    _requireAccess(StartupAccessOperation.mutateContent);
    if (note == null || note.id == null || _currentChat?.id == null) return;
    if (_attachedNotes.any((item) => item.id == note.id)) return;
    await _db.attachNote(_currentChat!.id!, note.id!);
    _attachedNotes = [..._attachedNotes, note];
    notifyListeners();
  }

  Future<void> clearAttachedNote([Note? note]) async {
    _requireAccess(StartupAccessOperation.mutateContent);
    final chatId = _currentChat?.id;
    if (chatId == null) return;
    final selectionEpoch = _selectionEpoch;
    final removedIds = note?.id != null
        ? {note!.id}
        : _attachedNotes.map((attached) => attached.id).toSet();
    if (note?.id != null) {
      await _db.detachNote(chatId, note!.id!);
    } else {
      for (final id in removedIds) {
        if (id != null) await _db.detachNote(chatId, id);
      }
    }
    if (_isDisposed ||
        _selectionEpoch != selectionEpoch ||
        _currentChat?.id != chatId)
      return;
    _attachedNotes = _attachedNotes
        .where((attached) => !removedIds.contains(attached.id))
        .toList();
    notifyListeners();
  }

  Future<void> updateChatTitle(int chatId, String title) async {
    _requireAccess(StartupAccessOperation.mutateContent);
    _requireChatAvailable(chatId);
    if (exceedsUnicodeScalars(title, AppConstants.maxChatTitleLength)) {
      _setError('Chat title is limited to 256 characters');
      return;
    }
    try {
      await _db.updateChat(chatId, {
        'title': title,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (_currentChat?.id == chatId) {
        _currentChat = _currentChat!.copyWith(title: title);
      }
      final index = _chats.indexWhere((c) => c.id == chatId);
      if (index != -1) {
        _chats[index] = _chats[index].copyWith(title: title);
      }
      notifyListeners();
    } catch (e) {
      _logger.error('Failed to update chat title (${e.runtimeType})');
      _setError('Failed to update chat title');
    }
  }

  void updateSettingsLocally(ModelSettings settings) {
    _requireAccess(StartupAccessOperation.mutateContent);
    _settings = settings;
    _settingsRevision++;
    notifyListeners();
  }

  Future<void> updateSettings(ModelSettings settings) async {
    await _admitSettingsWrite(settings);
  }

  Future<void> switchModel(String modelId) async {
    _requireAccess(StartupAccessOperation.recoverModels);
    if (_modelSwitchInProgress) throw StateError('Model switch already active');
    final selectionEpoch = _selectionEpoch;
    final chatId = _currentChat?.id;
    final next = chatId == null
        ? ModelSettings(modelId: modelId)
        : _settings.copyWith(modelId: modelId);
    void requireSelectedOwner() {
      _requireAccess(StartupAccessOperation.recoverModels);
      if (selectionEpoch != _selectionEpoch) {
        throw StateError('Chat selection changed during model switching');
      }
    }

    _modelSwitchInProgress = true;
    try {
      final model = await _modelRegistry.requireInstalled(modelId);
      if (model.id != modelId || model.compatibilityStatus != 'compatible') {
        throw StateError('Model verification required');
      }
      requireSelectedOwner();
      if (_generation?.isSending == true) await _generation!.stopSending();
      requireSelectedOwner();
      if (chatId == null) {
        void requireFirstChatAccess() {
          requireSelectedOwner();
          final capabilities = _startupAccess?.snapshot();
          if (capabilities != null &&
              !capabilities
                  .withModelReadiness(StartupModelReadiness.ready)
                  .canMutateContent) {
            throw StartupAccessDenied(StartupAccessOperation.mutateContent);
          }
        }

        requireFirstChatAccess();
        final now = DateTime.now();
        final draft = Chat(title: 'New Chat', createdAt: now, updatedAt: now);
        final id = await _db.insertChatWithModel(
          draft.toMap(),
          modelId,
          beforeCommit: requireFirstChatAccess,
        );
        requireSelectedOwner();
        _generation?.abandonResponseFrameObservation();
        _currentChat = draft.copyWith(id: id);
        _messages = [];
        _attachedNotes = [];
        _currentPersona = null;
        _hasOlderMessages = false;
        _hasError = false;
        _generation?.clearError();
      } else {
        await _db.assignModelForChat(chatId, modelId);
      }
      requireSelectedOwner();
      _settings = next;
      _committedSettings = _committedSettings.copyWith(modelId: modelId);
      _settingsRevision++;
      await _modelReadiness?.select(modelId, refresh: true);
      requireSelectedOwner();
      notifyListeners();
      if (_startupAccess?.snapshot().canInfer != false) {
        await _generation?.prepareModel(next);
      }
    } catch (error) {
      _setError('Model switch failed (${error.runtimeType}).');
      rethrow;
    } finally {
      _modelSwitchInProgress = false;
    }
  }

  bool isCurrentModel(String modelId) => _settings.modelId == modelId;

  Future<void> prepareModelRemoval(String modelId) async {
    if (!isCurrentModel(modelId)) return;
    await _generation?.unloadModel(modelId);
  }

  Future<bool> setPersona(Persona persona) async => _savePersona(persona);

  Future<bool> removePersona() async => _savePersona(null);

  /// Only committed record changes update the current chat; assignments stay put.
  void applyPersonaChange(int id, Persona? persona) {
    if (_isDisposed) return;
    _personaRevision++;
    if (_currentPersona?.id != id) return;
    _currentPersona = persona;
    notifyListeners();
  }

  Future<Persona?> _readPersona(int id) async {
    while (!_isDisposed) {
      final revision = _personaRevision;
      final map = await _db.getPersona(id);
      if (revision == _personaRevision) {
        return map == null ? null : Persona.fromMap(map);
      }
    }
    return null;
  }

  Future<bool> _savePersona(Persona? persona) {
    _requireAccess(StartupAccessOperation.mutateContent);
    final chatId = _currentChat?.id;
    final epoch = _selectionEpoch;
    final previous = _personaWrites[chatId] ?? Future<void>.value();
    final pending = previous.then<bool>((_) async {
      bool ownsView() =>
          !_isDisposed &&
          epoch == _selectionEpoch &&
          chatId == _currentChat?.id;
      try {
        if (chatId != null) {
          if (persona == null) {
            await _db.removeChatPersona(chatId);
          } else {
            final id = persona.id;
            if (id == null) throw StateError('Persona has not been saved');
            // The unique chat mapping is replaced in one database statement.
            await _db.setChatPersona(chatId, id);
          }
        }
        if (ownsView()) {
          final committed = persona == null || chatId == null
              ? persona
              : await _readPersona(persona.id!);
          if (!ownsView()) return true;
          _currentPersona = committed;
          _hasError = false;
          _errorMessage = '';
          notifyListeners();
        }
        return true;
      } catch (e) {
        _logger.error('Persona persistence failed (${e.runtimeType})');
        if (ownsView()) _setError('Persona could not be saved. Please retry.');
        return false;
      }
    });
    late final Future<void> settled;
    settled = pending.then<void>((_) {
      if (identical(_personaWrites[chatId], settled)) {
        _personaWrites.remove(chatId);
      }
    });
    _personaWrites[chatId] = settled;
    return pending;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _detachGenerationCallbacks();
    _generation = null;
    _closeFuture = drainPendingPersistence();
    super.dispose();
  }

  Future<void> close() {
    dispose();
    return _closeFuture!;
  }

  void _detachGenerationCallbacks() {
    final generation = _generation;
    if (generation?.onGenerationComplete == _onGenerationComplete) {
      generation!.onGenerationComplete = null;
    }
    if (generation?.onError == _onGenerationError) generation!.onError = null;
  }
}
