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
  static const cardElevations = <double>[0, 1, 4];
  static const cardElevationNames = <String>['无阴影', '轻微', '明显'];
  static const buttonRadii = <double>[8, 16, 28];
  static const buttonStyleNames = <String>['方正', '圆角', '胶囊'];
  static const inputRadii = <double>[8, 14, 24];
  static const inputStyleNames = <String>['方正', '圆角', '圆润'];
  static const dialogRadii = <double>[12, 20, 32];
  static const dialogStyleNames = <String>['方正', '圆角', '柔和'];
  static const backgroundColors = <Color>[
    Color(0xFFF5F7FB),
    Color(0xFFFFF8F0),
    Color(0xFFF1F8F4),
    Color(0xFFF7F2FA),
    Color(0xFFFFF3F5),
  ];
  static const backgroundNames = <String>['雾白', '奶油', '薄荷', '薰衣草', '浅樱'];

  static const fontRecommended = <Color>[
    Color(0xFF212121),
    Color(0xFF5F6368),
    Color(0xFF1A3A6B),
    Color(0xFF5D4037),
    Color(0xFF2E5540),
  ];
  static const fontRecommendedNames = <String>['墨黑', '暖灰', '藏蓝', '咖啡', '松绿'];

  static const stylePresetNames = <String, String>{
    'minimal': '简约',
    'standard': '标准',
    'soft': '柔和',
  };

  /// 套餐 → [卡片圆角, 卡片阴影, 按键, 输入框, 弹窗] 各档位索引。
  static const stylePresetValues = <String, List<int>>{
    'minimal': [0, 0, 0, 0, 0],
    'standard': [1, 0, 1, 1, 1],
    'soft': [2, 1, 2, 2, 2],
  };

  Future<void>? _loadFuture;
  ThemeMode _themeMode = ThemeMode.light;
  int _colorIndex = 0;
  int _fontScaleIndex = 1;
  int _cardStyleIndex = 1;
  int _cardElevationIndex = 0;
  int _buttonStyleIndex = 1;
  int _inputStyleIndex = 1;
  int _dialogStyleIndex = 1;
  int _backgroundIndex = 0;
  Color? _customBackgroundColor;
  Color? _customThemeColor;
  Color? _fontColor;
  String _stylePreset = '';
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

  /// 主题种子色：自定义优先，其次预设索引。ColorScheme.fromSeed 需要实色，
  /// 因此此处强制去掉透明度。
  Color get seedColor =>
      (_customThemeColor ?? colors[_colorIndex]).withValues(alpha: 1);
  Color? get customThemeColor => _customThemeColor;
  bool get isCustomTheme => _customThemeColor != null;

  /// 字体颜色：null 表示跟随主题默认。
  Color? get fontColor => _fontColor;
  int get fontScaleIndex => _fontScaleIndex;
  double get fontScale => fontScales[_fontScaleIndex];
  int get cardStyleIndex => _cardStyleIndex;
  double get cardRadius => cardRadii[_cardStyleIndex];
  int get cardElevationIndex => _cardElevationIndex;
  double get cardElevation => cardElevations[_cardElevationIndex];
  int get buttonStyleIndex => _buttonStyleIndex;
  double get buttonRadius => buttonRadii[_buttonStyleIndex];
  int get inputStyleIndex => _inputStyleIndex;
  double get inputRadius => inputRadii[_inputStyleIndex];
  int get dialogStyleIndex => _dialogStyleIndex;
  double get dialogRadius => dialogRadii[_dialogStyleIndex];
  int get backgroundIndex => _backgroundIndex;

  /// 背景色：自定义优先，其次预设索引。
  Color get backgroundColor =>
      _customBackgroundColor ?? backgroundColors[_backgroundIndex];
  Color? get customBackgroundColor => _customBackgroundColor;
  bool get isCustomBackground => _customBackgroundColor != null;

  /// 当前样式套餐：'' 表示自定义搭配。
  String get stylePreset => _stylePreset;
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
        "'card_elevation', 'button_style', 'input_style', 'dialog_style', "
        "'style_preset', 'background_color', 'notifications_enabled', "
        "'wish_goal_id', 'food_points_per_yuan', 'daily_summary_hour', "
        "'anniversary_reminder_hour', 'default_remind_minutes', "
        "'font_color')",
      );
      final values = {for (final row in rows) row['key']: row['value']};
      final mode = values['theme_mode'];
      _themeMode = switch (mode) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
      // 主题色：'c<argb>' 为自定义色，纯数字为预设索引（兼容旧数据）。
      final customTheme = parseCustomColorValue(values['theme_color']);
      if (customTheme != null) {
        _customThemeColor = customTheme;
      } else {
        _customThemeColor = null;
        final parsedColor = int.tryParse('${values['theme_color']}');
        if (parsedColor != null &&
            parsedColor >= 0 &&
            parsedColor < colors.length) {
          _colorIndex = parsedColor;
        }
      }
      _fontColor = parseCustomColorValue(values['font_color']);
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
      _cardElevationIndex = _storedIndex(
        values['card_elevation'],
        cardElevations.length,
      );
      _buttonStyleIndex = _storedIndex(
        values['button_style'],
        buttonRadii.length,
        fallback: 1,
      );
      _inputStyleIndex = _storedIndex(
        values['input_style'],
        inputRadii.length,
        fallback: 1,
      );
      _dialogStyleIndex = _storedIndex(
        values['dialog_style'],
        dialogRadii.length,
        fallback: 1,
      );
      final preset = '${values['style_preset']}';
      _stylePreset = stylePresetValues.containsKey(preset) ? preset : '';
      // 背景色：'c<argb>' 为自定义色，纯数字为预设索引（兼容旧数据）。
      final background = parseBackgroundValue(values['background_color']);
      _backgroundIndex = background.index;
      _customBackgroundColor = background.custom;
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
    _customThemeColor = null;
    notifyListeners();
  }

  /// 自定义主题色：存 `'c<argb>'` 格式，与预设索引值区分。
  Future<void> setThemeCustomColor(Color color) async {
    await _save('theme_color', 'c${color.toARGB32()}');
    _customThemeColor = color;
    notifyListeners();
  }

  /// 字体颜色：null 表示恢复默认（跟随主题）。
  Future<void> setFontColor(Color? color) async {
    await _save('font_color', color == null ? '' : 'c${color.toARGB32()}');
    _fontColor = color;
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
    await _saveMany({'card_style': '$value', 'style_preset': ''});
    _cardStyleIndex = value;
    _stylePreset = '';
    notifyListeners();
  }

  Future<void> setCardElevationIndex(int value) async {
    _validateIndex(value, cardElevations.length, '卡片阴影');
    await _saveMany({'card_elevation': '$value', 'style_preset': ''});
    _cardElevationIndex = value;
    _stylePreset = '';
    notifyListeners();
  }

  Future<void> setButtonStyleIndex(int value) async {
    _validateIndex(value, buttonRadii.length, '按键样式');
    await _saveMany({'button_style': '$value', 'style_preset': ''});
    _buttonStyleIndex = value;
    _stylePreset = '';
    notifyListeners();
  }

  Future<void> setInputStyleIndex(int value) async {
    _validateIndex(value, inputRadii.length, '输入框样式');
    await _saveMany({'input_style': '$value', 'style_preset': ''});
    _inputStyleIndex = value;
    _stylePreset = '';
    notifyListeners();
  }

  Future<void> setDialogStyleIndex(int value) async {
    _validateIndex(value, dialogRadii.length, '弹窗样式');
    await _saveMany({'dialog_style': '$value', 'style_preset': ''});
    _dialogStyleIndex = value;
    _stylePreset = '';
    notifyListeners();
  }

  /// 一键应用整套组件样式套餐。
  Future<void> applyStylePreset(String preset) async {
    final values = stylePresetValues[preset];
    if (values == null) {
      throw ArgumentError.value(preset, 'preset', '未知样式套餐');
    }
    await _saveMany({
      'card_style': '${values[0]}',
      'card_elevation': '${values[1]}',
      'button_style': '${values[2]}',
      'input_style': '${values[3]}',
      'dialog_style': '${values[4]}',
      'style_preset': preset,
    });
    _cardStyleIndex = values[0];
    _cardElevationIndex = values[1];
    _buttonStyleIndex = values[2];
    _inputStyleIndex = values[3];
    _dialogStyleIndex = values[4];
    _stylePreset = preset;
    notifyListeners();
  }

  Future<void> setBackgroundIndex(int value) async {
    _validateIndex(value, backgroundColors.length, '背景颜色');
    await _save('background_color', '$value');
    _backgroundIndex = value;
    _customBackgroundColor = null;
    notifyListeners();
  }

  /// 自定义背景色：存 `'c<argb>'` 格式，与预设索引值区分。
  Future<void> setBackgroundCustomColor(Color color) async {
    await _save('background_color', 'c${color.toARGB32()}');
    _customBackgroundColor = color;
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

  /// 解析 `'c<argb>'` 格式的自定义颜色值；其他格式返回 null。纯函数，便于测试。
  static Color? parseCustomColorValue(Object? value) {
    final text = '$value';
    if (!text.startsWith('c')) return null;
    final argb = int.tryParse(text.substring(1));
    return argb != null ? Color(argb) : null;
  }

  /// 解析背景色存储值：`'c<argb>'` → 自定义色；数字 → 预设索引；
  /// 无效值回退到默认预设。纯函数，便于测试。
  static ({int index, Color? custom}) parseBackgroundValue(Object? value) {
    final custom = parseCustomColorValue(value);
    if (custom != null) return (index: 0, custom: custom);
    final index = int.tryParse('$value');
    return (
      index: index != null && index >= 0 && index < backgroundColors.length
          ? index
          : 0,
      custom: null,
    );
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
