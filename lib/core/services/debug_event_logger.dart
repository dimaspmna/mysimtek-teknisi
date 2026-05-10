import 'dart:convert';

import 'package:flutter/foundation.dart';

class DebugEventLogger {
  static const _prefix = 'SIMTEK_DEBUG';

  static void log(
    String event, {
    String scope = 'app',
    Map<String, dynamic>? data,
  }) {
    if (!kDebugMode) return;

    final payload = <String, dynamic>{
      'ts': DateTime.now().toIso8601String(),
      'scope': scope,
      'event': event,
      'data': _sanitize(data ?? const <String, dynamic>{}),
    };

    debugPrint('$_prefix ${jsonEncode(payload)}');
  }

  static Map<String, dynamic> _sanitize(Map<String, dynamic> source) {
    final sanitized = <String, dynamic>{};
    source.forEach((key, value) {
      sanitized[key] = _sanitizeValue(value);
    });
    return sanitized;
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Map<String, dynamic>) return _sanitize(value);
    if (value is Iterable) return value.map(_sanitizeValue).toList();
    return value.toString();
  }
}
