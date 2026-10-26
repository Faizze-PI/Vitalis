import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/models/model_download_job.dart';
import 'package:vitalis_app/providers/model_library_provider.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/model_download_manager.dart';
import 'package:vitalis_app/services/model_hub_client.dart';
import 'package:vitalis_app/services/remote_gguf_inspector.dart';

void main() {
  for (final fails in [false, true]) {
    test(
      'inspection ${fails ? 'failure stays unknown' : 'preserves authoritative metadata'}',
      () async {
        final inspector = _Inspector(fails);
        final library = ModelLibraryProvider(
          hub: _Hub(),
          registry: _Registry(),
          downloads: _Downloads(),
          remoteInspector: inspector,
        );
        addTearDown(library.dispose);
        const variant = GgufVariant(
          repository: 'publisher/fixture',
          revision: 'immutable-revision',
          displayName: 'Disposable',
          files: [GgufFile(name: 'folder/model name.gguf', sizeBytes: 100)],
        );
        final metadata = await library.inspectRemote(variant);
        expect(inspector.source?.scheme, 'https');
        expect(inspector.source?.host, 'huggingface.co');
        expect(inspector.source?.pathSegments, [
          'publisher',
          'fixture',
          'resolve',
          'immutable-revision',
          'folder',
          'model name.gguf',
        ]);
        expect(metadata.complete, !fails);
        expect(metadata.architecture, fails ? isNull : 'fixture-architecture');
        expect(library.installed, isEmpty);
      },
    );
  }
  test(
    'empty artifact set remains unknown without requesting metadata',
    () async {
      final inspector = _Inspector(false);
      final library = ModelLibraryProvider(
        hub: _Hub(),
        registry: _Registry(),
        downloads: _Downloads(),
        remoteInspector: inspector,
      );
      addTearDown(library.dispose);
      expect(
        await library.inspectRemote(
          const GgufVariant(
            repository: 'publisher/fixture',
            revision: 'immutable',
            displayName: 'Disposable',
            files: [],
          ),
        ),
        same(RemoteGgufMetadata.unknown),
      );
      expect(inspector.source, isNull);
    },
  );
}

class _Inspector implements RemoteGgufInspector {
  _Inspector(this.fails);
  final bool fails;
  Uri? source;
  @override
  Future<RemoteGgufMetadata> inspect(Uri source) async {
    this.source = source;
    if (fails) throw StateError('fixture unavailable metadata');
    return const RemoteGgufMetadata(
      complete: true,
      architecture: 'fixture-architecture',
    );
  }
}

class _Hub implements ModelHubClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Hub operation');
}

class _Registry implements ModelRegistryService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected registry operation');
}

class _Downloads implements ModelDownloadManager {
  @override
  void addJobListener(void Function(ModelDownloadJob) listener) {}
  @override
  void removeJobListener(void Function(ModelDownloadJob) listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected transfer operation');
}
