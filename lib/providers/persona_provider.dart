import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/persona.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../utils/validation_exception.dart';
import '../utils/text_limits.dart';
import '../services/startup_access_guard.dart';

class PersonaProvider extends ChangeNotifier {
  PersonaProvider({
    DatabaseHelper? database,
    StartupAccessGuard? startupAccess,
    AppLogger? logger,
    this.onCommittedChange,
  }) : _db = database ?? DatabaseHelper.instance,
       _logger = logger ?? AppLogger.instance,
       _startupAccess = startupAccess;

  final DatabaseHelper _db;
  final AppLogger _logger;
  final StartupAccessGuard? _startupAccess;
  final void Function(int id, Persona? persona)? onCommittedChange;
  bool _disposed = false;

  void _require(StartupAccessOperation operation) {
    if (_disposed) throw StateError('Persona provider is disposed');
    _startupAccess?.require(operation);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  List<Persona> _personas = [];
  bool _isLoading = false;

  List<Persona> get personas => _personas;
  bool get isLoading => _isLoading;

  Future<void> loadPersonas() async {
    _require(StartupAccessOperation.browse);
    _isLoading = true;
    notifyListeners();
    try {
      final personaMaps = await _db.getPersonas();
      _personas = personaMaps.map((m) => Persona.fromMap(m)).toList();
    } catch (e) {
      _personas = [];
      _logger.error('Error loading personas (${e.runtimeType})');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Persona?> createPersona(String name, String systemPrompt) async {
    _require(StartupAccessOperation.mutateContent);
    if (exceedsUnicodeScalars(name, AppConstants.maxPersonaNameLength)) {
      throw const ValidationException('Name too long (max 256 characters)');
    }
    if (exceedsUtf8Bytes(
      systemPrompt,
      AppConstants.maxPersonaSystemPromptLength,
    )) {
      throw const ValidationException(
        'Prompt is larger than the 1 MiB storage safety limit',
      );
    }
    try {
      final persona = Persona(name: name, systemPrompt: systemPrompt);
      final id = await _db.insertPersona(persona.toMap());
      final created = Persona(id: id, name: name, systemPrompt: systemPrompt);
      _personas.add(created);
      notifyListeners();
      return created;
    } catch (e) {
      _logger.error('Error creating persona (${e.runtimeType})');
      return null;
    }
  }

  Future<void> updatePersona(Persona persona) async {
    _require(StartupAccessOperation.mutateContent);
    if (exceedsUnicodeScalars(
          persona.name,
          AppConstants.maxPersonaNameLength,
        ) ||
        exceedsUtf8Bytes(
          persona.systemPrompt,
          AppConstants.maxPersonaSystemPromptLength,
        )) {
      throw const ValidationException(
        'Persona exceeds its storage safety limit',
      );
    }
    try {
      if (await _db.updatePersona(persona.id!, persona.toMap()) != 1) {
        throw StateError('Persona update was not acknowledged');
      }
      final index = _personas.indexWhere((p) => p.id == persona.id);
      if (index != -1) {
        _personas[index] = persona;
      }
      if (!_disposed) onCommittedChange?.call(persona.id!, persona);
      notifyListeners();
    } catch (e) {
      _logger.error('Error updating persona (${e.runtimeType})');
    }
  }

  Future<bool> deletePersona(int id) async {
    _require(StartupAccessOperation.mutateContent);
    try {
      // Foreign-key cascade keeps persona and chat mappings atomic.
      if (await _db.deletePersona(id) != 1) {
        throw StateError('Persona deletion was not acknowledged');
      }
      _personas.removeWhere((p) => p.id == id);
      if (!_disposed) onCommittedChange?.call(id, null);
      notifyListeners();
      return true;
    } catch (e) {
      _logger.error('Error deleting persona (${e.runtimeType})');
      return false;
    }
  }
}
