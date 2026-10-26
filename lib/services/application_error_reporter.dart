import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

/// The app's framework/platform diagnostic boundary; injectable for testing.
class ApplicationErrorReporter {
  ApplicationErrorReporter({
    required AppLogger logger,
    FlutterExceptionHandler? presenter,
  }) : _logger = logger,
       _presenter = presenter;
  final AppLogger _logger;
  final FlutterExceptionHandler? _presenter;

  void framework(FlutterErrorDetails details) {
    final message = 'FlutterError (${details.exception.runtimeType})';
    (_presenter ?? FlutterError.presentError)(
      FlutterErrorDetails(
        exception: FlutterError(message),
        // Null makes Flutter's profile/release presenter generate a fresh stack.
        stack: StackTrace.empty,
        library: 'VITALIS',
        silent: details.silent,
      ),
    );
    _logger.errorSync(message);
  }

  bool platform(Object error, StackTrace stack) {
    _logger.errorSync('Fatal error (${error.runtimeType})');
    return true;
  }
}
