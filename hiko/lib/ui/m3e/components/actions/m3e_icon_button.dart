import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// 图标按钮变体（M3 的四种 icon button）。
enum M3EIconButtonVariant {
  /// 无容器：工具栏、顶栏的默认形态。
  standard,

  /// primary 实底：页面里唯一的高优先图标动作。
  filled,

  /// secondaryContainer 色调底：压在封面/渐变上的浮层动作。
  tonal,

  /// 1dp outlineVariant 描边，无底色。
  outlined,
}

/// 图标按钮尺寸。
///
/// [visual] 是视觉圆容器直径，[hit] 是可点区域（含外扩），[icon] 是图标尺寸。
/// 视觉 40 / 热区 48 是 M3 的常用组合：手指点得到，视觉不臃肿。
enum M3EIconButtonSize {
  small(32, 40, 20),
  medium(40, 48, 24),
  large(48, 56, 28);

  const M3EIconButtonSize(this.visual, this.hit, this.icon);

  final double visual;
  final double hit;
  final double icon;
}

/// M3E 图标按钮。
///
/// 交互走 [M3EPressable]：hover 8% / focus 10% / press 10% 状态层 + 弹簧按压 0.94，
/// 与 Button/Card/List 共用同一套反馈。键盘 Enter/Space 可激活。
///
/// 颜色规则：
/// - standard：无底，图标 onSurfaceVariant；选中时 secondaryContainer 底；
/// - filled：primary 底 + onPrimary 图标；
/// - tonal：secondaryContainer 底 + onSecondaryContainer 图标；
/// - outlined：无底 + outlineVariant 描边。
///
/// [backgroundColor] / [foregroundColor] 是「压在封面/渐变上」的逃生口：
/// 调用方可以传 `surfaceContainerHighest.withValues(alpha: .92)` 做浮层底，
/// 但不要用它绕开上面的语义色。
class M3EIconButton extends StatelessWidget {
  const M3EIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.onLongPress,
    this.tooltip,
    this.semanticLabel,
    this.variant = M3EIconButtonVariant.standard,
    this.size = M3EIconButtonSize.medium,
    this.selected = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final String? semanticLabel;
  final M3EIconButtonVariant variant;
  final M3EIconButtonSize size;
  final bool selected;
  final Color? backgroundColor;
  final Color? foregroundColor;

  bool get _enabled => onPressed != null || onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;

    final (
      Color? variantBackground,
      Color variantForeground,
    ) = switch (variant) {
      M3EIconButtonVariant.standard => (
        selected ? colors.secondaryContainer : null,
        selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
      ),
      M3EIconButtonVariant.filled => (colors.primary, colors.onPrimary),
      M3EIconButtonVariant.tonal => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      M3EIconButtonVariant.outlined => (
        selected ? colors.secondaryContainer : null,
        selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
      ),
    };

    // 禁用态：有底的变体降到 12% onSurface，图标 38%；无底变体只降图标。
    final effectiveBackground =
        !_enabled && backgroundColor == null && variantBackground != null
        ? colors.onSurface.withValues(alpha: 0.12)
        : backgroundColor ?? variantBackground;
    final effectiveForeground =
        foregroundColor ??
        (_enabled
            ? variantForeground
            : colors.onSurface.withValues(alpha: 0.38));

    final border = variant == M3EIconButtonVariant.outlined
        ? Border.all(
            color: _enabled
                ? colors.outlineVariant
                : colors.onSurface.withValues(alpha: 0.12),
          )
        : null;

    final button = M3EPressable(
      onTap: onPressed,
      onLongPress: onLongPress,
      enabled: _enabled,
      pressScale: 0.94,
      borderRadius: BorderRadius.circular(M3EShape.full),
      semanticLabel: semanticLabel ?? tooltip,
      child: SizedBox.square(
        dimension: size.hit,
        child: Center(
          child: Container(
            width: size.visual,
            height: size.visual,
            decoration: BoxDecoration(
              color: effectiveBackground,
              shape: BoxShape.circle,
              border: border,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: size.icon, color: effectiveForeground),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    // Tooltip 不再重复贡献语义（M3EPressable 已经给了 label）。
    return Tooltip(
      message: tooltip!,
      excludeFromSemantics: true,
      child: button,
    );
  }
}
