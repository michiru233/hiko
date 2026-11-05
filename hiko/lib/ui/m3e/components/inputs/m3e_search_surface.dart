import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/elevation_tokens.dart';
import '../../tokens/opacity_tokens.dart';
import '../../tokens/shape_tokens.dart';

/// 搜索框的唯一壳（1.99.71）。
///
/// 折叠胶囊 [M3ESearchEntry] 与放大后的输入框 [M3ESearchBar] 都是「全圆、
/// `surfaceContainerHigh`、海拔 3、前置放大镜、尾部槽」这一套。1.99.70 时两处
/// 各写了一份 `Container`，改一处必漂；这里收成一个组件。
///
/// [surfaceOpacity] 是用户可调的「搜索框不透明度」：只调填充与阴影的 alpha，
/// 不做模糊、不做玻璃。0 时填充与阴影都消失，只剩图标与文字。
class M3ESearchSurface extends StatelessWidget {
  const M3ESearchSurface({
    super.key,
    required this.child,
    this.height = 48,
    this.trailing,
    this.fillColor,
    this.surfaceOpacity = 1,
    this.enabled = true,
  });

  final Widget child;

  final double height;

  /// 尾部槽（清除钮 / 空占位）。null 时补一个 8dp 间距。
  final Widget? trailing;

  /// 覆盖填充色（浮层里用 `surfaceContainerHighest` 与面板拉开一档）。
  /// null → `surfaceContainerHigh`。
  final Color? fillColor;

  final double surfaceOpacity;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final opacity = M3ESurfaceOpacity.clamp(surfaceOpacity);
    final fill = enabled
        ? M3ESurfaceOpacity.apply(
            fillColor ?? colors.surfaceContainerHigh,
            opacity,
          )
        // M3 的「填充面禁用」配方：容器 12% + 前景 38%
        : colors.onSurface.withValues(alpha: 0.12 * opacity);
    final iconColor = enabled
        ? colors.onSurfaceVariant
        : colors.onSurface.withValues(alpha: 0.38);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(M3EShape.full),
        boxShadow: M3EElevation.shadow(
          M3EElevation.level3,
          colors.shadow,
          opacity: opacity,
        ),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          Icon(Icons.search_rounded, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: child),
          trailing ?? const SizedBox(width: 8),
        ],
      ),
    );
  }
}
