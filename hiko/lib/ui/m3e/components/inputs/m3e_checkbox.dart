import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E 复选框（1.99.43）。
///
/// 视觉 18×18、圆角 4（`M3EShape.xs`），热区 40×40。
/// 选中：`primary` 实底 + `onPrimary` 勾；未选：2dp `outline` 描边。
/// 三态（indeterminate）不提供 —— 设置页与列表里都是二态，加了只会多一条分支。
class M3ECheckbox extends StatelessWidget {
  const M3ECheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final on = value;
    final active = enabled && onChanged != null;

    final fill = !active
        ? (on ? colors.onSurface.withValues(alpha: 0.38) : Colors.transparent)
        : on
        ? colors.primary
        : Colors.transparent;
    final border = !active
        ? colors.onSurface.withValues(alpha: 0.38)
        : on
        ? Colors.transparent
        : colors.outline;

    return Semantics(
      checked: on,
      enabled: active,
      label: semanticLabel,
      child: M3EPressable(
        enabled: active,
        onTap: active ? () => onChanged!(!on) : null,
        borderRadius: BorderRadius.circular(M3EShape.full),
        pressScale: 0.94,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: AnimatedContainer(
              duration: theme.motion.stateLayerDuration,
              curve: Curves.easeOut,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(M3EShape.xs),
                border: Border.all(color: border, width: 2),
              ),
              child: on
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: active ? colors.onPrimary : colors.surface,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
