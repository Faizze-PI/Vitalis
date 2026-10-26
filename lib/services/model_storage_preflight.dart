import 'package:flutter/services.dart';

/// On-demand storage preflight, separate from frequent safety telemetry.
Future<int?> queryAllocatableModelStorage() async {
  const channel = MethodChannel('vitalis/model_storage');
  try {
    final value = await channel.invokeMethod<Object?>('allocatableBytes');
    return value is int && value >= 0 ? value : null;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
