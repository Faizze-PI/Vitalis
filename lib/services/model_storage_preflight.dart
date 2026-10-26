import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// On-demand storage preflight, separate from frequent safety telemetry.
Future<int?> queryAllocatableModelStorage() async {
  const channel = MethodChannel('vitalis/model_storage');
  try {
    final path = Platform.isWindows
        ? (await getApplicationSupportDirectory()).path
        : null;
    final value = await channel.invokeMethod<Object?>('allocatableBytes', path);
    return value is int && value >= 0 ? value : null;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
