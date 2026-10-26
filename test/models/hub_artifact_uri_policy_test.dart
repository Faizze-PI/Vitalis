import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/model_library_policy.dart';

void main() {
  test('produces the canonical query-free immutable transfer URL', () {
    final uri = HubArtifactUriPolicy.resolve(
      repository: 'publisher/model',
      revision: '0123456789012345678901234567890123456789',
      artifactName: 'weights/model.gguf',
    );

    expect(
      uri.toString(),
      'https://huggingface.co/publisher/model/resolve/'
      '0123456789012345678901234567890123456789/weights/model.gguf',
    );
    expect(uri.query, isEmpty);
    expect(uri.userInfo, isEmpty);
    expect(uri.fragment, isEmpty);
  });
}
