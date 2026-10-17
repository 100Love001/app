import 'package:app/constants/style/app_style.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/utils/date_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('date picker range', () {
    test('clamps an initial date to the selectable range', () {
      expect(
        clampDateToRange(
          DateTime(2026, 9, 27, 18),
          DateTime(2026, 9, 30, 22),
          DateTime(2100),
        ),
        DateTime(2026, 9, 30),
      );
    });

    test('rejects an inverted selectable range', () {
      expect(
        () => clampDateToRange(DateTime(2026), DateTime(2027), DateTime(2026)),
        throwsArgumentError,
      );
    });

    test('returns the date when within range', () {
      final date = DateTime(2026, 10, 5);
      expect(
        clampDateToRange(date, DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
        date,
      );
    });

    test('clamps to start when before range', () {
      expect(
        clampDateToRange(
          DateTime(2026, 9, 15),
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 31),
        ),
        DateTime(2026, 10, 1),
      );
    });

    test('clamps to end when after range', () {
      expect(
        clampDateToRange(
          DateTime(2026, 11, 5),
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 31),
        ),
        DateTime(2026, 10, 31),
      );
    });

    test('handles same-day range', () {
      final rangeDate = DateTime(2026, 10, 15);
      expect(
        clampDateToRange(DateTime(2026, 10, 10), rangeDate, rangeDate),
        rangeDate,
      );
      expect(
        clampDateToRange(DateTime(2026, 10, 20), rangeDate, rangeDate),
        rangeDate,
      );
    });
  });

  group('daily task review schedule', () {
    test('advances through spaced review intervals', () {
      final date = DateTime(2026, 9, 27, 18, 30);
      final intervals = [1, 2, 4, 7, 15, 30];
      for (var stage = 0; stage < intervals.length; stage++) {
        expect(
          PointsService.nextDailyReviewDate(date, stage),
          DateTime(2026, 9, 27 + intervals[stage]),
        );
      }
    });

    test('handles month boundaries correctly', () {
      expect(
        PointsService.nextDailyReviewDate(DateTime(2026, 9, 30), 0),
        DateTime(2026, 10, 1),
      );
      expect(
        PointsService.nextDailyReviewDate(DateTime(2026, 12, 31), 0),
        DateTime(2027, 1, 1),
      );
      expect(
        PointsService.nextDailyReviewDate(DateTime(2026, 2, 28), 1),
        DateTime(2026, 3, 2),
      );
    });

    test('handles leap year correctly', () {
      expect(
        PointsService.nextDailyReviewDate(DateTime(2024, 2, 29), 0),
        DateTime(2024, 3, 1),
      );
    });

    test('rejects negative stage', () {
      expect(
        () => PointsService.nextDailyReviewDate(DateTime(2026, 9, 27), -1),
        throwsArgumentError,
      );
    });

    test('strips time component from input date', () {
      expect(
        PointsService.nextDailyReviewDate(DateTime(2026, 9, 27, 23, 59, 59), 0),
        DateTime(2026, 9, 28),
      );
    });

    group('automatic food balance conversion', () {
      test('converts the remaining balance at five points per yuan', () {
        expect(PointsService.foodPointsForBalance(12.39), 61);
        expect(PointsService.foodPointsForBalance(0.19), 0);
      });

      test('handles zero balance', () {
        expect(PointsService.foodPointsForBalance(0), 0);
        expect(PointsService.foodPointsForBalance(0.0), 0);
      });

      test('floors fractional points correctly', () {
        expect(PointsService.foodPointsForBalance(1.0), 5);
        expect(PointsService.foodPointsForBalance(1.19), 5);
        expect(PointsService.foodPointsForBalance(1.20), 6);
        expect(PointsService.foodPointsForBalance(0.99), 4);
      });

      test('handles large values', () {
        expect(PointsService.foodPointsForBalance(1000.0), 5000);
        expect(PointsService.foodPointsForBalance(999999.99), 4999999);
      });

      test('rejects invalid balances', () {
        expect(
          () => PointsService.foodPointsForBalance(-1),
          throwsArgumentError,
        );
        expect(
          () => PointsService.foodPointsForBalance(-0.01),
          throwsArgumentError,
        );
        expect(
          () => PointsService.foodPointsForBalance(double.infinity),
          throwsArgumentError,
        );
        expect(
          () => PointsService.foodPointsForBalance(double.nan),
          throwsArgumentError,
        );
        expect(
          () => PointsService.foodPointsForBalance(double.negativeInfinity),
          throwsArgumentError,
        );
      });
    });

    test('continues using the longest interval after the final stage', () {
      expect(
        PointsService.nextDailyReviewDate(DateTime(2026, 9, 27), 20),
        DateTime(2026, 10, 27),
      );
    });
  });

  group('anniversary dates', () {
    test('returns today when the annual date is today', () {
      expect(
        nextAnniversaryDate(DateTime(2000, 9, 27), DateTime(2026, 9, 27, 20)),
        DateTime(2026, 9, 27),
      );
    });

    test('moves an elapsed annual date to next year', () {
      expect(
        nextAnniversaryDate(DateTime(2000, 3, 10), DateTime(2026, 9, 27)),
        DateTime(2027, 3, 10),
      );
    });

    test('handles future annual date in same year', () {
      expect(
        nextAnniversaryDate(DateTime(2000, 12, 25), DateTime(2026, 9, 27)),
        DateTime(2026, 12, 25),
      );
    });

    test('handles leap year anniversary', () {
      expect(
        nextAnniversaryDate(DateTime(2000, 2, 29), DateTime(2024, 3, 1)),
        DateTime(2025, 2, 28),
      );
    });

    test('preserves original date components', () {
      final original = DateTime(1990, 6, 15, 14, 30, 45);
      final result = nextAnniversaryDate(original, DateTime(2026, 9, 27));
      expect(result.year, 2027);
      expect(result.month, 6);
      expect(result.day, 15);
      expect(result.hour, 0);
      expect(result.minute, 0);
    });
  });

  test('appearance palette has a matching name for every color', () {
    expect(AppSettingsController.colors.length, greaterThanOrEqualTo(8));
    expect(
      AppSettingsController.colorNames.length,
      AppSettingsController.colors.length,
    );
  });

  test('all supported text scales create valid light and dark themes', () {
    for (final scale in AppSettingsController.fontScales) {
      final light = AppTheme.lightThemeFor(
        AppThemeColors.defaultSeed,
        fontScale: scale,
      );
      final dark = AppTheme.darkThemeFor(
        AppThemeColors.defaultSeed,
        fontScale: scale,
      );
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
    }
  });

  group('PointsService constants', () {
    test('food points per yuan is positive', () {
      expect(PointsService.foodPointsPerYuan, greaterThan(0));
      expect(PointsService.foodPointsPerYuan, 5);
    });
  });
}
