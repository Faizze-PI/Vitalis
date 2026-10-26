// Copyright 2026 VITALIS contributors. MIT license; see LICENSE.
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Audited template content, never model names or untrusted capability flags.
abstract final class VerifiedThinkingTemplates {
  // Derived from the immutable bundled GGUF and publisher template branches.
  static const qwen35Sha256 =
      '7f0e529032c25183bcd66c7f238da2d377f43be754a94e2725a58c4e16d2ed67'; // hardcode: HC-066

  static bool supports(String? template) =>
      template != null &&
      sha256.convert(utf8.encode(template)).toString() == qwen35Sha256;
}
