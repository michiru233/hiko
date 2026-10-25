import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/elevation_tokens.dart';
import '../../tokens/shape_tokens.dart';

/// M3E 浮动工具条：64dp 高、全圆、`surfaceContainerHigh`、海拔 3。
///
/// 全产品的「功能承载条」只有两种形态：导航（`M3ENavBar` / `M3ENavRail`）
/// 与本组件。播放条、播放页辅助区都用它，保证同一层级观感一致
/// （plan-hiko-m3e-redesign.md §8.5 / §8.6）。
class M3EToolbar extends StatelessWidget {
  const M3EToolbar({
    super.key,
    required this.child,
    this.height = 64,
    this.margin = const EdgeInsets.all(16),
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final double height;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final radius = BorderRadius.circular(M3EShape.full);
    return Padding(
      padding: margin,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: radius,
            boxShadow: M3EElevation.shadow(M3EElevation.level3, colors.shadow),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
