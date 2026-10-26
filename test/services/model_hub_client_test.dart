import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/model_hub_client.dart';

void main() {
  late HttpServer server;
  late HuggingFaceModelHubClient client;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dio = Dio(
      BaseOptions(baseUrl: 'http://${server.address.host}:${server.port}'),
    );
    client = HuggingFaceModelHubClient(dio: dio);
  });

  tearDown(() => server.close(force: true));

  test(
    'search returns only public GGUF models with immutable identity',
    () async {
      final response = client.search(query: 'qwen');
      final request = await server.first;
      expect(request.uri.path, '/api/models');
      expect(request.uri.queryParameters['filter'], 'gguf');
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode([
            {
              'id': 'publisher/public-model',
              'sha': 'a' * 40,
              'downloads': 42,
              'gated': false,
              'tags': ['gguf'],
              'safetensors': {'total': 4000000001},
            },
            {'id': 'publisher/gated-model', 'sha': 'b' * 40, 'gated': true},
          ]),
        );
      await request.response.close();

      final page = await response;
      expect(page.models, hasLength(1));
      expect(page.models.single.isLargeModel, isTrue);
    },
  );

  test('search sends an explicit publisher filter', () async {
    final response = client.search(query: 'qwen', publisher: 'publisher');
    final request = await server.first;
    expect(request.uri.queryParameters['author'], 'publisher');
    request.response
      ..headers.contentType = ContentType.json
      ..write('[]');
    await request.response.close();
    expect((await response).models, isEmpty);
  });

  test('repository resolves the latest immutable public revision', () async {
    final response = client.repository('publisher/model');
    final request = await server.first;
    expect(request.uri.path, '/api/models/publisher/model');
    request.response
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'id': 'publisher/model',
          'sha': 'e' * 40,
          'author': 'publisher',
          'downloads': 1,
          'gated': false,
          'tags': ['gguf'],
        }),
      );
    await request.response.close();
    expect((await response).revision, 'e' * 40);
  });

  test('artifact resolver groups complete split GGUF shards', () async {
    final response = client.resolveGgufArtifacts(
      repository: 'publisher/model',
      revision: 'c' * 40,
    );
    final request = await server.first;
    request.response
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'sha': 'c' * 40,
          'gated': false,
          'siblings': [
            {
              'rfilename': 'model-Q4_K_M-00001-of-00002.gguf',
              'lfs': {'size': 10, 'sha256': '1' * 64},
            },
            {
              'rfilename': 'model-Q4_K_M-00002-of-00002.gguf',
              'lfs': {'size': 12, 'sha256': '2' * 64},
            },
            {'rfilename': 'README.md'},
          ],
        }),
      );
    await request.response.close();

    final variants = await response;
    expect(variants, hasLength(1));
    expect(variants.single.isSplit, isTrue);
    expect(variants.single.totalBytes, 22);
    expect(variants.single.quantization, 'Q4_K_M');
    expect(variants.single.files.map((file) => file.shardIndex), [0, 1]);
  });

  for (final indices in [
    [0, 2],
    [1, 1],
    [1, 3],
  ]) {
    test(
      'artifact resolver rejects incomplete or duplicate split indices $indices',
      () async {
        final response = client.resolveGgufArtifacts(
          repository: 'publisher/model',
          revision: 'c' * 40,
        );
        final request = await server.first;
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'sha': 'c' * 40,
              'gated': false,
              'siblings': [
                for (final index in indices)
                  {
                    'rfilename':
                        'model-Q4_K_M-${index.toString().padLeft(5, '0')}-of-00002.gguf',
                    'lfs': {'size': 10, 'sha256': '1' * 64},
                  },
              ],
            }),
          );
        await request.response.close();
        expect(await response, isEmpty);
      },
    );
  }

  test('artifact resolver rejects gated repositories', () async {
    final response = client.resolveGgufArtifacts(
      repository: 'publisher/model',
      revision: 'd' * 40,
    );
    final request = await server.first;
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'sha': 'd' * 40, 'gated': true, 'siblings': []}));
    await request.response.close();

    await expectLater(response, throwsA(isA<ModelHubAccessException>()));
  });
}
