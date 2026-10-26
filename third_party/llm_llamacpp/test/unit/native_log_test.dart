import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => NativeLog.sink = null);

  test('is silent until a structured sink is injected', () {
    NativeLog.debug('model at C:\\private\\model.gguf');
    expect(NativeLog.sink, isNull);
  });

  test('redacts paths credentials query values and native addresses', () {
    final events = <String>[];
    NativeLog.sink = (level, message) => events.add('${level.name}:$message');

    NativeLog.error(
      'C:\\Users\\person\\model.gguf '
      '/home/person/model.gguf '
      'authorization=secret token=abc 0xDEADBEEF Bearer private.jwt',
    );

    expect(events, hasLength(1));
    expect(events.single, isNot(contains('person')));
    expect(events.single, isNot(contains('secret')));
    expect(events.single, isNot(contains('DEADBEEF')));
    expect(events.single, contains('[local-path]'));
    expect(events.single, contains('[redacted]'));
    expect(events.single, contains('[address]'));
  });
}
