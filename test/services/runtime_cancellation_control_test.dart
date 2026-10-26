import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/runtime_cancellation_control.dart';

void main() {
  late RuntimeCancellationControl control;
  late List<int> requested;
  late List<int> released;
  var clock = 0;
  setUp(() {
    clock = 0;
    requested = [];
    released = [];
    control = RuntimeCancellationControl(
      readMonotonicMicros: () => clock,
      requestCancel: requested.add,
      releaseHandle: released.add,
    );
  });
  test('Stop before handle is replayed through native control', () {
    control.register(7);
    expect(control.request(7), isTrue);
    expect(requested, isEmpty);
    clock = 100;
    expect(control.attachHandle(7, 123), isTrue);
    expect(requested, [123]);
  });
  test('normal or error terminal outcome retires Stop timing state', () {
    control.register(7);
    control.attachHandle(7, 123);
    control.request(7);
    clock = 100;
    expect(control.finish(7), 100);
    expect(released, [123]);
    expect(control.isRequested(7), isFalse);
    expect(control.retainedRequestCount, 0);
  });

  test('repeated Stop retains its first monotonic deadline', () {
    control.register(7);
    control.attachHandle(7, 123);
    clock = 10;
    control.request(7);
    clock = 40;
    control.request(7);
    clock = 100;
    expect(control.finish(7), 90);
    expect(requested, [123, 123]);
    expect(released, [123]);
  });

  test('completed and unknown requests cannot recreate Stop intent', () {
    expect(control.request(7), isFalse);
    control.register(7);
    expect(control.finish(7), isNull);
    expect(control.finish(7), isNull);
    expect(control.request(7), isFalse);
    expect(control.retainedRequestCount, 0);
    expect(control.attachHandle(7, 123), isFalse);
    expect(released, [123]);
    expect(requested, isEmpty);
  });

  test('duplicate transferred references cannot replace the owned handle', () {
    control.register(7);
    expect(control.hasHandle(7), isFalse);
    expect(control.attachHandle(7, 123), isTrue);
    expect(control.hasHandle(7), isTrue);
    expect(control.attachHandle(7, 456), isFalse);
    control.request(7);
    expect(requested, [123]);
    expect(released, [456]);
    control.finish(7);
    expect(released, [456, 123]);
  });

  test('null handles never enter native control', () {
    control.register(7);
    expect(control.attachHandle(7, 0), isFalse);
    control.request(7);
    expect(requested, isEmpty);
    expect(released, isEmpty);
    control.finish(7);
    expect(control.retainedRequestCount, 0);
  });

  for (final stopBeforePublication in [false, true]) {
    test('tagged arm64 handle preserves Stop and release bits '
        '(early Stop: $stopBeforePublication)', () {
      // Android heap tags can set bit 63; Dart exposes a signed raw address.
      const address = 0xb400000000001230;
      expect(address, isNegative);
      control.register(7);
      if (stopBeforePublication) control.request(7);
      expect(control.attachHandle(7, address), isTrue);
      expect(control.hasHandle(7), isTrue);
      if (!stopBeforePublication) control.request(7);
      expect(requested, [address]);
      control.finish(7);
      expect(released, [address]);
      expect(control.retainedRequestCount, 0);
    });
  }

  test('late tagged handle releases its transferred reference', () {
    const address = 0xb400000000001230;
    expect(control.attachHandle(7, address), isFalse);
    expect(released, [address]);
    expect(requested, isEmpty);
  });

  test('duplicate or invalid request identity is rejected', () {
    expect(() => control.register(-1), throwsArgumentError);
    control.register(7);
    expect(() => control.register(7), throwsArgumentError);
    expect(control.retainedRequestCount, 1);
    control.finish(7);
  });

  test('bridge request failure retains Stop intent for retry', () {
    var reject = true;
    control = RuntimeCancellationControl(
      readMonotonicMicros: () => clock,
      requestCancel: (address) {
        if (reject) throw StateError('injected control failure');
        requested.add(address);
      },
      releaseHandle: released.add,
    );
    control.register(7);
    control.attachHandle(7, 123);
    expect(() => control.request(7), throwsStateError);
    expect(control.isRequested(7), isTrue);
    reject = false;
    clock = 100;
    control.request(7);
    expect(control.finish(7), 100);
    expect(requested, [123]);
  });

  test('reference release failure does not forget the retained owner', () {
    var reject = true;
    control = RuntimeCancellationControl(
      readMonotonicMicros: () => clock,
      requestCancel: requested.add,
      releaseHandle: (address) {
        if (reject) throw StateError('injected release failure');
        released.add(address);
      },
    );
    control.register(7);
    control.attachHandle(7, 123);
    control.request(7);
    expect(() => control.finish(7), throwsStateError);
    expect(control.hasHandle(7), isTrue);
    expect(control.isRequested(7), isTrue);
    reject = false;
    control.finish(7);
    expect(released, [123]);
    expect(control.retainedRequestCount, 0);
  });

  test('final cleanup retires all request and handle state', () {
    for (final id in [7, 8]) {
      control.register(id);
      control.attachHandle(id, id);
      control.request(id);
    }
    control.clear();
    expect(released, [7, 8]);
    expect(control.retainedRequestCount, 0);
    control.clear();
    expect(released, [7, 8]);
  });
}
