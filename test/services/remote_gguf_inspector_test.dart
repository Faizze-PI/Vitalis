import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/remote_gguf_inspector.dart';

void main() {
  test(
    'HTTP reader bounds streamed ignored-Range responses before buffering',
    () async {
      final cancelled = Completer<void>();
      final stream = StreamController<Uint8List>(
        onCancel: () {
          cancelled.complete();
        },
      );
      final adapter = _ResponseAdapter(ResponseBody(stream.stream, 200));
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final result = DioRemoteRangeReader(dio: dio).read(
        Uri.parse('https://huggingface.co/a/b/resolve/revision/model.gguf'),
        4,
      );
      final assertion = expectLater(result, throwsFormatException);
      stream.add(Uint8List.fromList([1, 2, 3, 4]));
      stream.add(Uint8List.fromList([5]));
      await assertion;
      await cancelled.future.timeout(const Duration(seconds: 1));
      expect(adapter.responseType, ResponseType.stream);
      await stream.close();
    },
  );

  test('HTTP reader accepts exactly bounded data', () async {
    final adapter = _ResponseAdapter(
      ResponseBody(Stream.value(Uint8List.fromList([1, 2, 3, 4])), 206),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final result = await DioRemoteRangeReader(dio: dio).read(
      Uri.parse('https://huggingface.co/a/b/resolve/revision/model.gguf'),
      4,
    );
    expect(result.bytes, [1, 2, 3, 4]);
  });

  test('parses bounded text-model metadata', () {
    final bytes = _gguf({
      'general.architecture': 'qwen2',
      'general.name': 'Test model',
      'tokenizer.ggml.model': 'gpt2',
      'tokenizer.chat_template': '{{ messages }}',
      'qwen2.context_length': 32768,
    });
    final metadata = GgufHeaderParser.parse(bytes);
    expect(metadata.complete, isTrue);
    expect(metadata.architecture, 'qwen2');
    expect(metadata.tokenizer, 'gpt2');
    expect(metadata.trainingContext, 32768);
  });

  test('reports an incomplete range without guessing', () {
    final bytes = _gguf({'general.architecture': 'qwen2'});
    expect(
      () => GgufHeaderParser.parse(bytes.sublist(0, bytes.length - 1)),
      throwsA(isA<GgufRangeIncomplete>()),
    );
  });

  test('rejects excessive metadata counts before allocating', () {
    final builder = BytesBuilder()
      ..add(ascii.encode('GGUF'))
      ..add(_u32(3))
      ..add(_u64(0))
      ..add(_u64(RemoteGgufInspectionPolicy.maximumMetadataEntries + 1));
    expect(
      () => GgufHeaderParser.parse(builder.takeBytes()),
      throwsA(isA<FormatException>()),
    );
  });

  test('range inspector expands exponentially only when incomplete', () async {
    final complete = _gguf({'general.architecture': 'qwen2'});
    final reader = _ExpandingReader(complete);
    final inspector = BoundedRemoteGgufInspector(reader: reader);
    final metadata = await inspector.inspect(
      Uri.parse(
        'https://huggingface.co/publisher/model/resolve/${'a' * 40}/model.gguf',
      ),
    );
    expect(metadata.architecture, 'qwen2');
    expect(reader.requests, [
      RemoteGgufInspectionPolicy.initialBytes,
      RemoteGgufInspectionPolicy.initialBytes * 2,
    ]);
  });
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.response);
  final ResponseBody response;
  ResponseType? responseType;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    responseType = options.responseType;
    return response;
  }

  @override
  void close({bool force = false}) {}
}

class _ExpandingReader implements RemoteRangeReader {
  _ExpandingReader(this.complete);
  final Uint8List complete;
  final requests = <int>[];

  @override
  Future<RemoteRangeResult> read(Uri source, int maximumBytes) async {
    requests.add(maximumBytes);
    if (requests.length == 1) {
      return RemoteRangeResult(complete.sublist(0, complete.length - 1));
    }
    return RemoteRangeResult(complete);
  }
}

Uint8List _gguf(Map<String, Object> metadata) {
  final builder = BytesBuilder()
    ..add(ascii.encode('GGUF'))
    ..add(_u32(3))
    ..add(_u64(0))
    ..add(_u64(metadata.length));
  for (final entry in metadata.entries) {
    builder.add(_string(entry.key));
    if (entry.value is String) {
      builder
        ..add(_u32(8))
        ..add(_string(entry.value as String));
    } else {
      builder
        ..add(_u32(4))
        ..add(_u32(entry.value as int));
    }
  }
  return builder.takeBytes();
}

Uint8List _string(String value) {
  final bytes = utf8.encode(value);
  return Uint8List.fromList([..._u64(bytes.length), ...bytes]);
}

Uint8List _u32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _u64(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.little);
  return data.buffer.asUint8List();
}
