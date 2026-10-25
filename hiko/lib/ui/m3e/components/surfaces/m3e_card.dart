import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/elevation_tokens.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// 卡片变体（对应 M3 的 filled / elevated / outlined 三型）。
enum M3ECardVariant {
  /// 填充：最亮的内容容器（surfaceContainerHighest），用于需要「跳出来」的卡
  filled,

  /// 抬升：容器色 + 1dp 阴影，用于需要轻微浮起的卡
  elevated,

  /// 描边：容器色 + 1dp 描边，用于不想产生阴影的密集排布
  outlined,
}

/// M3E 卡片。
///
/// 默认 16dp 圆角（Hiko 的内容面基准），**不是 M3 默认的 12dp** ——
/// 12dp 留给卡片内部的图片（嵌套规则：16 − 4 padding = 12），
/// 这样卡片与封面之间才有层级感（见 plan-hiko-m3e-redesign.md §4.4）。
class M3ECard extends StatelessWidget {
  const M3ECard({
    super.key,
    required this.child,
    this.variant = M3ECardVariant.filled,
    this.padding = const EdgeInsets.all(16),
    this.radius = M3EShape.lg,
    this.color,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.clipBehavior = Clip.antiAlias,
    this.semanticLabel,
  });

  final Widget child;
  final M3ECardVariant variant;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// 覆盖底色（例如「正在播放」的卡用 `primaryContainer`）。
  final Color? color;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTapDown;
  final Clip clipBehavior;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final background = color ??
        switch (variant) {
          M3ECardVariant.filled => colors.surfaceContainerHighest,
          M3ECardVariant.elevated => colors.surfaceContainerLow,
          M3ECardVariant.outlined => colors.surfaceContainerLow,
        };
    final shadows = variant == M3ECardVariant.elevated
        ? M3EElevation.shadow(M3EElevation.level1, colors.shadow)
        : const <BoxShadow>[];
    final borderRadius = BorderRadius.circular(radius);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: Padding(padding: padding, child: child),
      ),
    );

    if (variant == M3ECardVariant.outlined) {
      // 描边画在前景：否则会被卡片内容（尤其是贴边的封面）盖住。
      surface = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: surface,
      );
    }

    if (onTap == null && onLongPress == null && onSecondaryTapDown == null) {
      return surface;
    }
    return M3EPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      borderRadius: borderRadius,
      pressScale: 0.98,
      semanticLabel: semanticLabel,
      child: surface,
    );
  }
}
