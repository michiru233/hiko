import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/elevation_tokens.dart';
import '../../tokens/shape_tokens.dart';

enum M3ESheetVariant {
  /// 桌面侧滑面板：贴边、通高、宽 480（plan §8.4）。
  side,

  /// 移动底部面板：28dp 顶角，覆在内容之上。
  bottom,
}

/// M3E 详情面板（替代玻璃抽屉）。
///
/// 材质是**不透明色调面**（`surfaceContainerLow`），层级靠色阶与投影，
/// 不再有 σ55 氛围光晕与玻璃边框（plan §8.4 / §9.1）。
///
/// 定位与尺寸（贴右缘 / 贴底、宽多少）由调用方的 `Positioned` 决定，
/// 本组件只管材质与形状。
class M3ESheet extends StatelessWidget {
  const M3ESheet({
    super.key,
    required this.child,
    this.variant = M3ESheetVariant.side,
    this.color,
  });

  final Widget child;
  final M3ESheetVariant variant;

  /// 覆盖底色（默认 `surfaceContainerLow`）。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final background = color ?? colors.surfaceContainerLow;

    switch (variant) {
      case M3ESheetVariant.side:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            boxShadow: M3EElevation.shadow(M3EElevation.level3, colors.shadow),
          ),
          child: child,
        );
      case M3ESheetVariant.bottom:
        final radius = BorderRadius.vertical(
          top: Radius.circular(M3EShape.xl),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            boxShadow: M3EElevation.shadow(M3EElevation.level3, colors.shadow),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: child,
          ),
        );
    }
  }
}
