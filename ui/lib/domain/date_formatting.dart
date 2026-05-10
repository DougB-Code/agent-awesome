/// Provides shared local date and timestamp formatting helpers.
library;

/// Formats an integer as two decimal digits.
String twoDigitDatePart(int value) {
  return value.toString().padLeft(2, '0');
}

/// Formats a timestamp as a local ISO-like calendar day.
String formatLocalDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${twoDigitDatePart(local.month)}-'
      '${twoDigitDatePart(local.day)}';
}

/// Formats an optional timestamp as a local ISO-like calendar day.
String formatOptionalLocalDate(DateTime? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  return formatLocalDate(value);
}

/// Formats a timestamp as a local date and minute.
String formatLocalDateTime(DateTime value) {
  final local = value.toLocal();
  return '${formatLocalDate(local)} '
      '${twoDigitDatePart(local.hour)}:'
      '${twoDigitDatePart(local.minute)}';
}

/// Formats an optional timestamp as a local date and minute.
String formatOptionalLocalDateTime(DateTime? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  return formatLocalDateTime(value);
}

/// Formats a timestamp as a compact local month/day time label.
String formatLocalMonthDayTime(DateTime value) {
  final local = value.toLocal();
  return '${twoDigitDatePart(local.month)}/${twoDigitDatePart(local.day)} '
      '${twoDigitDatePart(local.hour)}:${twoDigitDatePart(local.minute)}';
}

/// Formats an optional timestamp as a compact local month/day label.
String formatOptionalLocalMonthDay(DateTime? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final local = value.toLocal();
  return '${local.month}/${local.day}';
}
