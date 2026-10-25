import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E 筛选芯片（filter chip）。
///
/// 高 32dp、圆角 8dp（芯片不用全圆 —— 全圆留给按钮与指示器，见 §3 原则 3）。
/// 未选：透明底 + 1dp outline 描边；已选：`secondaryContainer` 底 + 前置勾选 + 去掉描边。
///
/// 用勾选而不是只换颜色：状态差异要能扛住色觉障碍与深色模式。
class M3EChip extends StatelessWidget {
  const M3EChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.leading,
    this.showCheckmark = true,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTapDown;

  /// 自定义前导（例如分类色点）。给了它就不画勾选。
  final Widget? leading;

  final bool showCheckmark;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final foreground = !enabled
        ? colors.onSurface.withValues(alpha: 0.38)
        : selected
            ? colors.onSecondaryContainer
            : colors.onSurfaceVariant;

    final body = AnimatedContainer(
      duration: theme.motion.stateLayerDuration,
      curve: Curves.easeOut,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(M3EShape.sm),
        border: selected
            ? null
            : Border.all(
                color: enabled
                    ? colors.outline
                    : colors.onSurface.withValues(alpha: 0.12),
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: 6),
          ] else if (selected && showCheckmark) ...<Widget>[
            Icon(Icons.check, size: 16, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.type.labelLarge.copyWith(color: foreground),
          ),
        ],
      ),
    );

    if (onTap == null && onLongPress == null && onSecondaryTapDown == null) {
      return body;
    }
    return M3EPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      borderRadius: BorderRadius.circular(M3EShape.sm),
      pressScale: 0.96,
      semanticLabel: label,
      child: body,
    );
  }
}
