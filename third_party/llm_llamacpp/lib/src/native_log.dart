enum NativeLogLevel { debug, info, warning, error }

typedef NativeLogSink =
    void Function(NativeLogLevel level, String redactedMessage);

/// Opt-in structured diagnostics for the native runtime.
///
/// No sink is installed by default, so release builds are silent. Applications
/// may inject a local sink; sensitive paths, tokens, query values, and native
/// addresses are redacted before the event crosses the package boundary.
abstract final class NativeLog {
  static NativeLogSink? sink;

  static void debug(Object? message) => _emit(NativeLogLevel.debug, message);
  static void info(Object? message) => _emit(NativeLogLevel.info, message);
  static void warning(Object? message) =>
      _emit(NativeLogLevel.warning, message);
  static void error(Object? message) => _emit(NativeLogLevel.error, message);

  static void _emit(NativeLogLevel level, Object? message) {
    final destination = sink;
    if (destination == null) return;
    destination(level, redact(message?.toString() ?? ''));
  }

  static String redact(String message) => message
      .replaceAll(RegExp(r'0x[0-9a-fA-F]+'), '[address]')
      .replaceAll(
        RegExp(
          r'(authorization|token|access_token|api_key)=([^&\s]+)',
          caseSensitive: false,
        ),
        r'$1=[redacted]',
      )
      .replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
        'Bearer [redacted]',
      )
      .replaceAll(RegExp(r'[A-Za-z]:\\[^\s]+'), '[local-path]')
      .replaceAll(RegExp(r'(?<!:)\/(?:[^\s/:]+\/)+[^\s:]*'), '[local-path]');
}
