part of 'gguf_metadata.dart';

/// Keeps vocabulary string skips local instead of issuing three OS calls/token.
final class _GgufBufferedReader {
  _GgufBufferedReader(this._file, this._length);

  // hardcode: HC-054; bounded read-ahead, not a model/metadata size ceiling.
  static const _windowBytes = 64 * 1024;
  final RandomAccessFile _file;
  final int _length;
  int _offset = 0;
  int _bufferStart = 0;
  Uint8List _buffer = Uint8List(0);

  Future<int> position() async => _offset;

  Future<void> setPosition(int offset) async {
    if (offset < 0 || offset > _length) {
      throw const FormatException('Truncated GGUF metadata');
    }
    _offset = offset;
  }

  Future<Uint8List> read(int count) async {
    if (count < 0 || count > _length - _offset) {
      throw const FormatException('Truncated GGUF metadata');
    }
    final result = Uint8List(count);
    var copied = 0;
    while (copied < count) {
      var relative = _offset - _bufferStart;
      if (relative < 0 || relative >= _buffer.length) {
        await _file.setPosition(_offset);
        _bufferStart = _offset;
        final remaining = _length - _offset;
        _buffer = await _file.read(
          remaining < _windowBytes ? remaining : _windowBytes,
        );
        if (_buffer.isEmpty) {
          throw const FormatException('Truncated GGUF metadata');
        }
        relative = 0;
      }
      final available = _buffer.length - relative;
      final needed = count - copied;
      final taking = available < needed ? available : needed;
      result.setRange(copied, copied + taking, _buffer, relative);
      copied += taking;
      _offset += taking;
    }
    return result;
  }
}
