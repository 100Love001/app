import 'package:app/stores/database/add_database.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._();

  static final AppSettingsController instance = AppSettingsController._();

  static const colors = <Color>[
    Color(0xFF5267D8),
    Color(0xFF00897B),
    Color(0xFF8E5CC2),
    Color(0xFFE47742),
    Color(0xFFE05D78),
    Color(0xFF3F8FCE),
    Color(0xFF668B46),
    Color(0xFFD19A24),
    Color(0xFFB0523A),
    Color(0xFF56616F),
  ];

  static const colorNames = <String>[
    '晴空蓝',
    '薄荷绿',
    '薰衣草',
    '暖橘',
    '樱花粉',
    '海洋蓝',
    '森林绿',
    '琥珀金',
    '陶土红',
    '石墨灰',
  ];

  static const fontScales = <double>[0.9, 1, 1.1, 1.2];
  static const fontScaleNames = <String>['偏小', '标准', '偏大', '特大'];
  static const cardRadii = <double>[12, 20, 28];
  static const cardStyleNames = <String>['简洁', '圆润', '柔和'];
  static const buttonRadii = <double>[8, 16, 28];
  static const buttonStyleNames = <String>['方正', '圆角', '胶囊'];
  static const backgroundColors = <Color>[
    Color(0xFFF5F7FB),
    Color(0xFFFFF8F0),
    Color(0xFFF1F8F4),
    Color(0xFFF7F2FA),
    Color(0xFFFFF3F5),
  ];
  static const backgroundNames = <String>['雾白', '奶油', '薄荷', '薰衣草', '浅樱'];

  Future<void>? _loadFuture;
  ThemeMode _themeMode = ThemeMode.light;
  int _colorIndex = 0;
  int _fontScaleIndex = 1;
  int _cardStyleIndex = 1;
  int _buttonStyleIndex = 1;
  int _backgroundIndex = 0;
  String _displayName = '生活规划师';
  String _signature = '把每一天都过成喜欢的样子';
  String _personalMotto = '专注当下，慢慢成为想成为的人';
  bool _notificationsEnabled = false;
  int? _wishGoalId;
  int _foodPointsPerYuan = 5;
  int _dailySummaryHour = 21;
  int _anniversaryReminderHour = 9;
  int _defaultRemindMinutes = 15;
  Object? _loadError;

  ThemeMode get themeMode => _themeMode;
  int get colorIndex => _colorIndex;
  Color get seedColor => colors[_colorIndex];
  int get fontScaleIndex => _fontScaleIndex;
  double get fontScale => fontScales[_fontScaleIndex];
  int get cardStyleIndex => _cardStyleIndex;
  double get cardRadius => cardRadii[_cardStyleIndex];
  int get buttonStyleIndex => _buttonStyleIndex;
  double get buttonRadius => buttonRadii[_buttonStyleIndex];
  int get backgroundIndex => _backgroundIndex;
  Color get backgroundColor => backgroundColors[_backgroundIndex];
  String get displayName => _displayName;
  String get signature => _signature;
  String get personalMotto => _personalMotto;
  bool get notificationsEnabled => _notificationsEnabled;

  /// 当前设为“目标”的愿望 id；null 表示未设置。
  int? get wishGoalId => _wishGoalId;

  /// 饭钱结余兑换积分比例：每元结余 = N 积分（默认 5）。
  int get foodPointsPerYuan => _foodPointsPerYuan;

  /// 每日小结推送小时（0-23，默认 21）。
  int get dailySummaryHour => _dailySummaryHour;

  /// 纪念日提醒小时（0-23，默认 9）。
  int get anniversaryReminderHour => _anniversaryReminderHour;

  /// 特殊任务默认提前提醒分钟数（默认 15）。
  int get defaultRemindMinutes => _defaultRemindMinutes;
  Object? get loadError => _loadError;

  Future<void> load() => _loadFuture ??= _loadSettings();

  Future<void> reload() {
    _loadFuture = null;
    return load();
  }

  Future<void> _loadSettings() async {
    try {
      final rows = await AppDatabase.instance.rawQuery(
        'SELECT key, value FROM app_settings '
        "WHERE key IN ('theme_mode', 'theme_color', 'profile_name', "
        "'profile_signature', 'personal_motto', 'font_scale', 'card_style', "
        "'button_style', 'background_color', 'notifications_enabled', "
        "'wish_goal_id', 'food_points_per_yuan', 'daily_summary_hour', "
        "'anniversary_reminder_hour', 'default_remind_minutes')",
      );
      final values = {for (final row in rows) row['key']: row['value']};
      final mode = values['theme_mode'];
      _themeMode = switch (mode) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
      final parsedColor = int.tryParse('${values['theme_color']}');
      if (parsedColor != null &&
          parsedColor >= 0 &&
          parsedColor < colors.length) {
        _colorIndex = parsedColor;
      }
      _fontScaleIndex = _storedIndex(
        values['font_scale'],
        fontScales.length,
        fallback: 1,
      );
      _cardStyleIndex = _storedIndex(
        values['card_style'],
        cardRadii.length,
        fallback: 1,
      );
      _buttonStyleIndex = _storedIndex(
        values['button_style'],
        buttonRadii.length,
        fallback: 1,
      );
      _backgroundIndex = _storedIndex(
        values['background_color'],
        backgroundColors.length,
      );
      _displayName = _nonEmpty(values['profile_name'], _displayName);
      _signature = _nonEmpty(values['profile_signature'], _signature);
      _personalMotto = _nonEmpty(values['personal_motto'], _personalMotto);
      _notificationsEnabled = values['notifications_enabled'] == 'true';
      _wishGoalId = int.tryParse('${values['wish_goal_id']}');
      _foodPointsPerYuan = _storedIntInRange(
        values['food_points_per_yuan'],
        1,
        100,
        fallback: 5,
      );
      _dailySummaryHour = _storedIntInRange(
        values['daily_summary_hour'],
        0,
        23,
        fallback: 21,
      );
      _anniversaryReminderHour = _storedIntInRange(
        values['anniversary_reminder_hour'],
        0,
        23,
        fallback: 9,
      );
      _defaultRemindMinutes = _storedIntInRange(
        values['default_remind_minutes'],
        0,
        1440,
        fallback: 15,
      );
      _loadError = null;
    } catch (error) {
      _loadError = error;
      _loadFuture = null;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _save('theme_mode', switch (value) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
    });
    _themeMode = value;
    notifyListeners();
  }

  Future<void> setColorIndex(int value) async {
    if (value < 0 || value >= colors.length) {
      throw ArgumentError.value(value, 'value', '主题色索引无效');
    }
    await _save('theme_color', '$value');
    _colorIndex = value;
    notifyListeners();
  }

  Future<void> setFontScaleIndex(int value) async {
    _validateIndex(value, fontScales.length, '字体大小');
    await _save('font_scale', '$value');
    _fontScaleIndex = value;
    notifyListeners();
  }

  Future<void> setCardStyleIndex(int value) async {
    _validateIndex(value, cardRadii.length, '卡片样式');
    await _save('card_style', '$value');
    _cardStyleIndex = value;
    notifyListeners();
  }

  Future<void> setButtonStyleIndex(int value) async {
    _validateIndex(value, buttonRadii.length, '按键样式');
    await _save('button_style', '$value');
    _buttonStyleIndex = value;
    notifyListeners();
  }

  Future<void> setBackgroundIndex(int value) async {
    _validateIndex(value, backgroundColors.length, '背景颜色');
    await _save('background_color', '$value');
    _backgroundIndex = value;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String displayName,
    required String signature,
  }) async {
    final name = displayName.trim();
    final motto = signature.trim();
    if (name.isEmpty) throw ArgumentError('昵称不能为空');
    await _saveMany({'profile_name': name, 'profile_signature': motto});
    _displayName = name;
    _signature = motto;
    notifyListeners();
  }

  Future<void> setPersonalMotto(String value) async {
    final motto = value.trim();
    if (motto.isEmpty) throw ArgumentError('座右铭不能为空');
    await _save('personal_motto', motto);
    _personalMotto = motto;
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _save('notifications_enabled', value.toString());
    _notificationsEnabled = value;
    notifyListeners();
  }

  /// 设置/清除目标愿望 id（null = 清除）。常驻通知据此展示进度。
  Future<void> setWishGoalId(int? value) async {
    await _save('wish_goal_id', value == null ? '' : '$value');
    _wishGoalId = value;
    notifyListeners();
  }

  Future<void> setFoodPointsPerYuan(int value) async {
    if (value < 1 || value > 100) {
      throw ArgumentError.value(value, 'value', '兑换比例需在 1-100 之间');
    }
    await _save('food_points_per_yuan', '$value');
    _foodPointsPerYuan = value;
    notifyListeners();
  }

  Future<void> setDailySummaryHour(int value) async {
    if (value < 0 || value > 23) {
      throw ArgumentError.value(value, 'value', '推送时间需在 0-23 点之间');
    }
    await _save('daily_summary_hour', '$value');
    _dailySummaryHour = value;
    notifyListeners();
  }

  Future<void> setAnniversaryReminderHour(int value) async {
    if (value < 0 || value > 23) {
      throw ArgumentError.value(value, 'value', '提醒时间需在 0-23 点之间');
    }
    await _save('anniversary_reminder_hour', '$value');
    _anniversaryReminderHour = value;
    notifyListeners();
  }

  Future<void> setDefaultRemindMinutes(int value) async {
    if (value < 0 || value > 1440) {
      throw ArgumentError.value(value, 'value', '提前提醒需在 0-1440 分钟之间');
    }
    await _save('default_remind_minutes', '$value');
    _defaultRemindMinutes = value;
    notifyListeners();
  }

  int _storedIntInRange(Object? value, int min, int max, {required int fallback}) {
    final parsed = int.tryParse('$value');
    return parsed != null && parsed >= min && parsed <= max ? parsed : fallback;
  }

  Future<void> _save(String key, String value) => _saveMany({key: value});

  Future<void> _saveMany(Map<String, String> values) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      for (final entry in values.entries) {
        await transaction.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _loadError = null;
  }

  String _nonEmpty(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  int _storedIndex(Object? value, int length, {int fallback = 0}) {
    final index = int.tryParse('$value');
    return index != null && index >= 0 && index < length ? index : fallback;
  }

  void _validateIndex(int value, int length, String label) {
    if (value < 0 || value >= length) {
      throw ArgumentError.value(value, 'value', '$label索引无效');
    }
  }
}
