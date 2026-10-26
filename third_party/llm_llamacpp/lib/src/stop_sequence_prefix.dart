// Copyright 2024 The dart-llm Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Length of text retained until a possible split stop marker is resolved.
int retainedStopPrefixLength(String text, List<String> stopTokens) {
  var retained = 0;
  for (final marker in stopTokens) {
    final maximum = (marker.length - 1).clamp(0, text.length);
    for (var length = maximum; length > retained; length--) {
      if (marker.startsWith(text.substring(text.length - length))) {
        retained = length;
        break;
      }
    }
  }
  return retained;
}
