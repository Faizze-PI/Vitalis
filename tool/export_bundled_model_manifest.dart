import 'dart:convert';
import 'dart:io';

import '../lib/models/bundled_model_manifest.dart';

/// Dependency-free export for CI before Pub dependency resolution.
Map<String, Object> bundledModelFixtureManifest() => {
  'fileName': BundledModelManifest.fileName,
  'sha256': BundledModelManifest.sha256,
  'url': BundledModelManifest.downloadUrl,
  'byteSize': BundledModelManifest.byteSize,
  'revision': BundledModelManifest.revision,
};

void main() {
  stdout.writeln(jsonEncode(bundledModelFixtureManifest()));
}
