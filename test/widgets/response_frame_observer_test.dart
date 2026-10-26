import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/widgets/response_frame_observer.dart';

void main() {
  testWidgets('reports after paint once per response, not every rebuild', (
    tester,
  ) async {
    final first = Object();
    final second = Object();
    final observed = <Object>[];
    Widget build(Object identity, {bool offstage = false}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Offstage(
        offstage: offstage,
        child: ResponseFrameObserver(
          responseIdentity: identity,
          onFrame: observed.add,
          child: const Text('Disposable response'),
        ),
      ),
    );
    await tester.pumpWidget(build(first, offstage: true));
    expect(
      observed,
      isEmpty,
      reason: 'A layout/build without paint is not rendering',
    );
    await tester.pumpWidget(build(first));
    expect(observed, [first]);
    await tester.pumpWidget(build(first));
    await tester.pump();
    expect(observed, [first]);
    await tester.pumpWidget(build(second));
    expect(observed, [first, second]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(observed, [first, second]);
  });
}
