// SECURITY: LogSanitizer provides regex-based PII masking before log persistence.
// Coverage: Emails, phone numbers (XXX-XXX-XXXX), Android data paths, IP addresses.
// All patterns are compiled once for performance.
// Apply sanitize() to every string before writing to AppLogger.
// This is the ONLY PII masking layer — logs are safe to share after sanitization.
// FILE: lib/utils/log_sanitizer.dart
// PURPOSE: Regex-based PII masking before log persistence
// STATUS: PRODUCTION-HARDENED

/// Static PII masking engine. All regex patterns are compiled once.
/// Apply [sanitize] to every string before writing to [AppLogger].
class LogSanitizer {
  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );

  static final RegExp _phoneRegex = RegExp(r'\d{3}-\d{3}-\d{4}');

  static final RegExp _androidPathRegex = RegExp(
    r'/data/(?:user/\d+|data)/[^\s:]+',
  );

  static final RegExp _windowsPathRegex = RegExp(r'[A-Za-z]:\\[^\s]+');

  static final RegExp _unixPathRegex = RegExp(
    r'(?<!:)\/(?:home|Users|tmp|var|opt|usr\/local)\/[^\s:]+',
  );

  static final RegExp _credentialRegex = RegExp(
    r'(authorization\s*[:=]\s*(?:bearer\s+)?|access_token=|api_key=|token=)[^&\s]+',
    caseSensitive: false,
  );

  static final RegExp _queryValueRegex = RegExp(r'([?&][^=\s]+)=([^&\s]+)');

  static final RegExp _addressRegex = RegExp(r'0x[0-9a-fA-F]+');

  static final RegExp _ipRegex = RegExp(
    r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
  );

  static String sanitize(String raw) {
    var cleaned = raw;
    cleaned = cleaned.replaceAll(_emailRegex, '[EMAIL_REDACTED]');
    cleaned = cleaned.replaceAll(_phoneRegex, '[PHONE_REDACTED]');
    cleaned = cleaned.replaceAll(_androidPathRegex, '[PATH_REDACTED]');
    cleaned = cleaned.replaceAll(_windowsPathRegex, '[PATH_REDACTED]');
    cleaned = cleaned.replaceAll(_unixPathRegex, '[PATH_REDACTED]');
    cleaned = cleaned.replaceAll(_credentialRegex, '[CREDENTIAL_REDACTED]');
    cleaned = cleaned.replaceAllMapped(
      _queryValueRegex,
      (match) => '${match.group(1)}=[QUERY_REDACTED]',
    );
    cleaned = cleaned.replaceAll(_addressRegex, '[ADDRESS_REDACTED]');
    cleaned = cleaned.replaceAll(_ipRegex, '[IP_REDACTED]');
    return cleaned;
  }
}
