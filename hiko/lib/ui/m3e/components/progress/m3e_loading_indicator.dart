import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart' as shapes;

import '../../theme/m3e_theme.dart';
import '../../tokens/motion_tokens.dart';

/// 形状环：相邻两项互为 morph 目标，末项回卷到首项。
final List<shapes.RoundedPolygon> _ring = [
  shapes.MaterialShapes.circle,
  shapes.MaterialShapes.pill,
  shapes.MaterialShapes.sunny,
];


/// M3E 加载指示器：38dp 形状变形（circle → pill → sunny 循环，plan §8.8）。
///
/// 形状来自 `material_new_shapes`（用户裁决引入，1.99.31）。两条实现约束：
/// - 连续动画**不用弹簧**（§7.2 弹簧只跟离散交互）：线性循环 + 每段 easeInOut；
/// - 动效档门控：off 画静态形状、连控制器都不建（§7.4-3），reduced 时长 ×2。
class M3ELoadingIndicator extends StatefulWidget {
  const M3ELoadingIndicator({super.key, this.size = 38, this.color});

  final double size;
  final Color? color;

  @override
  State<M3ELoadingIndicator> createState() => _M3ELoadingIndicatorState();
}

class _M3ELoadingIndicatorState extends State<M3ELoadingIndicator>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  M3EMotion _motion = const M3EMotion();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = M3ETheme.of(context).motion;
    if (_motion.enabled && _controller == null) {
      final mult = _motion.level == M3EMotionLevel.reduced ? 2 : 1;
      _controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 900 * mult * _ring.length),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? M3ETheme.of(context).colors.primary;
    final controller = _controller;
    final painter = _MorphPainter(
      progress: controller?.value ?? 0,
      color: color,
      animate: controller != null,
    );

    if (controller != null) {
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: painter,
          ),
        ),
      );
    }
    // 动效关闭：静态圆形（终态）
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(widget.size), painter: painter),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.progress,
    required this.color,
    required this.animate,
  });

  /// 0~1 的全局进度（控制器值）；非动画态忽略。
  final double progress;
  final Color color;
  final bool animate;

  static const int _segmentCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (!animate) {
      _drawFitted(canvas, size, _ring[0].toPath(), paint);
      return;
    }
    final pos = progress * _segmentCount;
    final segment = pos.floor() % _ring.length;
    final local = Curves.easeInOut.transform(pos - pos.floorToDouble());
    final morph = shapes.Morph(
      _ring[segment],
      _ring[(segment + 1) % _ring.length],
    );
    _drawFitted(canvas, size, morph.toPath(progress: local), paint);
  }

  /// 形状在包内是单位空间（约 ±0.5），按外接框适配到给定尺寸并居中。
  void _drawFitted(Canvas canvas, Size size, Path path, Paint paint) {
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;
    final scale =
        (size.shortestSide * 0.92) / bounds.longestSide.clamp(0.001, 10);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale, scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.animate != animate;
}
