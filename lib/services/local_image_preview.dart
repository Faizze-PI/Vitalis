import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'local_file_workspace.dart';

abstract final class ImagePreviewPolicy {
  static const maxBytes = 32 * 1024 * 1024; // hardcode: HC-081
  static const maxPixels = 24 * 1024 * 1024; // hardcode: HC-081
  static const edge = 1024; // hardcode: HC-081
}

final class ImagePreviewError implements Exception {
  const ImagePreviewError(this.message);
  final String message;
  @override
  String toString() => message;
}

final class ImagePreviewResult {
  const ImagePreviewResult(this.image, this.sourceWidth, this.sourceHeight);
  final ui.Image image;
  final int sourceWidth, sourceHeight;
}

class LocalImagePreview {
  LocalImagePreview({
    required this.workspace,
    this.maxBytes = ImagePreviewPolicy.maxBytes,
    this.maxPixels = ImagePreviewPolicy.maxPixels,
    this.edge = ImagePreviewPolicy.edge,
  });
  final InputWorkspaceStore workspace;
  final int maxBytes, maxPixels, edge;
  static bool supports(String name) => const {
    'png',
    'jpg',
    'jpeg',
  }.contains(name.split('.').last.toLowerCase()); // hardcode: HC-081
  Future<ImagePreviewResult> load(WorkspaceFile item) async {
    if (!supports(item.name) ||
        item.bytes <= 0 ||
        item.bytes > maxBytes ||
        edge < 1)
      throw const ImagePreviewError(
        'Preview unavailable within the image safety budget. The stored original is unchanged.',
      );
    return workspace.withFile(item.id, (file) async {
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        if (await file.length() != item.bytes ||
            (await sha256.bind(file.openRead()).first).toString() !=
                item.sha256)
          throw const ImagePreviewError(
            'Image bytes changed. Re-import the original before previewing.',
          );
        final head = await file
            .openRead(0, item.bytes < 8 ? item.bytes : 8)
            .fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            ); // hardcode: HC-081: signature only.
        final png =
            head.length >= 8 &&
            head[0] == 137 &&
            head[1] == 80 &&
            head[2] == 78 &&
            head[3] == 71 &&
            head[4] == 13 &&
            head[5] == 10 &&
            head[6] == 26 &&
            head[7] == 10; // hardcode: HC-081
        final jpeg =
            head.length >= 3 &&
            head[0] == 255 &&
            head[1] == 216 &&
            head[2] == 255; // hardcode: HC-081
        if (!png && !jpeg)
          throw const ImagePreviewError(
            'This file is not a readable PNG or JPEG image.',
          );
        buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final w = descriptor.width, h = descriptor.height;
        if (w <= 0 || h <= 0 || w * h > maxPixels)
          throw const ImagePreviewError(
            'Image dimensions exceed the preview safety budget. The stored original is unchanged.',
          );
        final scale = (w > h ? w : h) > edge ? edge / (w > h ? w : h) : 1.0;
        final tw = (w * scale).round(), th = (h * scale).round();
        codec = await descriptor.instantiateCodec(
          targetWidth: tw < 1 ? 1 : tw,
          targetHeight: th < 1 ? 1 : th,
        );
        final frame = await codec.getNextFrame();
        return ImagePreviewResult(frame.image, w, h);
      } on ImagePreviewError {
        rethrow;
      } catch (_) {
        throw const ImagePreviewError(
          'Image preview could not be decoded. The stored file was not modified.',
        );
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer?.dispose();
      }
    });
  }
}
