import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';

/// M3E 滑杆：粗轨道 16dp + 把手 4×44dp 竖条（plan §8.5）。
///
/// 这是 M3 Expressive 观感变化最大的一处：旧滑杆是细线+圆点，
/// 新滑杆是明显的粗轨道，把手是竖条（手柄本身就是「量尺」隐喻）。
class M3ESlider extends StatelessWidget {
  const M3ESlider({
    super.key,
    required this.value,
    required this.max,
    this.min = 0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double value;
  final double max;
  final double min;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 16,
        thumbShape: const M3ESliderThumb(),
        thumbColor: colors.onSurfaceVariant,
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.surfaceContainerHighest,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        overlayColor: colors.primary.withValues(alpha: 0.12),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// M3E 把手：4 宽 × 44 高的竖条，圆角 2。
///
/// Flutter 内置的 `RectangularSliderThumbShape` 画的是以半径为边长的方块，
/// 撑不出「高大于轨道」的竖条，所以自绘。公开成类以便回归锁直测尺寸。
class M3ESliderThumb extends SliderComponentShape {
  const M3ESliderThumb();

  static const double _width = 4;
  static const double _height = 44;
  static const double _radius = 2;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(_width, _height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final rect = Rect.fromCenter(
      center: center,
      width: _width,
      height: _height,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_radius),
    );
    context.canvas.drawRRect(rrect, Paint()..color = sliderTheme.thumbColor!);
  }
}
