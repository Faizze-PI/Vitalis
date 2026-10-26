import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/model_descriptor.dart';

void main() {
  test('persisted thinking flag cannot authorize an unverified template', () {
    final descriptor = ModelDescriptor.fromMap({
      'id': 'fixture',
      'display_name': 'Fixture',
      'source': 'imported',
      'compatibility_status': 'compatible',
      'supports_thinking': 1,
      'chat_template': '{{ enable_thinking }} /no_think',
    });
    expect(descriptor.supportsThinking, isFalse);
  });
}
