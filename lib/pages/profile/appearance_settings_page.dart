import 'dart:async';

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
            const SizedBox(height: 20),
            _buildColorSection(context),
            const SizedBox(height: 20),
            _buildChoicesSection(
              context: context,
              title: '字体大小',
              names: AppSettingsController.fontScaleNames,
              selectedIndex: _settings.fontScaleIndex,
              onSelected: _settings.setFontScaleIndex,
            ),
            const SizedBox(height: 16),
            _buildChoicesSection(
              context: context,
              title: '卡片样式',
              names: AppSettingsController.cardStyleNames,
              selectedIndex: _settings.cardStyleIndex,
              onSelected: _settings.setCardStyleIndex,
            ),
            const SizedBox(height: 16),
            _buildChoicesSection(
              context: context,
              title: '按键样式',
              names: AppSettingsController.buttonStyleNames,
              selectedIndex: _settings.buttonStyleIndex,
              onSelected: _settings.setButtonStyleIndex,
            ),
            const SizedBox(height: 20),
            _buildBackgroundSection(context),
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

  Widget _buildThemeModeSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('显示模式', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
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
          ],
        ),
      ),
    );
  }

  Widget _buildColorSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('主题颜色', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < AppSettingsController.colors.length; i++)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 9,
                      backgroundColor: AppSettingsController.colors[i],
                      child: _settings.colorIndex == i
                          ? const Icon(Icons.check, color: Colors.white, size: 12)
                          : null,
                    ),
                    label: Text(AppSettingsController.colorNames[i]),
                    selected: _settings.colorIndex == i,
                    onSelected: (_) =>
                        _runSetting(() => _settings.setColorIndex(i)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('背景颜色', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
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
                    selected: _settings.backgroundIndex == i,
                    onSelected: (_) =>
                        _runSetting(() => _settings.setBackgroundIndex(i)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoicesSection({
    required BuildContext context,
    required String title,
    required List<String> names,
    required int selectedIndex,
    required Future<void> Function(int) onSelected,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
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
          ),
        ],
      ),
    ),
  );
}
