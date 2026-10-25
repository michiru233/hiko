import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// 按钮变体（M3 的四种 Common Button）。
enum M3EButtonVariant {
  /// 主操作：primary 底
  filled,

  /// 次主操作：secondaryContainer 底
  tonal,

  /// 描边：无底，1dp outline
  outlined,

  /// 文字：无底无描边
  text,
}

/// 按钮尺寸。高度与左右内边距照 Compose token（32/40/56）。
enum M3EButtonSize {
  small(32, 12),
  medium(40, 16),
  large(56, 24);

  const M3EButtonSize(this.height, this.horizontalPadding);

  final double height;
  final double horizontalPadding;
}

/// M3E 按钮。
///
/// 圆角恒为 full（全圆），这是 M3E 最容易辨认的特征之一。
/// 文字用 `labelLarge`；只有 [M3EButtonVariant.filled] 升到 emphasized 字重 ——
/// 「全站加粗等于全站不加粗」，见 §3 原则 2。
class M3EButton extends StatelessWidget {
  const M3EButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = M3EButtonVariant.filled,
    this.size = M3EButtonSize.medium,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final M3EButtonVariant variant;
  final M3EButtonSize size;

  /// 前导图标（16 或 18dp 的 Icon）。不传则为纯文字按钮。
  final Widget? icon;

  /// 撑满父级宽度（移动端底部主按钮用）。
  final bool expand;

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;

    final (background, foreground, border) = switch (variant) {
      M3EButtonVariant.filled => (
          colors.primary,
          colors.onPrimary,
          null,
        ),
      M3EButtonVariant.tonal => (
          colors.secondaryContainer,
          colors.onSecondaryContainer,
          null,
        ),
      M3EButtonVariant.outlined => (
          null,
          colors.primary,
          colors.outline,
        ),
      M3EButtonVariant.text => (
          null,
          colors.primary,
          null,
        ),
    };

    // 禁用态：容器 12% onSurface、文字 38% onSurface（M3 规范值）。
    final effectiveBackground = _enabled
        ? background
        : (background == null
            ? null
            : colors.onSurface.withValues(alpha: 0.12));
    final effectiveForeground = _enabled
        ? foreground
        : colors.onSurface.withValues(alpha: 0.38);

    final textStyle =
        (variant == M3EButtonVariant.filled
                ? theme.type.labelLargeEmphasized
                : theme.type.labelLarge)
            .copyWith(color: effectiveForeground);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          IconTheme.merge(
            data: IconThemeData(size: 18, color: effectiveForeground),
            child: icon!,
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );

    final body = Container(
      height: size.height,
      padding: EdgeInsets.symmetric(horizontal: size.horizontalPadding),
      decoration: BoxDecoration(
        color: effectiveBackground,
        borderRadius: BorderRadius.circular(M3EShape.full),
        border: border == null
            ? null
            : Border.all(
                color: _enabled
                    ? border
                    : colors.onSurface.withValues(alpha: 0.12),
              ),
      ),
      alignment: Alignment.center,
      child: content,
    );

    return M3EPressable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(M3EShape.full),
      pressScale: 0.96,
      semanticLabel: label,
      child: body,
    );
  }
}
