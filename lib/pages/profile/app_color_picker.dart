import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 通用颜色选择器：系统推荐色 + 色相环轮盘（全色彩）+ 可选透明度滑杆。
/// 通过 [onChanged] 实时上报选中颜色。
class AppColorPicker extends StatefulWidget {
  const AppColorPicker({
    super.key,
    this.recommended = const [],
    this.current,
    this.showOpacity = false,
    this.onChanged,
  });

  /// 系统推荐色，显示在轮盘上方。
  final List<Color> recommended;

  /// 当前颜色，用于初始化轮盘与打勾标记。
  final Color? current;

  /// 是否显示透明度滑杆（字体颜色等需要透明度的场景）。
  final bool showOpacity;

  /// 选中颜色变化回调。
  final ValueChanged<Color>? onChanged;

  /// 弹出颜色选择对话框，「确定」返回选中颜色，取消返回 null。
  static Future<Color?> show(
    BuildContext context, {
    required String title,
    List<Color> recommended = const [],
    Color? current,
    bool showOpacity = false,
  }) {
    return showDialog<Color>(
      context: context,
      builder: (context) => _AppColorPickerDialog(
        title: title,
        recommended: recommended,
        current: current,
        showOpacity: showOpacity,
      ),
    );
  }

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
}

class _AppColorPickerDialog extends StatefulWidget {
  const _AppColorPickerDialog({
    required this.title,
    required this.recommended,
    required this.current,
    required this.showOpacity,
  });

  final String title;
  final List<Color> recommended;
  final Color? current;
  final bool showOpacity;

  @override
  State<_AppColorPickerDialog> createState() => _AppColorPickerDialogState();
}

class _AppColorPickerDialogState extends State<_AppColorPickerDialog> {
  late Color _selected = widget.current ?? const Color(0xFFE05D78);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      content: AppColorPicker(
        recommended: widget.recommended,
        current: widget.current,
        showOpacity: widget.showOpacity,
        onChanged: (color) => _selected = color,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _AppColorPickerState extends State<AppColorPicker> {
  static const double _wheelSize = 236;
  static const double _ringWidth = 20;
  static const double _ringGap = 6;

  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.current ?? const Color(0xFFE05D78));
  }

  double get _innerRadius => _wheelSize / 2 - _ringWidth - _ringGap;

  void _update(HSVColor color) {
    setState(() => _hsv = color);
    widget.onChanged?.call(color.toColor());
  }

  void _handleWheelGesture(Offset position) {
    final center = const Offset(_wheelSize / 2, _wheelSize / 2);
    final delta = position - center;
    final distance = delta.distance;
    if (distance >= _innerRadius && distance <= _wheelSize / 2) {
      // 色相环：角度即色相。
      var degrees = math.atan2(delta.dy, delta.dx) * 180 / math.pi;
      if (degrees < 0) degrees += 360;
      _update(_hsv.withHue(degrees));
      return;
    }
    // 饱和度/明度方形区。
    final half = _innerRadius / math.sqrt2;
    final dx = delta.dx.clamp(-half, half).toDouble();
    final dy = delta.dy.clamp(-half, half).toDouble();
    final saturation = ((dx + half) / (2 * half)).clamp(0.0, 1.0);
    final value = (1 - (dy + half) / (2 * half)).clamp(0.0, 1.0);
    _update(_hsv.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _hsv.toColor();
    return SizedBox(
      width: _wheelSize + 24,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.recommended.isNotEmpty) ...[
              Text('推荐', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in widget.recommended)
                    InkWell(
                      onTap: () => _update(HSVColor.fromColor(color)),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: selected.toARGB32() == color.toARGB32()
                            ? Icon(
                                Icons.check,
                                size: 15,
                                color: color.computeLuminance() > 0.5
                                    ? Colors.black54
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('全部颜色', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
            ],
            Center(
              child: GestureDetector(
                onTapDown: (details) =>
                    _handleWheelGesture(details.localPosition),
                onPanDown: (details) =>
                    _handleWheelGesture(details.localPosition),
                onPanUpdate: (details) =>
                    _handleWheelGesture(details.localPosition),
                child: CustomPaint(
                  size: const Size(_wheelSize, _wheelSize),
                  painter: _HsvWheelPainter(
                    hsv: _hsv,
                    ringWidth: _ringWidth,
                    innerRadius: _innerRadius,
                  ),
                ),
              ),
            ),
            if (widget.showOpacity) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.opacity, size: 18),
                  Expanded(
                    child: Slider(
                      value: _hsv.alpha,
                      onChanged: (value) => _update(_hsv.withAlpha(value)),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${(_hsv.alpha * 100).round()}%',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: selected,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 色相环 + 饱和度/明度方形区的绘制器。
class _HsvWheelPainter extends CustomPainter {
  const _HsvWheelPainter({
    required this.hsv,
    required this.ringWidth,
    required this.innerRadius,
  });

  final HSVColor hsv;
  final double ringWidth;
  final double innerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);

    // 色相环：扫掠渐变，0° 起始于正右方，与手势 atan2 角度一致。
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..shader = SweepGradient(
        colors: [
          for (var h = 0; h <= 360; h += 30)
            HSVColor.fromAHSV(1, (h % 360).toDouble(), 1, 1).toColor(),
        ],
      ).createShader(bounds);
    canvas.drawCircle(center, radius - ringWidth / 2, ringPaint);

    // 饱和度/明度方形：底色为当前色相，横向白→透明，纵向透明→黑。
    final half = innerRadius / math.sqrt2;
    final square = Rect.fromCenter(
      center: center,
      width: half * 2,
      height: half * 2,
    );
    canvas.drawRect(
      square,
      Paint()..color = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
    );
    canvas.drawRect(
      square,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(square),
    );
    canvas.drawRect(
      square,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(square),
    );

    // 色相指示点。
    final angle = hsv.hue * math.pi / 180;
    final hueCenter = center +
        Offset(math.cos(angle), math.sin(angle)) * (radius - ringWidth / 2);
    canvas.drawCircle(
      hueCenter,
      8,
      Paint()..color = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
    );
    canvas.drawCircle(
      hueCenter,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );

    // 饱和度/明度指示点。
    final svCenter = square.topLeft +
        Offset(hsv.saturation * square.width, (1 - hsv.value) * square.height);
    canvas.drawCircle(
      svCenter,
      7,
      Paint()
        ..color = HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, hsv.value)
            .toColor(),
    );
    canvas.drawCircle(
      svCenter,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HsvWheelPainter oldDelegate) => oldDelegate.hsv != hsv;
}
