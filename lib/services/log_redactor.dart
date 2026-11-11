class LogRedactor {
  LogRedactor._();

  static const int _defaultMaxChars = 600;

  static final RegExp _jsonSensitiveFieldPattern = RegExp(
    r'("?(?:token|password|authorization|access_token|refresh_token|secret|lat|lng|long|latitude|longitude|created_latitude|created_longitude|pickup_latitude|pickup_longitude|delivered_latitude|delivered_longitude|location_address|mobile|phone|iqama|iqama_number|email)"?\s*:\s*")([^"]*)(")',
    caseSensitive: false,
  );

  static final RegExp _querySensitiveFieldPattern = RegExp(
    r'\b(token|password|authorization|access_token|refresh_token|secret|lat|lng|long|latitude|longitude|created_latitude|created_longitude|pickup_latitude|pickup_longitude|delivered_latitude|delivered_longitude|location_address|mobile|phone|iqama|iqama_number|email)=([^&,\s]+)',
    caseSensitive: false,
  );

  static final RegExp _bearerTokenPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9\-\._~\+/]+=*',
    caseSensitive: false,
  );

  static bool isSensitiveField(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('authorization') ||
        normalized == 'lat' ||
        normalized == 'lng' ||
        normalized == 'long' ||
        normalized.contains('latitude') ||
        normalized.contains('longitude') ||
        normalized.contains('location') ||
        normalized.contains('mobile') ||
        normalized.contains('phone') ||
        normalized.contains('iqama') ||
        normalized.contains('email');
  }

  static String sanitizeText(Object? value, {int maxChars = _defaultMaxChars}) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return '';
    }

    var sanitized = raw.replaceAllMapped(
      _bearerTokenPattern,
      (_) => 'Bearer <redacted>',
    );
    sanitized = sanitized.replaceAllMapped(
      _jsonSensitiveFieldPattern,
      (match) => '${match.group(1)}<redacted>${match.group(3)}',
    );
    sanitized = sanitized.replaceAllMapped(
      _querySensitiveFieldPattern,
      (match) => '${match.group(1)}=<redacted>',
    );

    if (sanitized.length <= maxChars) {
      return sanitized;
    }

    return '${sanitized.substring(0, maxChars)}...';
  }

  static dynamic sanitizeValue(dynamic value, {String? key}) {
    if (key != null && isSensitiveField(key)) {
      return '<redacted>';
    }

    if (value is Map) {
      return value.map(
        (rawKey, rawValue) => MapEntry(
          rawKey.toString(),
          sanitizeValue(rawValue, key: rawKey.toString()),
        ),
      );
    }

    if (value is Iterable) {
      return value.map((item) => sanitizeValue(item)).toList(growable: false);
    }

    if (value is String) {
      return sanitizeText(value);
    }

    if (value is num || value is bool || value == null) {
      return value;
    }

    return sanitizeText(value);
  }

  static Map<String, dynamic>? sanitizeContext(Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) {
      return null;
    }

    return context.map(
      (key, value) => MapEntry(key, sanitizeValue(value, key: key)),
    );
  }
}