import 'package:app/constants/app_constants.dart';
import 'package:app/constants/style/app_style.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/utils/date_range.dart';
import 'package:app/utils/task_component.dart';
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

  test('style presets are consistent and within valid ranges', () {
    // 名称表与值表键集合一致。
    expect(
      AppSettingsController.stylePresetNames.keys.toSet(),
      AppSettingsController.stylePresetValues.keys.toSet(),
    );
    for (final entry in AppSettingsController.stylePresetValues.entries) {
      final values = entry.value;
      // 每套套餐覆盖 卡片圆角/卡片阴影/按键/输入框/弹窗 五个维度。
      expect(values.length, 5);
      expect(values[0], inInclusiveRange(0, AppSettingsController.cardRadii.length - 1));
      expect(values[1], inInclusiveRange(0, AppSettingsController.cardElevations.length - 1));
      expect(values[2], inInclusiveRange(0, AppSettingsController.buttonRadii.length - 1));
      expect(values[3], inInclusiveRange(0, AppSettingsController.inputRadii.length - 1));
      expect(values[4], inInclusiveRange(0, AppSettingsController.dialogRadii.length - 1));
    }
    // 标准套餐即历史默认搭配。
    expect(AppSettingsController.stylePresetValues['standard'], [1, 0, 1, 1, 1]);
  });

  test('background value parser supports preset index and custom color', () {
    // 旧版索引值兼容。
    final preset = AppSettingsController.parseBackgroundValue('2');
    expect(preset.index, 2);
    expect(preset.custom, isNull);

    // 自定义色：'c<argb>' 格式。
    const color = Color(0xFFFFF3E0);
    final custom = AppSettingsController.parseBackgroundValue(
      'c${color.toARGB32()}',
    );
    expect(custom.custom?.toARGB32(), color.toARGB32());

    // 无效值回退默认预设。
    final invalid = AppSettingsController.parseBackgroundValue('abc');
    expect(invalid.index, 0);
    expect(invalid.custom, isNull);
    final outOfRange = AppSettingsController.parseBackgroundValue('99');
    expect(outOfRange.index, 0);
  });

  test('custom color parser round-trips argb values and rejects others', () {
    // 'c<argb>' 往返解析。
    const color = Color(0xFFE05D78);
    final parsed = AppSettingsController.parseCustomColorValue(
      'c${color.toARGB32()}',
    );
    expect(parsed?.toARGB32(), color.toARGB32());

    // 带透明度的颜色同样往返。
    const translucent = Color(0x802E5540);
    final parsedAlpha = AppSettingsController.parseCustomColorValue(
      'c${translucent.toARGB32()}',
    );
    expect(parsedAlpha?.toARGB32(), translucent.toARGB32());

    // 索引值、空串、非法文本均返回 null。
    expect(AppSettingsController.parseCustomColorValue('3'), isNull);
    expect(AppSettingsController.parseCustomColorValue(''), isNull);
    expect(AppSettingsController.parseCustomColorValue('null'), isNull);
    expect(AppSettingsController.parseCustomColorValue('cabc'), isNull);
  });

  test('font recommended colors have matching names', () {
    expect(
      AppSettingsController.fontRecommendedNames.length,
      AppSettingsController.fontRecommended.length,
    );
  });

  test('font color and translucent background produce valid themes', () {
    final light = AppTheme.lightThemeFor(
      AppThemeColors.defaultSeed,
      fontColor: const Color(0xFF1A3A6B),
      backgroundColor: const Color(0x80FFF3E0),
    );
    expect(light.textTheme.bodyMedium?.color, const Color(0xFF1A3A6B));
    // 半透明背景合成实色后 alpha 必为 1。
    expect(light.scaffoldBackgroundColor.a, 1.0);

    final dark = AppTheme.darkThemeFor(
      AppThemeColors.defaultSeed,
      fontColor: const Color(0x802E5540),
    );
    expect(dark.textTheme.bodyMedium?.color, const Color(0x802E5540));
    expect(dark.scaffoldBackgroundColor.a, 1.0);
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

  group('task penalty idempotency keys', () {
    test('biz key embeds kind, task id and period key', () {
      expect(
        PointsService.penaltyBizKey('habit', 42, '2025-07-01'),
        'penalty:habit:42:2025-07-01',
      );
      expect(
        PointsService.penaltyBizKey('special', 7, '2025-06-30'),
        'penalty:special:7:2025-06-30',
      );
    });

    test('same task and period always produce the same key', () {
      String key() => PointsService.penaltyBizKey('daily', 9, '2025-07-01');
      expect(key(), key());
    });

    test('different periods or tasks produce different keys', () {
      final keys = {
        PointsService.penaltyBizKey('daily', 9, '2025-07-01'),
        PointsService.penaltyBizKey('daily', 9, '2025-07-02'),
        PointsService.penaltyBizKey('daily', 10, '2025-07-01'),
        PointsService.penaltyBizKey('long', 9, '2025-07-01'),
      };
      expect(keys.length, 4);
    });

    test('source types cover the four penalizable task kinds', () {
      expect(PointsService.penaltySourceType('special'),
          'special_task_penalty');
      expect(PointsService.penaltySourceType('long'), 'long_task_penalty');
      expect(PointsService.penaltySourceType('daily'), 'daily_task_penalty');
      expect(PointsService.penaltySourceType('habit'), 'daily_task_penalty');
    });

    test('wish and hope never support overdue penalty', () {
      expect(TaskType.wish.supportsOverduePenalty, isFalse);
      expect(TaskType.hope.supportsOverduePenalty, isFalse);
      for (final type in [
        TaskType.daily,
        TaskType.longTerm,
        TaskType.shortTerm,
        TaskType.habit,
      ]) {
        expect(type.supportsOverduePenalty, isTrue);
      }
    });
  });

  group('TaskComponentDocument', () {
    test('encodes and decodes ordered components with data', () {
      final doc = TaskComponentDocument([
        const TaskComponent(
          type: ComponentType.deadline,
          data: {ComponentDataKeys.end: '2025-08-01T23:59:00.000'},
        ),
        const TaskComponent(
          type: ComponentType.rewardPoints,
          data: {ComponentDataKeys.points: 20},
        ),
      ]);
      final restored = TaskComponentDocument.decode(doc.encode());
      expect(restored.components.length, 2);
      expect(restored.components[0].type, ComponentType.deadline);
      expect(restored.components[1].type, ComponentType.rewardPoints);
      expect(
        restored.dataOf(ComponentType.rewardPoints)[ComponentDataKeys.points],
        20,
      );
    });

    test('corrupted or partial json degrades to an empty document', () {
      expect(TaskComponentDocument.decode(null).components, isEmpty);
      expect(TaskComponentDocument.decode('').components, isEmpty);
      expect(TaskComponentDocument.decode('not-json').components, isEmpty);
      expect(
        TaskComponentDocument.decode(
          '[{"type":"unknown_type","data":{}},{"type":"tag","data":{}}]',
        ).components.single.type,
        ComponentType.tag,
      );
    });

    test('upsert, update, remove and reorder mutate in place', () {
      final doc = TaskComponentDocument.defaultFor(TaskType.daily);
      doc.upsert(ComponentType.dataChart);
      expect(doc.has(ComponentType.dataChart), isTrue);
      doc.updateData(ComponentType.dataChart, {ComponentDataKeys.value: 70});
      expect(doc.dataOf(ComponentType.dataChart)[ComponentDataKeys.value], 70);
      final originalOrder = doc.components.map((c) => c.type).toList();
      // 数据分析默认不在首位；移到最前后其余顺序平移。
      final chartIndex = doc.indexOf(ComponentType.dataChart);
      expect(chartIndex, greaterThan(0));
      doc.reorder(chartIndex, 0);
      expect(doc.components.first.type, ComponentType.dataChart);
      expect(doc.components[1].type, originalOrder.first);
      expect(doc.components.length, originalOrder.length);
      doc.remove(ComponentType.dataChart);
      expect(doc.has(ComponentType.dataChart), isFalse);
    });

    test('each task type gets its default component set', () {
      expect(
        TaskComponentDocument.defaultFor(
          TaskType.shortTerm,
        ).components.map((c) => c.type),
        contains(ComponentType.reminders),
      );
      expect(
        TaskComponentDocument.defaultFor(
          TaskType.habit,
        ).components.map((c) => c.type),
        contains(ComponentType.repeatRule),
      );
      expect(
        TaskComponentDocument.defaultFor(
          TaskType.longTerm,
        ).components.map((c) => c.type),
        contains(ComponentType.deadline),
      );
    });

    test('file and subtask helpers return growable lists', () {
      final files = TaskComponentDocument.fileItems(const {});
      expect(() => files.add({'name': 'a', 'path': 'b'}), returnsNormally);
      final items = TaskComponentDocument.subtaskItems(const {});
      expect(
        () => items.add({'text': 'a', 'done': false}),
        returnsNormally,
      );
    });

    test('intValue tolerates int, num and string representations', () {
      expect(
        TaskComponentDocument.intValue(const {'v': 3}, 'v', 1),
        3,
      );
      expect(
        TaskComponentDocument.intValue(const {'v': '12'}, 'v', 1),
        12,
      );
      expect(
        TaskComponentDocument.intValue(const {'v': 4.0}, 'v', 1),
        4,
      );
      expect(TaskComponentDocument.intValue(const {}, 'v', 7), 7);
    });
  });

  group('MoodLevel', () {
    test('maps valid scores and clamps invalid ones to neutral', () {
      expect(MoodLevel.fromScore(1), MoodLevel.veryLow);
      expect(MoodLevel.fromScore(5), MoodLevel.veryGood);
      expect(MoodLevel.fromScore(null), MoodLevel.neutral);
      expect(MoodLevel.fromScore(99), MoodLevel.neutral);
    });
  });

  group('MoodCategory', () {
    test('defaults mirror the five MoodLevel entries', () {
      final defaults = MoodCategory.defaults;
      expect(defaults.length, MoodLevel.values.length);
      for (var i = 0; i < defaults.length; i++) {
        expect(defaults[i].label, MoodLevel.values[i].label);
        expect(defaults[i].score, MoodLevel.values[i].score);
      }
    });

    test('parse falls back to defaults on missing or corrupted data', () {
      expect(MoodCategory.parse(const {}), hasLength(MoodLevel.values.length));
      expect(
        MoodCategory.parse(const {ComponentDataKeys.categories: 'broken'}),
        hasLength(MoodLevel.values.length),
      );
      expect(
        MoodCategory.parse(const {ComponentDataKeys.categories: []}),
        hasLength(MoodLevel.values.length),
      );
      // 全部条目非法（空标签 / 越界分值）时同样回退默认五项。
      expect(
        MoodCategory.parse(const {
          ComponentDataKeys.categories: [
            {'label': '', 'score': 3},
            {'label': '开心', 'score': 0},
            {'label': '开心', 'score': 6},
          ],
        }),
        hasLength(MoodLevel.values.length),
      );
    });

    test('parse keeps valid entries and skips invalid ones', () {
      final parsed = MoodCategory.parse(const {
        ComponentDataKeys.categories: [
          {'label': '平静', 'score': 3},
          {'label': '亢奋', 'score': '5'},
          {'label': '', 'score': 1},
        ],
      });
      expect(parsed, hasLength(2));
      expect(parsed.first.label, '平静');
      expect(parsed.last.score, 5);
    });

    test('labelFor prefers custom categories then falls back to MoodLevel', () {
      const categories = [MoodCategory(label: '多云', score: 2)];
      expect(MoodCategory.labelFor(2, categories), '多云');
      expect(MoodCategory.labelFor(4, categories), MoodLevel.fromScore(4).label);
      expect(MoodCategory.labelFor(3), MoodLevel.neutral.label);
    });
  });

  group('task editor defaults', () {
    test('legacy weight and mood components are dropped when decoding', () {
      // 体重 / 心情已独立为应用级功能：旧 component_json 中的残留项
      // 在解码时按未知类型容错跳过，不再进入任务组件列表。
      final doc = TaskComponentDocument.decode(
        '[{"type":"weight","data":{}},{"type":"mood","data":{}},'
        '{"type":"tag","data":{}}]',
      );
      expect(doc.components.single.type, ComponentType.tag);
    });

    test('data chart component survives a json round trip', () {
      final doc = TaskComponentDocument([
        const TaskComponent(
          type: ComponentType.dataChart,
          data: {
            ComponentDataKeys.chartType: 'bar',
            ComponentDataKeys.title: '支出趋势',
            ComponentDataKeys.unit: '元',
          },
        ),
      ]);
      final decoded = TaskComponentDocument.decode(doc.encode());
      expect(decoded.components, hasLength(1));
      final data = decoded.dataOf(ComponentType.dataChart);
      expect(data[ComponentDataKeys.chartType], 'bar');
      expect(data[ComponentDataKeys.title], '支出趋势');
      expect(data[ComponentDataKeys.unit], '元');
    });
  });
}
