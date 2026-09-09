import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

/// 通用玻璃拟态容器
/// 遵循性能与体验分离原则：
/// - [blur] > 0 时使用硬件加速的 BackdropFilter 模糊背后内容（适合悬浮栏、顶栏、模态抽屉）
/// - [blur] == 0 时使用纯 CSS 风格的高透仿玻璃渐变（适合长列表高频滑动的卡片，规避 GPU 过载）
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 16.0,
    this.borderRadius = 16.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderColor,
    this.borderWidth = 1.0,
    this.backgroundColor,
    this.gradient,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final double blur;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultBg = backgroundColor ??
        (isDark ? HikoColors.darkGlassSurface : HikoColors.lightGlassSurface);

    final defaultBorderColor = borderColor ??
        (isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorder);

    final defaultShadow = boxShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ];

    final decoration = BoxDecoration(
      color: gradient == null ? defaultBg : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: defaultBorderColor,
        width: borderWidth,
      ),
      boxShadow: defaultShadow,
    );

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (blur > 0) {
      return Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          clipBehavior: clipBehavior,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: content,
          ),
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: content);
    }

    return content;
  }
}
