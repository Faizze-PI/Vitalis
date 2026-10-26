part of 'chat_provider.dart';

final class ChatSettingsSaveError extends StateError {
  ChatSettingsSaveError()
    : super('Chat settings could not be saved. Please retry.');
}

extension _ChatSettingsPersistence on ChatProvider {
  Future<void> _admitSettingsWrite(ModelSettings settings) {
    _requireAccess(StartupAccessOperation.mutateContent);
    if (exceedsUtf8Bytes(
      settings.systemPrompt,
      AppConstants.maxStoredTextBytes,
    )) {
      _setError('System prompt exceeds the 1 MiB storage safety limit');
      throw ArgumentError(
        'System prompt exceeds the 1 MiB storage safety limit',
      );
    }
    final ownerEpoch = _selectionEpoch;
    final chatId = _currentChat?.id;
    final revision = ++_settingsRevision;
    final pending = _settingsWriteTail.then<void>((_) async {
      bool ownsView() =>
          !_isDisposed &&
          ownerEpoch == _selectionEpoch &&
          chatId == _currentChat?.id;
      try {
        if (chatId != null) {
          final existing = await _db.getModelSettings(chatId);
          final json = settings.toJson()..['chat_id'] = chatId;
          if (existing != null) {
            if (await _db.updateModelSettings(chatId, json) != 1) {
              throw StateError('Settings record was not updated');
            }
          } else if (await _db.insertModelSettings(json) <= 0) {
            throw StateError('Settings record was not inserted');
          }
        }
        if (ownsView()) {
          _committedSettings = settings;
          if (revision == _settingsRevision) {
            _settings = settings;
            _hasError = false;
            _errorMessage = '';
            notifyListeners();
          }
        }
      } catch (error) {
        _logger.error('Settings persistence failed (${error.runtimeType})');
        if (ownsView() && revision == _settingsRevision) {
          _settings = _committedSettings;
          _setError('Chat settings could not be saved. Please retry.');
        }
        throw ChatSettingsSaveError();
      }
    });
    // Settlement advances the next admitted write and lets close drain every
    // operation. The original future reports failure to its caller; a counter
    // records the typed cleanup disposition instead of swallowing it silently.
    _settingsWriteTail = pending.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _settingsWriteFailures++;
      },
    );
    return pending;
  }
}
