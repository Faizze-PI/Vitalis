import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/local_image_preview.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalFileWorkspace store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('image-preview-');
    store = LocalFileWorkspace(
      root: () async => root,
      availableBytes: () async => 10000000,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<WorkspaceFile> image() {
    final data = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAD0lEQVR4nGP8zwABIPo/ABMJAv9xhkSYAAAAAElFTkSuQmCC',
    );
    return store.import(
      name: 'input.png',
      expectedBytes: data.length,
      source: Stream.value(data),
    );
  }

  test(
    'decodes real RGB image and produces bounded aspect-preserving thumbnail',
    () async {
      final file = await image();
      final result = await LocalImagePreview(
        workspace: store,
        edge: 1,
      ).load(file);
      try {
        expect(result.sourceWidth, 2);
        expect(result.sourceHeight, 2);
        expect(result.image.width, 1);
        expect(result.image.height, 1);
      } finally {
        result.image.dispose();
      }
      expect((await store.list()).single.sha256, file.sha256);
    },
  );
  test(
    'rejects file and pixel budgets without changing stored originals',
    () async {
      final file = await image();
      await expectLater(
        LocalImagePreview(workspace: store, maxBytes: 1).load(file),
        throwsA(isA<ImagePreviewError>()),
      );
      await expectLater(
        LocalImagePreview(workspace: store, maxPixels: 3).load(file),
        throwsA(isA<ImagePreviewError>()),
      );
      expect(await store.list(), hasLength(1));
    },
  );
  test('hash drift and invalid image data never produce a preview', () async {
    final file = await image();
    await store.withFile(
      file.id,
      (f) => f.writeAsBytes(List.filled(file.bytes, 0)),
    );
    await expectLater(
      LocalImagePreview(workspace: store).load(file),
      throwsA(isA<ImagePreviewError>()),
    );
    final bad = await store.import(
      name: 'bad.png',
      expectedBytes: 4,
      source: Stream.value([1, 2, 3, 4]),
    );
    await expectLater(
      LocalImagePreview(workspace: store).load(bad),
      throwsA(isA<ImagePreviewError>()),
    );
  });
  test(
    'JPEG preview retains aspect ratio and decoder remains usable after rejection',
    () async {
      final data = base64Decode(
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAACAAQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDmqKKK908U/9k=',
      );
      final file = await store.import(
        name: 'test.jpeg',
        expectedBytes: data.length,
        source: Stream.value(data),
      );
      await expectLater(
        LocalImagePreview(workspace: store, maxPixels: 1).load(file),
        throwsA(isA<ImagePreviewError>()),
      );
      final result = await LocalImagePreview(
        workspace: store,
        edge: 2,
      ).load(file);
      try {
        expect(result.sourceWidth, 4);
        expect(result.sourceHeight, 2);
        expect(result.image.width, 2);
        expect(result.image.height, 1);
      } finally {
        result.image.dispose();
      }
    },
  );
}
