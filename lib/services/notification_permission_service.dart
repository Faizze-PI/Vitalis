import 'dart:io';

import 'package:flutter/services.dart';

enum NotificationPermissionStatus { granted, denied, notRequired, unavailable }

/// Requests notification visibility only from a user-initiated download flow.
final class NotificationPermissionService {
  NotificationPermissionService({
    MethodChannel channel = const MethodChannel('vitalis/device_safety'),
    bool Function()? isAndroid,
  }) : _channel = channel,
       _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  Future<NotificationPermissionStatus> ensureForDownload() async {
    if (!_isAndroid()) return NotificationPermissionStatus.notRequired;
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'notificationPermission',
      );
      return switch (value?['status']) {
        'granted' => NotificationPermissionStatus.granted,
        'not_required' => NotificationPermissionStatus.notRequired,
        'denied' ||
        'request_in_progress' => NotificationPermissionStatus.denied,
        _ => NotificationPermissionStatus.unavailable,
      };
    } on PlatformException {
      return NotificationPermissionStatus.unavailable;
    } on MissingPluginException {
      return NotificationPermissionStatus.unavailable;
    }
  }
}
