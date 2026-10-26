import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/services/model_downloader.dart';
import 'package:vitalis_app/utils/app_logger.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled adapter requires a configured installation authority',
    () async {
      await expectLater(
        AndroidModelDownloadEnvironment().persistVerifiedModel(
          'unused-fixture.gguf',
          ModelDownloadSpec.bundled,
        ),
        throwsStateError,
      );
    },
  );
  for (final field in ['url', 'file', 'size', 'hash']) {
    test(
      'bundled adapter rejects changed manifest $field before authority work',
      () async {
        final authority = _Installer();
        addTearDown(authority.close);
        final spec = ModelDownloadSpec(
          url: field == 'url'
              ? '${BundledModelManifest.downloadUrl}?download=true'
              : BundledModelManifest.downloadUrl,
          fileName: field == 'file'
              ? 'different.gguf'
              : BundledModelManifest.fileName,
          byteSize: field == 'size' ? 1 : BundledModelManifest.byteSize,
          sha256: field == 'hash' ? 'untrusted' : BundledModelManifest.sha256,
        );
        await expectLater(
          AndroidModelDownloadEnvironment(
            registry: authority,
          ).persistVerifiedModel('unused-fixture.gguf', spec),
          throwsStateError,
        );
        expect(authority.paths, isEmpty);
      },
    );
  }
  test(
    'bundled adapter waits for authoritative installation acknowledgement',
    () async {
      final authority = _Installer();
      addTearDown(authority.close);
      final environment = AndroidModelDownloadEnvironment(registry: authority);
      var complete = false;
      final operation = environment
          .persistVerifiedModel('disposable.gguf', ModelDownloadSpec.bundled)
          .then((_) => complete = true);
      await Future<void>.delayed(Duration.zero);
      expect(authority.paths, ['disposable.gguf']);
      expect(complete, isFalse);
      authority.finished.complete(_installed('disposable.gguf'));
      await operation;
      expect(complete, isTrue);
    },
  );

  test(
    'bundled adapter propagates rejected authoritative persistence',
    () async {
      final authority = _Installer();
      addTearDown(authority.close);
      final environment = AndroidModelDownloadEnvironment(registry: authority);
      final failure = StateError('Injected persistence failure');
      final operation = environment.persistVerifiedModel(
        'disposable.gguf',
        ModelDownloadSpec.bundled,
      );
      final observed = expectLater(operation, throwsA(same(failure)));
      authority.finished.completeError(failure);
      await observed;
      expect(authority.paths, ['disposable.gguf']);
    },
  );
  test('untrusted synthetic GGUF cannot acquire bundled identity', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vitalis_adapter_failure_',
    );
    addTearDown(() async {
      await DatabaseHelper.instance.close();
      await AppLogger.instance.flush();
      await directory.delete(recursive: true);
    });
    const channel = MethodChannel('com.tekartik.sqflite');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDatabasesPath') return directory.path;
      throw PlatformException(
        code: 'injected_disk_failure',
        message: '/private/token=secret',
      );
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final header = ByteData(24)
      ..setUint32(0, 0x46554747, Endian.little)
      ..setUint32(4, 3, Endian.little)
      ..setUint64(8, 0, Endian.little)
      ..setUint64(16, 0, Endian.little);
    final bytes = header.buffer.asUint8List();
    final file = File('${directory.path}/disposable.gguf');
    await file.writeAsBytes(bytes);
    final environment = AndroidModelDownloadEnvironment();
    await expectLater(
      environment.persistVerifiedModel(
        file.path,
        ModelDownloadSpec(
          url:
              'https://huggingface.co/disposable/repo/resolve/immutable/model.gguf',
          fileName: 'disposable.gguf',
          byteSize: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        ),
      ),
      throwsA(anything),
    );
    expect(await file.readAsBytes(), bytes);
  });
}

ModelDescriptor _installed(String path) => ModelDescriptor(
  id: BundledModelManifest.id,
  displayName: BundledModelManifest.displayName,
  source: BundledModelManifest.source,
  compatibilityStatus: 'compatible',
  localPath: path,
  sha256: BundledModelManifest.sha256,
  byteSize: BundledModelManifest.byteSize,
  installationState: 'installed',
);

final class _Installer extends ModelRegistryService {
  final paths = <String>[];
  final finished = Completer<ModelDescriptor>();
  @override
  Future<ModelDescriptor> installBundledModel(String primaryPath) {
    paths.add(primaryPath);
    return finished.future;
  }
}
