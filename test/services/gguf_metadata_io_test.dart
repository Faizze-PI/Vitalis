import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';

void main() {
  for (final synchronous in [false, true]) {
    test(
      'UTF-8 model metadata survives decoding (sync: $synchronous)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'gguf-unicode-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/fixture.gguf');
        const value = '模型 🌍 नमस्ते';
        await file.writeAsBytes(_stringMetadata(value));
        final result = synchronous
            ? GgufMetadata.fromFileSync(file.path)
            : await GgufMetadata.fromFile(file.path);
        expect(result.name, value);
      },
    );

    test('invalid UTF-8 metadata is rejected (sync: $synchronous)', () async {
      final directory = await Directory.systemTemp.createTemp('gguf-encoding-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/fixture.gguf');
      final bytes = _stringMetadata('a');
      bytes[bytes.length - 1] = 0xff;
      await file.writeAsBytes(bytes);
      Future<GgufMetadata> read() async => synchronous
          ? GgufMetadata.fromFileSync(file.path)
          : await GgufMetadata.fromFile(file.path);
      await expectLater(read(), throwsFormatException);
    });
  }

  test(
    'large vocabulary metadata avoids per-token filesystem round trips',
    () async {
      final directory = await Directory.systemTemp.createTemp('gguf-reader-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/fixture.gguf');
      final bytes = BytesBuilder();
      void number(int value, int width) {
        final data = ByteData(width);
        if (width == 4) {
          data.setUint32(0, value, Endian.little);
        } else {
          data.setUint64(0, value, Endian.little);
        }
        bytes.add(data.buffer.asUint8List());
      }

      void string(String value) {
        final encoded = utf8.encode(value);
        number(encoded.length, 8);
        bytes.add(encoded);
      }

      number(0x46554747, 4);
      number(3, 4);
      number(0, 8);
      number(2, 8);
      string('tokenizer.ggml.tokens');
      number(9, 4);
      number(8, 4);
      number(1001, 8);
      for (var index = 0; index < 1001; index++) {
        string('token-${'x' * 128}');
      }
      string('general.name');
      number(8, 4);
      string('After vocabulary');
      await file.writeAsBytes(bytes.takeBytes());
      final observed = _ObservedFile(file);
      final result = await IOOverrides.runZoned(
        () => GgufMetadata.fromFile(file.path),
        createFile: (_) => observed,
      );
      expect(result.vocabSize, 1001);
      expect(result.name, 'After vocabulary');
      expect(
        observed.ioCalls,
        lessThan(32),
        reason: 'Sequential vocabulary skips must use buffered file access',
      );
    },
  );
  test('metadata strings crossing read windows retain every byte', () async {
    final directory = await Directory.systemTemp.createTemp('gguf-window-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/fixture.gguf');
    final value = 'window-boundary-' * 10000;
    await file.writeAsBytes(_stringMetadata(value));
    final result = await GgufMetadata.fromFile(file.path);
    expect(result.name, value);
  });

  test(
    'declared metadata past EOF fails before allocating its payload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gguf-truncated-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/fixture.gguf');
      await file.writeAsBytes(
        _stringMetadata('short', declaredLength: 1 << 40),
      );
      await expectLater(
        GgufMetadata.fromFile(file.path),
        throwsFormatException,
      );
    },
  );
}

Uint8List _stringMetadata(String value, {int? declaredLength}) {
  final key = utf8.encode('general.name');
  final payload = utf8.encode(value);
  final header = ByteData(24)
    ..setUint32(0, 0x46554747, Endian.little)
    ..setUint32(4, 3, Endian.little)
    ..setUint64(8, 0, Endian.little)
    ..setUint64(16, 1, Endian.little);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(
          (ByteData(
            8,
          )..setUint64(0, key.length, Endian.little)).buffer.asUint8List(),
        )
        ..add(key)
        ..add(
          (ByteData(4)..setUint32(0, 8, Endian.little)).buffer.asUint8List(),
        )
        ..add(
          (ByteData(8)
                ..setUint64(0, declaredLength ?? payload.length, Endian.little))
              .buffer
              .asUint8List(),
        )
        ..add(payload))
      .takeBytes();
}

final class _ObservedFile implements File {
  _ObservedFile(this.actual);
  final File actual;
  int ioCalls = 0;

  @override
  Future<bool> exists() => actual.exists();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _ObservedHandle(await actual.open(mode: mode), () => ioCalls++);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ObservedHandle implements RandomAccessFile {
  _ObservedHandle(this.actual, this.observe);
  final RandomAccessFile actual;
  final void Function() observe;

  @override
  Future<Uint8List> read(int count) {
    observe();
    return actual.read(count);
  }

  @override
  Future<int> length() {
    observe();
    return actual.length();
  }

  @override
  Future<int> position() {
    observe();
    return actual.position();
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    observe();
    await actual.setPosition(position);
    return this;
  }

  @override
  Future<void> close() => actual.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
