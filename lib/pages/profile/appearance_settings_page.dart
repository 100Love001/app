import 'dart:async';

import 'package:app/pages/profile/app_color_picker.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:flutter/material.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  final AppSettingsController _settings = AppSettingsController.instance;

  Future<void> _runSetting(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存设置失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观与样式')),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, child) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildThemeModeSection(context),
            const SizedBox(height: 12),
            _buildThemeColorSection(context),
            const SizedBox(height: 12),
            _buildBackgroundSection(context),
            const SizedBox(height: 12),
            _buildFontColorSection(context),
            const SizedBox(height: 12),
            _section(
              id: 'font-scale',
              title: '字体大小',
              summary:
                  AppSettingsController.fontScaleNames[_settings.fontScaleIndex],
              child: _chipWrap(
                names: AppSettingsController.fontScaleNames,
                selectedIndex: _settings.fontScaleIndex,
                onSelected: _settings.setFontScaleIndex,
              ),
            ),
            const SizedBox(height: 12),
            _buildCardStyleSection(context),
            const SizedBox(height: 12),
            _section(
              id: 'button-style',
              title: '按键样式',
              summary: AppSettingsController
                  .buttonStyleNames[_settings.buttonStyleIndex],
              child: _chipWrap(
                names: AppSettingsController.buttonStyleNames,
                selectedIndex: _settings.buttonStyleIndex,
                onSelected: _settings.setButtonStyleIndex,
              ),
            ),
            const SizedBox(height: 12),
            _section(
              id: 'input-style',
              title: '输入框样式',
              summary: AppSettingsController
                  .inputStyleNames[_settings.inputStyleIndex],
              child: _chipWrap(
                names: AppSettingsController.inputStyleNames,
                selectedIndex: _settings.inputStyleIndex,
                onSelected: _settings.setInputStyleIndex,
              ),
            ),
            const SizedBox(height: 12),
            _section(
              id: 'dialog-style',
              title: '弹窗样式',
              summary:
                  '${AppSettingsController.dialogStyleNames[_settings.dialogStyleIndex]} · 对话框与底部弹层统一生效',
              child: _chipWrap(
                names: AppSettingsController.dialogStyleNames,
                selectedIndex: _settings.dialogStyleIndex,
                onSelected: _settings.setDialogStyleIndex,
              ),
            ),
            const SizedBox(height: 12),
            _buildPresetSection(context),
            if (_settings.loadError != null) ...[
              const SizedBox(height: 12),
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  title: const Text('设置读取失败'),
                  subtitle: Text('${_settings.loadError}'),
                  trailing: TextButton(
                    onPressed: () => _runSetting(_settings.load),
                    child: const Text('重试'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 折叠区块：点击标题展开内容，副标题显示当前值摘要。
  Widget _section({
    required String id,
    required String title,
    required String summary,
    required Widget child,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('appearance-$id'),
        title: Text(title),
        subtitle: Text(
          summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [Align(alignment: Alignment.centerLeft, child: child)],
      ),
    );
  }

  Widget _chipWrap({
    required List<String> names,
    required int selectedIndex,
    required Future<void> Function(int) onSelected,
  }) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (var index = 0; index < names.length; index++)
          ChoiceChip(
            label: Text(names[index]),
            selected: selectedIndex == index,
            onSelected: (_) => _runSetting(() => onSelected(index)),
          ),
      ],
    );
  }

  Widget _buildThemeModeSection(BuildContext context) {
    final summary = switch (_settings.themeMode) {
      ThemeMode.dark => '深色',
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
    };
    return _section(
      id: 'theme-mode',
      title: '显示模式',
      summary: summary,
      child: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('浅色'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('深色'),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.settings_brightness_outlined),
            label: Text('跟随系统'),
          ),
        ],
        selected: {_settings.themeMode},
        onSelectionChanged: (selected) =>
            _runSetting(() => _settings.setThemeMode(selected.first)),
      ),
    );
  }

  Widget _buildThemeColorSection(BuildContext context) {
    final theme = Theme.of(context);
    final custom = _settings.customThemeColor;
    return _section(
      id: 'theme-color',
      title: '主题颜色',
      summary: _settings.isCustomTheme
          ? '自定义'
          : AppSettingsController.colorNames[_settings.colorIndex],
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < AppSettingsController.colors.length; i++)
            ChoiceChip(
              avatar: CircleAvatar(
                radius: 9,
                backgroundColor: AppSettingsController.colors[i],
                child: !_settings.isCustomTheme && _settings.colorIndex == i
                    ? const Icon(Icons.check, color: Colors.white, size: 12)
                    : null,
              ),
              label: Text(AppSettingsController.colorNames[i]),
              selected: !_settings.isCustomTheme && _settings.colorIndex == i,
              onSelected: (_) => _runSetting(() => _settings.setColorIndex(i)),
            ),
          ChoiceChip(
            avatar: CircleAvatar(
              radius: 9,
              backgroundColor: custom ?? theme.colorScheme.surface,
              child: custom == null
                  ? Icon(
                      Icons.palette_outlined,
                      size: 12,
                      color: theme.colorScheme.primary,
                    )
                  : null,
            ),
            label: const Text('自定义'),
            selected: _settings.isCustomTheme,
            onSelected: (_) => _pickThemeCustomColor(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickThemeCustomColor(BuildContext context) async {
    final picked = await AppColorPicker.show(
      context,
      title: '自定义主题色',
      recommended: AppSettingsController.colors,
      current: _settings.customThemeColor ??
          AppSettingsController.colors[_settings.colorIndex],
    );
    if (picked == null) return;
    await _runSetting(() => _settings.setThemeCustomColor(picked));
  }

  Widget _buildBackgroundSection(BuildContext context) {
    final theme = Theme.of(context);
    final customColor = _settings.customBackgroundColor;
    return _section(
      id: 'background-color',
      title: '背景颜色',
      summary: _settings.isCustomBackground
          ? '自定义'
          : AppSettingsController.backgroundNames[_settings.backgroundIndex],
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < AppSettingsController.backgroundColors.length; i++)
            ChoiceChip(
              avatar: CircleAvatar(
                radius: 9,
                backgroundColor: AppSettingsController.backgroundColors[i],
              ),
              label: Text(AppSettingsController.backgroundNames[i]),
              selected: !_settings.isCustomBackground &&
                  _settings.backgroundIndex == i,
              onSelected: (_) =>
                  _runSetting(() => _settings.setBackgroundIndex(i)),
            ),
          ChoiceChip(
            avatar: CircleAvatar(
              radius: 9,
              backgroundColor: customColor ?? theme.colorScheme.surface,
              child: customColor == null
                  ? Icon(
                      Icons.palette_outlined,
                      size: 12,
                      color: theme.colorScheme.primary,
                    )
                  : null,
            ),
            label: const Text('自定义'),
            selected: _settings.isCustomBackground,
            onSelected: (_) => _pickCustomBackground(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomBackground(BuildContext context) async {
    final picked = await AppColorPicker.show(
      context,
      title: '自定义背景色',
      recommended: AppSettingsController.backgroundColors,
      current: _settings.customBackgroundColor,
      showOpacity: true,
    );
    if (picked == null) return;
    await _runSetting(() => _settings.setBackgroundCustomColor(picked));
  }

  Widget _buildFontColorSection(BuildContext context) {
    final theme = Theme.of(context);
    final fontColor = _settings.fontColor;
    final recommended = AppSettingsController.fontRecommended;
    final matchesRecommended = fontColor != null &&
        recommended.any((color) => color.toARGB32() == fontColor.toARGB32());
    return _section(
      id: 'font-color',
      title: '字体颜色',
      summary: fontColor == null ? '默认' : '自定义',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('默认'),
            selected: fontColor == null,
            onSelected: (_) => _runSetting(() => _settings.setFontColor(null)),
          ),
          for (var i = 0; i < recommended.length; i++)
            ChoiceChip(
              avatar: CircleAvatar(radius: 9, backgroundColor: recommended[i]),
              label: Text(AppSettingsController.fontRecommendedNames[i]),
              selected: fontColor != null &&
                  fontColor.toARGB32() == recommended[i].toARGB32(),
              onSelected: (_) =>
                  _runSetting(() => _settings.setFontColor(recommended[i])),
            ),
          ChoiceChip(
            avatar: CircleAvatar(
              radius: 9,
              backgroundColor: matchesRecommended
                  ? theme.colorScheme.surface
                  : (fontColor ?? theme.colorScheme.surface),
              child: fontColor == null || matchesRecommended
                  ? Icon(
                      Icons.palette_outlined,
                      size: 12,
                      color: theme.colorScheme.primary,
                    )
                  : null,
            ),
            label: const Text('自定义'),
            selected: fontColor != null && !matchesRecommended,
            onSelected: (_) => _pickFontColor(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFontColor(BuildContext context) async {
    final picked = await AppColorPicker.show(
      context,
      title: '自定义字体颜色',
      recommended: AppSettingsController.fontRecommended,
      current: _settings.fontColor,
      showOpacity: true,
    );
    if (picked == null) return;
    await _runSetting(() => _settings.setFontColor(picked));
  }

  Widget _buildCardStyleSection(BuildContext context) {
    final theme = Theme.of(context);
    return _section(
      id: 'card-style',
      title: '卡片样式',
      summary:
          '${AppSettingsController.cardStyleNames[_settings.cardStyleIndex]} · '
          '${AppSettingsController.cardElevationNames[_settings.cardElevationIndex]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('圆角', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          _chipWrap(
            names: AppSettingsController.cardStyleNames,
            selectedIndex: _settings.cardStyleIndex,
            onSelected: _settings.setCardStyleIndex,
          ),
          const SizedBox(height: 12),
          Text('阴影', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          _chipWrap(
            names: AppSettingsController.cardElevationNames,
            selectedIndex: _settings.cardElevationIndex,
            onSelected: _settings.setCardElevationIndex,
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSection(BuildContext context) {
    final theme = Theme.of(context);
    const descriptions = <String, String>{
      'minimal': '直角卡片 · 方正按键',
      'standard': '圆角卡片 · 圆角按键',
      'soft': '大圆角卡片 · 轻微阴影',
    };
    const icons = <String, IconData>{
      'minimal': Icons.crop_square,
      'standard': Icons.rounded_corner,
      'soft': Icons.circle_outlined,
    };
    final entries = AppSettingsController.stylePresetNames.entries.toList();
    return _section(
      id: 'style-preset',
      title: '样式套餐',
      summary: _settings.stylePreset.isEmpty
          ? '自定义搭配'
          : AppSettingsController.stylePresetNames[_settings.stylePreset]!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一键应用整套组件风格，单项微调后变为自定义',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                Expanded(
                  child: _buildPresetCard(
                    context,
                    preset: entries[i].key,
                    name: entries[i].value,
                    description: descriptions[entries[i].key]!,
                    icon: icons[entries[i].key]!,
                  ),
                ),
                if (i < entries.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(
    BuildContext context, {
    required String preset,
    required String name,
    required String description,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final selected = _settings.stylePreset == preset;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _runSetting(() => _settings.applyStylePreset(preset)),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                name,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
