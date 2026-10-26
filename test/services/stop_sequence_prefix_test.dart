import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/stop_sequence_prefix.dart';

void main() {
  test('ordinary output is not delayed by an unrelated stop marker', () {
    expect(retainedStopPrefixLength('Hello', ['<|im_end|>']), 0);
  });

  test('retains only the actual split-marker prefix', () {
    expect(retainedStopPrefixLength('Hello<|im_', ['<|im_end|>']), 5);
    expect(retainedStopPrefixLength('Hello<', ['<|im_end|>']), 1);
    expect(retainedStopPrefixLength('Hello<|wrong', ['<|im_end|>']), 0);
  });

  test('uses longest matching prefix across overlapping markers', () {
    expect(retainedStopPrefixLength('textabc', ['abcd', 'bcde']), 3);
    expect(retainedStopPrefixLength('textab', ['abcd', 'bcde']), 2);
  });

  test('empty text and absent stop markers retain nothing', () {
    expect(retainedStopPrefixLength('', ['stop']), 0);
    expect(retainedStopPrefixLength('visible', []), 0);
    expect(retainedStopPrefixLength('visible', ['']), 0);
    expect(retainedStopPrefixLength('visible', ['x']), 0);
  });

  test('Unicode marker prefixes use the actual text boundary', () {
    expect(retainedStopPrefixLength('你好🙂', ['🙂结束']), 2);
    expect(retainedStopPrefixLength('你好', ['🙂结束']), 0);
  });

  test('every split of a marker retains exactly the unfinished suffix', () {
    const marker = '<|im_end|>';
    for (var split = 1; split < marker.length; split++) {
      final text = 'visible${marker.substring(0, split)}';
      expect(retainedStopPrefixLength(text, [marker]), split);
    }
  });
}
