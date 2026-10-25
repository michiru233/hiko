import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E FAB。目前只用 large 档（96dp / 角 28）：播放页的主键（播放/暂停）。
///
/// 颜色走 M3 规范：`primaryContainer` 底 + `onPrimaryContainer` 图标；
/// 按压缩放交给 [M3EPressable]（与全产品同一套弹簧）。
class M3EFab extends StatelessWidget {
  const M3EFab({
    super.key,
    required this.child,
    this.onPressed,
    this.size = 96,
    this.radius = M3EShape.xl,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double size;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final borderRadius = BorderRadius.circular(radius);
    return M3EPressable(
      onTap: onPressed,
      borderRadius: borderRadius,
      pressScale: 0.96,
      stateLayerColor: colors.onPrimaryContainer,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: IconTheme.merge(
          data: IconThemeData(
            color: colors.onPrimaryContainer,
            size: size * 0.38,
          ),
          child: child,
        ),
      ),
    );
  }
}
