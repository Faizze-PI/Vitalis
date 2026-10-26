import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

abstract final class RemoteGgufInspectionPolicy {
  static const initialBytes = 64 * 1024;
  static const maximumBytes = 8 * 1024 * 1024;
  static const maximumMetadataEntries = 100000; // hardcode: HC-036
  static const maximumStringBytes = 1024 * 1024;
  static const maximumArrayEntries = 1000000; // hardcode: HC-036
  static const maximumRedirects = 5; // hardcode: HC-036
}

class RemoteGgufMetadata {
  const RemoteGgufMetadata({
    required this.complete,
    this.name,
    this.architecture,
    this.tokenizer,
    this.chatTemplate,
    this.trainingContext,
  });

  final bool complete;
  final String? name;
  final String? architecture;
  final String? tokenizer;
  final String? chatTemplate;
  final int? trainingContext;

  static const unknown = RemoteGgufMetadata(complete: false);
}

class RemoteRangeResult {
  const RemoteRangeResult(this.bytes);
  final Uint8List bytes;
}

abstract interface class RemoteRangeReader {
  Future<RemoteRangeResult> read(Uri source, int maximumBytes);
}

class DioRemoteRangeReader implements RemoteRangeReader {
  DioRemoteRangeReader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<RemoteRangeResult> read(Uri source, int maximumBytes) async {
    if (maximumBytes <= 0 ||
        maximumBytes > RemoteGgufInspectionPolicy.maximumBytes) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    var current = source;
    for (
      var redirects = 0;
      redirects <= RemoteGgufInspectionPolicy.maximumRedirects;
      redirects++
    ) {
      _validateHubUri(current);
      final cancellation = CancelToken();
      try {
        final response = await _dio.get<ResponseBody>(
          current.toString(),
          cancelToken: cancellation,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
            headers: {'Range': 'bytes=0-${maximumBytes - 1}'},
          ),
        );
        final status = response.statusCode ?? 0;
        if (status >= 300 && status < 400) {
          await response.data?.stream.listen(null).cancel();
          final location = response.headers.value('location');
          if (location == null) {
            throw const FormatException('Hub redirect has no target');
          }
          current = current.resolve(location);
          continue;
        }
        final body = response.data;
        if (body == null) throw const FormatException('Missing GGUF response');
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in body.stream) {
          if (chunk.length > maximumBytes - bytes.length) {
            throw const FormatException(
              'GGUF range response exceeded its bound',
            );
          }
          bytes.add(chunk);
        }
        return RemoteRangeResult(bytes.takeBytes());
      } finally {
        // Also terminates ignored-Range bodies and redirect response streams.
        cancellation.cancel('Metadata inspection finished');
      }
    }
    throw const FormatException('Too many GGUF redirects');
  }

  void _validateHubUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final allowed =
        uri.scheme == 'https' &&
        (host == 'huggingface.co' ||
            host.endsWith('.huggingface.co') ||
            host == 'hf.co' ||
            host.endsWith('.hf.co'));
    if (!allowed || uri.userInfo.isNotEmpty) {
      throw const FormatException('Unsafe remote GGUF target');
    }
  }
}

abstract interface class RemoteGgufInspector {
  Future<RemoteGgufMetadata> inspect(Uri source);
}

class BoundedRemoteGgufInspector implements RemoteGgufInspector {
  const BoundedRemoteGgufInspector({required RemoteRangeReader reader})
    : _reader = reader;

  final RemoteRangeReader _reader;

  @override
  Future<RemoteGgufMetadata> inspect(Uri source) async {
    var requested = RemoteGgufInspectionPolicy.initialBytes;
    while (requested <= RemoteGgufInspectionPolicy.maximumBytes) {
      final result = await _reader.read(source, requested);
      try {
        return GgufHeaderParser.parse(result.bytes);
      } on GgufRangeIncomplete {
        if (requested == RemoteGgufInspectionPolicy.maximumBytes) {
          return RemoteGgufMetadata.unknown;
        }
        requested = (requested * 2).clamp(
          RemoteGgufInspectionPolicy.initialBytes,
          RemoteGgufInspectionPolicy.maximumBytes,
        );
      }
    }
    return RemoteGgufMetadata.unknown;
  }
}

