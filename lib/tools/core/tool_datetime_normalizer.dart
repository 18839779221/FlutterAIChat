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

/// Normalizes a natural-language datetime phrase into a local ISO wall-time
/// string such as `2026-04-13T21:00:00`.
String? normalizeNaturalLanguageDateTime({
  required String rawText,
  required DateTime anchor,
  int? fallbackDayOffset,
}) {
  final normalizedText = rawText.trim().replaceAll('：', ':').replaceAll(' ', '');
  if (normalizedText.isEmpty) {
    return null;
  }
  if (normalizedText.contains('T') && DateTime.tryParse(normalizedText) != null) {
    return null;
  }

  final explicitDate = _extractExplicitDate(normalizedText, anchor);
  final dayOffset =
      explicitDate == null ? extractRelativeDayOffset(normalizedText) ?? fallbackDayOffset : null;
  final clockTime = _extractNaturalLanguageClockTime(normalizedText);
  if (clockTime == null) {
    return null;
  }

  final baseDate = explicitDate ??
      DateTime(
        anchor.year,
        anchor.month,
        anchor.day + (dayOffset ?? 0),
      );
  final normalizedDateTime = DateTime(
    baseDate.year,
    baseDate.month,
    baseDate.day,
    clockTime.hour,
    clockTime.minute,
    clockTime.second,
  );
  return _formatLocalIsoDateTime(normalizedDateTime);
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

DateTime? _extractExplicitDate(String text, DateTime anchor) {
  final isoMatch = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (isoMatch != null) {
    return DateTime(
      int.parse(isoMatch.group(1)!),
      int.parse(isoMatch.group(2)!),
      int.parse(isoMatch.group(3)!),
    );
  }

  final zhMatch =
      RegExp(r'(?:(\d{4})年)?(\d{1,2})月(\d{1,2})[日号]?').firstMatch(text);
  if (zhMatch == null) {
    return null;
  }

  return DateTime(
    zhMatch.group(1) == null ? anchor.year : int.parse(zhMatch.group(1)!),
    int.parse(zhMatch.group(2)!),
    int.parse(zhMatch.group(3)!),
  );
}

_ParsedClockTime? _extractNaturalLanguageClockTime(String text) {
  final match = RegExp(
    r'(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|今晚)?'
    r'(\d{1,2}|[零〇一二两三四五六七八九十]{1,3})'
    r'(?:(?::|点)'
    r'(\d{1,2}|[零〇一二两三四五六七八九十]{1,3}|半)?)?'
    r'(分)?',
  ).firstMatch(text);
  if (match == null) {
    return null;
  }

  final meridiem = match.group(1);
  final rawHour = match.group(2);
  final rawMinute = match.group(3);
  final hour = _parseClockNumber(rawHour);
  if (hour == null) {
    return null;
  }

  var minute = 0;
  if (rawMinute == '半') {
    minute = 30;
  } else if (rawMinute != null && rawMinute.isNotEmpty) {
    final parsedMinute = _parseClockNumber(rawMinute);
    if (parsedMinute == null) {
      return null;
    }
    minute = parsedMinute;
  }

  final normalizedHour = _normalizeHourByMeridiem(hour, meridiem);
  if (normalizedHour < 0 || normalizedHour > 23 || minute < 0 || minute > 59) {
    return null;
  }

  return _ParsedClockTime(
    hour: normalizedHour,
    minute: minute,
    second: 0,
  );
}

int? _parseClockNumber(String? rawValue) {
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }
  final digits = int.tryParse(rawValue);
  if (digits != null) {
    return digits;
  }

  const numerals = <String, int>{
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (rawValue == '十') {
    return 10;
  }
  if (!rawValue.contains('十')) {
    return numerals[rawValue];
  }

  final parts = rawValue.split('十');
  final tens = parts.first.isEmpty ? 1 : numerals[parts.first];
  final ones = parts.length < 2 || parts.last.isEmpty ? 0 : numerals[parts.last];
  if (tens == null || ones == null) {
    return null;
  }
  return tens * 10 + ones;
}

int _normalizeHourByMeridiem(int hour, String? meridiem) {
  switch (meridiem) {
    case '凌晨':
      return hour == 12 ? 0 : hour;
    case '中午':
      return hour >= 11 ? hour : hour + 12;
    case '下午':
    case '傍晚':
    case '晚上':
    case '今晚':
      return hour >= 12 ? hour : hour + 12;
    default:
      return hour;
  }
}

String _formatLocalIsoDateTime(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}T'
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}
