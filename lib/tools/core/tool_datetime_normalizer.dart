/// Extracts relative-day intent from the user message for tool argument
/// normalization.
int? extractRelativeDayOffset(String userMessage) {
  final normalized = userMessage.toLowerCase();
  if (normalized.contains('tomorrow') || userMessage.contains('明天')) {
    return 1;
  }
  if (normalized.contains('today') ||
      normalized.contains('tonight') ||
      userMessage.contains('今天') ||
      userMessage.contains('今晚')) {
    return 0;
  }
  return null;
}

/// Rewrites an ISO-like datetime string to the provided relative day offset
/// while preserving the original clock time and timezone suffix.
String? normalizeRelativeIsoDate({
  required String rawIsoText,
  required int dayOffset,
  required DateTime anchor,
}) {
  final parsed = DateTime.tryParse(rawIsoText);
  if (parsed == null) {
    return null;
  }

  final clockTime = _extractClockTime(rawIsoText);
  final normalizedDate = DateTime(
    anchor.year,
    anchor.month,
    anchor.day + dayOffset,
    clockTime?.hour ?? parsed.hour,
    clockTime?.minute ?? parsed.minute,
    clockTime?.second ?? parsed.second,
  );
  return _preserveIsoOffset(rawIsoText, normalizedDate);
}

_ParsedClockTime? _extractClockTime(String rawIsoText) {
  final match = RegExp(r'T(\d{2}):(\d{2})(?::(\d{2}))?').firstMatch(rawIsoText);
  if (match == null) {
    return null;
  }
  return _ParsedClockTime(
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
    second: int.parse(match.group(3) ?? '00'),
  );
}

String _preserveIsoOffset(String rawIsoText, DateTime normalizedDate) {
  final offsetMatch = RegExp(r'(Z|[+-]\d{2}:\d{2})$').firstMatch(rawIsoText);
  final suffix = offsetMatch?.group(1) ?? '';
  return '${normalizedDate.year.toString().padLeft(4, '0')}-'
      '${normalizedDate.month.toString().padLeft(2, '0')}-'
      '${normalizedDate.day.toString().padLeft(2, '0')}T'
      '${normalizedDate.hour.toString().padLeft(2, '0')}:'
      '${normalizedDate.minute.toString().padLeft(2, '0')}:'
      '${normalizedDate.second.toString().padLeft(2, '0')}'
      '$suffix';
}

class _ParsedClockTime {
  final int hour;
  final int minute;
  final int second;

  const _ParsedClockTime({
    required this.hour,
    required this.minute,
    required this.second,
  });
}