class GgufRangeIncomplete implements Exception {
  const GgufRangeIncomplete();
}

abstract final class GgufHeaderParser {
  static RemoteGgufMetadata parse(Uint8List bytes) =>
      _GgufReader(bytes).parse();
}

class _GgufReader {
  _GgufReader(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  var offset = 0;

  RemoteGgufMetadata parse() {
    if (_stringBytes(4) != 'GGUF') {
      throw const FormatException('Remote file is not GGUF');
    }
    final version = _u32();
    if (version < 2 || version > 3) {
      throw const FormatException('Unsupported GGUF version');
    }
    _u64(); // tensor count; tensors are intentionally not parsed remotely.
    final metadataCount = _u64();
    if (metadataCount > RemoteGgufInspectionPolicy.maximumMetadataEntries) {
      throw const FormatException('Excessive GGUF metadata count');
    }
    final values = <String, Object?>{};
    for (var index = 0; index < metadataCount; index++) {
      final key = _string();
      final type = _u32();
      final value = _value(type);
      if (_interestingKeys.contains(key) || key.endsWith('.context_length')) {
        values[key] = value;
      }
    }
    final architecture = values['general.architecture'] as String?;
    final contextKey = architecture == null
        ? null
        : '$architecture.context_length';
    return RemoteGgufMetadata(
      complete: true,
      name: values['general.name'] as String?,
      architecture: architecture,
      tokenizer: values['tokenizer.ggml.model'] as String?,
      chatTemplate: values['tokenizer.chat_template'] as String?,
      trainingContext: contextKey == null ? null : _asInt(values[contextKey]),
    );
  }

  static const _interestingKeys = {
    'general.name',
    'general.architecture',
    'tokenizer.ggml.model',
    'tokenizer.chat_template',
  };

  Object? _value(int type) => switch (type) {
    0 => _u8(),
    1 => _i8(),
    2 => _u16(),
    3 => _i16(),
    4 => _u32(),
    5 => _i32(),
    6 => _f32(),
    7 => _u8() != 0,
    8 => _string(),
    9 => _array(),
    10 => _u64(),
    11 => _i64(),
    12 => _f64(),
    _ => throw const FormatException('Unsupported GGUF metadata type'),
  };

  Object? _array() {
    final elementType = _u32();
    if (elementType == 9) {
      throw const FormatException('Nested GGUF arrays are not supported');
    }
    final count = _u64();
    if (count > RemoteGgufInspectionPolicy.maximumArrayEntries) {
      throw const FormatException('Excessive GGUF array count');
    }
    for (var index = 0; index < count; index++) {
      _value(elementType);
    }
    return null;
  }

  String _string() {
    final length = _u64();
    if (length > RemoteGgufInspectionPolicy.maximumStringBytes) {
      throw const FormatException('Excessive GGUF string length');
    }
    return _stringBytes(length);
  }

  String _stringBytes(int length) {
    _need(length);
    final result = utf8.decode(
      bytes.sublist(offset, offset + length),
      allowMalformed: false,
    );
    offset += length;
    return result;
  }

  int? _asInt(Object? value) => switch (value) {
    int number => number,
    null => null,
    _ => throw const FormatException('Invalid GGUF integer metadata'),
  };

  void _need(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const GgufRangeIncomplete();
    }
  }

  int _u8() {
    _need(1);
    return data.getUint8(offset++);
  }

  int _i8() {
    _need(1);
    return data.getInt8(offset++);
  }

  int _u16() {
    _need(2);
    final v = data.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int _i16() {
    _need(2);
    final v = data.getInt16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int _u32() {
    _need(4);
    final v = data.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int _i32() {
    _need(4);
    final v = data.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int _u64() {
    _need(8);
    final v = data.getUint64(offset, Endian.little);
    offset += 8;
    return v;
  }

  int _i64() {
    _need(8);
    final v = data.getInt64(offset, Endian.little);
    offset += 8;
    return v;
  }

  double _f32() {
    _need(4);
    final v = data.getFloat32(offset, Endian.little);
    offset += 4;
    return v;
  }

  double _f64() {
    _need(8);
    final v = data.getFloat64(offset, Endian.little);
    offset += 8;
    return v;
  }
}
