import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/note.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../utils/validation_exception.dart';
import '../utils/text_limits.dart';
import '../services/startup_access_guard.dart';

class NoteProvider extends ChangeNotifier {
  NoteProvider({
    DatabaseHelper? database,
    StartupAccessGuard? startupAccess,
    AppLogger? logger,
  }) : _db = database ?? DatabaseHelper.instance,
       _logger = logger ?? AppLogger.instance,
       _startupAccess = startupAccess;

  final DatabaseHelper _db;
  final AppLogger _logger;
  final StartupAccessGuard? _startupAccess;
  bool _disposed = false;

  void _require(StartupAccessOperation operation) {
    if (_disposed) throw StateError('Note provider is disposed');
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

  List<Note> _notes = [];
  bool _isLoading = false;

  List<Note> get notes => _notes;
  bool get isLoading => _isLoading;

  Future<void> loadNotes() async {
    _require(StartupAccessOperation.browse);
    _isLoading = true;
    notifyListeners();
    try {
      final notesMap = await _db.getNotes();
      _notes = notesMap.map((m) => Note.fromMap(m)).toList();
    } catch (e) {
      _notes = [];
      _logger.error('Error loading notes (${e.runtimeType})');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Note?> createNote(String title, String content) async {
    _require(StartupAccessOperation.mutateContent);
    if (exceedsUnicodeScalars(title, AppConstants.maxNoteTitleLength)) {
      throw const ValidationException('Title too long (max 256 characters)');
    }
    if (exceedsUtf8Bytes(content, AppConstants.maxNoteContentLength)) {
      throw const ValidationException(
        'Content is larger than the 1 MiB storage safety limit',
      );
    }
    try {
      final note = Note(title: title, content: content);
      final id = await _db.insertNote(note.toMap());
      final created = Note(
        id: id,
        title: title,
        content: content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
      );
      _notes.insert(0, created);
      notifyListeners();
      return created;
    } catch (e) {
      _logger.error('Error creating note (${e.runtimeType})');
      return null;
    }
  }

  Future<void> updateNote(Note note) async {
    _require(StartupAccessOperation.mutateContent);
    if (exceedsUnicodeScalars(note.title, AppConstants.maxNoteTitleLength) ||
        exceedsUtf8Bytes(note.content, AppConstants.maxNoteContentLength)) {
      throw const ValidationException('Note exceeds its storage safety limit');
    }
    try {
      await _db.updateNote(note.id!, note.toMap());
      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index != -1) {
        _notes[index] = note;
        notifyListeners();
      }
    } catch (e) {
      _logger.error('Error updating note (${e.runtimeType})');
    }
  }

  Future<void> deleteNote(int id) async {
    _require(StartupAccessOperation.mutateContent);
    try {
      await _db.deleteNote(id);
      _notes.removeWhere((n) => n.id == id);
      notifyListeners();
    } catch (e) {
      _logger.error('Error deleting note (${e.runtimeType})');
    }
  }
}
