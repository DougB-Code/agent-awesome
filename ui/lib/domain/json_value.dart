/// Provides shared coercion helpers for decoded JSON-like values.
library;

/// Converts a dynamic value to a JSON object map when possible.
Map<String, dynamic> jsonObject(dynamic value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

/// Converts a dynamic list into JSON object maps.
List<Map<String, dynamic>> jsonObjectList(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList();
}

/// Converts any decoded map-like value into a string-keyed dynamic map.
Map<String, dynamic> jsonStringKeyMap(dynamic value) {
  if (value is! Map) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

/// Converts a dynamic scalar to a non-empty string or fallback.
String stringValue(dynamic value, {String fallback = '', bool trim = false}) {
  if (value == null) {
    return fallback;
  }
  final text = trim ? value.toString().trim() : value.toString();
  return text.isEmpty ? fallback : text;
}

/// Converts a dynamic list into non-empty strings.
List<String> stringList(dynamic value, {bool trim = false}) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => stringValue(item, trim: trim))
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Converts a dynamic value to a bool.
bool boolValue(dynamic value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

/// Converts a dynamic value to a nullable bool.
bool? nullableBoolValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return null;
}

/// Converts a dynamic value to an integer.
int intValue(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

/// Converts a dynamic value to a double.
double doubleValue(dynamic value, {double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

/// Converts a dynamic value to a 0..1 normalized double.
double normalizedDouble(dynamic value, {double fallback = 0}) {
  return doubleValue(value, fallback: fallback).clamp(0, 1).toDouble();
}

/// Parses an optional timestamp from a dynamic scalar.
DateTime? parseOptionalDateTime(dynamic value, {bool trim = false}) {
  final text = stringValue(value, trim: trim);
  if (text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
