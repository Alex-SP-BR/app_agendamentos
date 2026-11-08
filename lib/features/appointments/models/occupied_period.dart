class OccupiedPeriod {
  const OccupiedPeriod({required this.startsAt, required this.endsAt});

  final DateTime startsAt;
  final DateTime endsAt;
}

const _fallbackOccupiedDurationMinutes = 30;

int parseOccupiedDurationMinutes(Object? value) {
  if (value is Duration) {
    final microseconds = value.inMicroseconds;
    if (microseconds > 0) {
      final wholeMinutes = microseconds ~/ Duration.microsecondsPerMinute;
      final hasRemainder =
          microseconds.remainder(Duration.microsecondsPerMinute) != 0;
      return wholeMinutes + (hasRemainder ? 1 : 0);
    }
    return _fallbackOccupiedDurationMinutes;
  }

  if (value is num) {
    return _positiveWholeMinutes(value) ?? _fallbackOccupiedDurationMinutes;
  }

  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return _fallbackOccupiedDurationMinutes;

  final numericValue = num.tryParse(text);
  if (numericValue != null) {
    return _positiveWholeMinutes(numericValue) ??
        _fallbackOccupiedDurationMinutes;
  }

  final timeValue = RegExp(r'^(\d+):([0-5]\d)(?::([0-5]\d(?:\.\d+)?))?$')
      .firstMatch(text);
  if (timeValue != null) {
    final hours = int.tryParse(timeValue.group(1)!);
    final minutes = int.tryParse(timeValue.group(2)!);
    final seconds = num.tryParse(timeValue.group(3) ?? '0');
    if (hours != null && minutes != null && seconds != null) {
      final totalSeconds = hours * 3600 + minutes * 60 + seconds;
      if (totalSeconds > 0 && totalSeconds.isFinite) {
        return (totalSeconds / 60).ceil();
      }
    }
  }

  final minuteValue = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(?:min|mins|minute|minutes)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (minuteValue != null) {
    final minutes = num.tryParse(minuteValue.group(1)!);
    if (minutes != null) {
      return _positiveWholeMinutes(minutes) ?? _fallbackOccupiedDurationMinutes;
    }
  }

  return _fallbackOccupiedDurationMinutes;
}

int? _positiveWholeMinutes(num value) {
  if (!value.isFinite || value <= 0 || value % 1 != 0) return null;
  return value.toInt();
}
