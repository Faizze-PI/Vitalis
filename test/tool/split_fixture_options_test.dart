import 'package:flutter_test/flutter_test.dart';

import '../../tool/prepare_split_fixture.dart';

void main() {
  List<String> options({
    String size = '300M',
    String model = 'path with spaces/model.gguf',
  }) => [
    '--model',
    model,
    '--splitter',
    'splitter',
    '--provenance',
    'receipt.json',
    '--output',
    'new-fixture',
    '--max-shard-size',
    size,
  ];

  test('fixture options preserve spaces without invoking a shell', () {
    final parsed = parseSplitFixtureOptions(options());
    expect(parsed['--model'], 'path with spaces/model.gguf');
    expect(() => parsed['--output'] = 'other', throwsUnsupportedError);
  });
  for (final size in ['0M', '-1M', '1', '1m', '1M --delete-splits']) {
    test('fixture rejects invalid split limit $size', () {
      expect(
        () => parseSplitFixtureOptions(options(size: size)),
        throwsFormatException,
      );
    });
  }
  test(
    'fixture rejects missing duplicate unknown and control-character options',
    () {
      expect(() => parseSplitFixtureOptions([]), throwsFormatException);
      final duplicate = options()..[0] = '--output';
      expect(() => parseSplitFixtureOptions(duplicate), throwsFormatException);
      final unknown = options()..[0] = '--unsafe';
      expect(() => parseSplitFixtureOptions(unknown), throwsFormatException);
      expect(
        () => parseSplitFixtureOptions(options(model: 'model\nsecret')),
        throwsFormatException,
      );
    },
  );
}
