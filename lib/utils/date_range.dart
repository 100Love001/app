import 'package:lunar/lunar.dart';

DateTime clampDateToRange(
  DateTime date,
  DateTime firstDate,
  DateTime lastDate,
) {
  DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);

  final minimum = day(firstDate);
  final maximum = day(lastDate);
  if (minimum.isAfter(maximum)) {
    throw ArgumentError('最早日期不能晚于最晚日期');
  }
  final candidate = day(date);
  if (candidate.isBefore(minimum)) return minimum;
  if (candidate.isAfter(maximum)) return maximum;
  return candidate;
}

DateTime nextAnniversaryDate(DateTime eventDate, DateTime today) {
  final startOfToday = DateTime(today.year, today.month, today.day);
  final year = today.year;
  final month = eventDate.month;
  final day = _clampDay(month, eventDate.day, year);
  var nextDate = DateTime(year, month, day);
  if (nextDate.isBefore(startOfToday)) {
    final nextYear = year + 1;
    final clampedDay = _clampDay(month, eventDate.day, nextYear);
    nextDate = DateTime(nextYear, month, clampedDay);
  }
  return nextDate;
}

DateTime computeNextAnniversaryDate({
  required DateTime eventDate,
  required DateTime today,
  required int calendarType,
  required int repeatType,
  int repeatCustomDays = 0,
}) {
  final startOfToday = DateTime(today.year, today.month, today.day);

  if (repeatType == 0) {
    return DateTime(eventDate.year, eventDate.month, eventDate.day);
  }

  if (repeatType == 4) {
    if (repeatCustomDays <= 0) {
      return DateTime(eventDate.year, eventDate.month, eventDate.day);
    }
    var candidate = DateTime(
      eventDate.year,
      eventDate.month,
      eventDate.day,
    );
    while (!candidate.isAfter(startOfToday)) {
      candidate = candidate.add(Duration(days: repeatCustomDays));
    }
    return candidate;
  }

  if (calendarType == 1) {
    return _computeNextLunarAnniversary(
      eventDate: eventDate,
      startOfToday: startOfToday,
      repeatType: repeatType,
    );
  }

  return _computeNextSolarAnniversary(
    eventDate: eventDate,
    startOfToday: startOfToday,
    repeatType: repeatType,
  );
}

DateTime _computeNextSolarAnniversary({
  required DateTime eventDate,
  required DateTime startOfToday,
  required int repeatType,
}) {
  final year = startOfToday.year;
  final month = eventDate.month;
  final day = _clampDay(month, eventDate.day, year);
  var nextDate = DateTime(year, month, day);

  if (nextDate.isBefore(startOfToday)) {
    if (repeatType == 1) {
      final nextYear = year + 1;
      final clampedDay = _clampDay(month, eventDate.day, nextYear);
      nextDate = DateTime(nextYear, month, clampedDay);
    } else if (repeatType == 2) {
      var candidateMonth = month;
      var candidateYear = year;
      do {
        candidateMonth++;
        if (candidateMonth > 12) {
          candidateMonth = 1;
          candidateYear++;
        }
        final clampedDay = _clampDay(
          candidateMonth,
          eventDate.day,
          candidateYear,
        );
        nextDate = DateTime(candidateYear, candidateMonth, clampedDay);
      } while (nextDate.isBefore(startOfToday));
    } else if (repeatType == 3) {
      var candidate = DateTime(year, month, day);
      while (candidate.isBefore(startOfToday)) {
        candidate = candidate.add(const Duration(days: 7));
      }
      nextDate = candidate;
    }
  }

  return nextDate;
}

DateTime _computeNextLunarAnniversary({
  required DateTime eventDate,
  required DateTime startOfToday,
  required int repeatType,
}) {
  final solar = Solar.fromYmd(
    eventDate.year,
    eventDate.month,
    eventDate.day,
  );
  final lunar = solar.getLunar();
  final lunarYear = lunar.getYear();
  final lunarMonth = lunar.getMonth();
  final lunarDay = lunar.getDay();

  if (repeatType == 1) {
    var targetYear = startOfToday.year;
    var lunarDate = _safeLunar(targetYear, lunarMonth, lunarDay);
    var solarDate = lunarDate.getSolar();
    var nextDate = DateTime(
      solarDate.getYear(),
      solarDate.getMonth(),
      solarDate.getDay(),
    );

    if (nextDate.isBefore(startOfToday)) {
      targetYear++;
      lunarDate = _safeLunar(targetYear, lunarMonth, lunarDay);
      solarDate = lunarDate.getSolar();
      nextDate = DateTime(
        solarDate.getYear(),
        solarDate.getMonth(),
        solarDate.getDay(),
      );
    }
    return nextDate;
  }

  if (repeatType == 2) {
    var targetYear = lunarYear;
    var targetMonth = lunarMonth;
    var lunarDate = _safeLunar(targetYear, targetMonth, lunarDay);
    var solarDate = lunarDate.getSolar();
    var nextDate = DateTime(
      solarDate.getYear(),
      solarDate.getMonth(),
      solarDate.getDay(),
    );

    while (nextDate.isBefore(startOfToday)) {
      targetMonth++;
      if (targetMonth > 12) {
        targetMonth = 1;
        targetYear++;
      }
      lunarDate = _safeLunar(targetYear, targetMonth, lunarDay);
      solarDate = lunarDate.getSolar();
      nextDate = DateTime(
        solarDate.getYear(),
        solarDate.getMonth(),
        solarDate.getDay(),
      );
    }
    return nextDate;
  }

  if (repeatType == 3) {
    var lunarDate = _safeLunar(lunarYear, lunarMonth, lunarDay);
    var solarDate = lunarDate.getSolar();
    var candidate = DateTime(
      solarDate.getYear(),
      solarDate.getMonth(),
      solarDate.getDay(),
    );
    while (candidate.isBefore(startOfToday)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  return DateTime(eventDate.year, eventDate.month, eventDate.day);
}

Lunar _safeLunar(int year, int month, int day) {
  try {
    return Lunar.fromYmd(year, month, day);
  } catch (_) {
    return Lunar.fromYmd(year, month, day - 1);
  }
}

int _clampDay(int month, int day, int year) {
  const daysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var maxDay = daysInMonth[month];
  if (month == 2 && _isLeapYear(year)) maxDay = 29;
  return day > maxDay ? maxDay : day;
}

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
