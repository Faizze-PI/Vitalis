/// Removes only the empty structural envelope emitted by some Qwen templates
/// after a verified `/no_think` directive.
///
/// This deliberately never removes non-empty reasoning. If a model ignores
/// the directive and supplies content between the tags, the complete response
/// is preserved instead of hiding it from the user.
class EmptyThinkEnvelopeFilter {
  static final RegExp _opening = RegExp(r'^\s*<think>');
  static final RegExp _emptyEnvelope = RegExp(r'^\s*<think>\s*</think>\s*');
  static final RegExp _nonEmptyEnvelope = RegExp(r'^\s*<think>\s*[^\s<]');

  String _pending = '';
  bool _settled = false;

  /// Transforms one streamed text chunk.
  String add(String chunk) {
    if (_settled) return chunk;
    _pending += chunk;

    final emptyMatch = _emptyEnvelope.firstMatch(_pending);
    if (emptyMatch != null) {
      _settled = true;
      final result = _pending.substring(emptyMatch.end);
      _pending = '';
      return result;
    }

    // A normal response, or a non-empty think block, must remain visible.
    // The small bound only delays the first visible chunk while we determine
    // whether the template emitted an empty envelope across token boundaries.
    final trimmed = _pending.trimLeft();
    final couldBeOpeningPrefix = '<think>'.startsWith(trimmed);
    if ((!_opening.hasMatch(_pending) && !couldBeOpeningPrefix) ||
        _nonEmptyEnvelope.hasMatch(_pending) ||
        _pending.length > 64) {
      _settled = true;
      final result = _pending;
      _pending = '';
      return result;
    }
    return '';
  }

  /// Flushes text retained while recognizing a split envelope.
  String finish() {
    if (_settled) return '';
    _settled = true;
    final result = _pending;
    _pending = '';
    return result;
  }
}
