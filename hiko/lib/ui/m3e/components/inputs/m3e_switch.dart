import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E 开关（1.99.43，B2 后半）。
///
/// 轨道 52×32、圆角 16；把手选中 24 / 未选 16，靠 `AnimatedAlign` 平移。
/// 选中：`primary` 轨 + `onPrimary` 把手；未选：`surfaceContainerHighest` 轨 +
/// 2dp `outline` 描边 + `outline` 把手。
///
/// 只画控件本身，不带标签 —— 设置页的行已经有标题与副标题
/// （[M3EListItem] / 设置行壳），再给开关配一套自带标签会立刻出现两套排版。
class M3ESwitch extends StatelessWidget {
  const M3ESwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  final bool value;

  /// 传 null 即禁用（与 Material `Switch` 的 `onChanged` 语义一致）。
  final ValueChanged<bool>? onChanged;

  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final on = value;
    final active = enabled && onChanged != null;

    final trackColor = !active
        ? colors.onSurface.withValues(alpha: 0.12)
        : on
        ? colors.primary
        : colors.surfaceContainerHighest;
    final thumbColor = !active
        ? colors.onSurface.withValues(alpha: 0.38)
        : on
        ? colors.onPrimary
        : colors.outline;
    final thumbSize = on ? 24.0 : 16.0;

    return Semantics(
      toggled: on,
      enabled: active,
      label: semanticLabel,
      child: M3EPressable(
        enabled: active,
        onTap: active ? () => onChanged!(!on) : null,
        borderRadius: BorderRadius.circular(M3EShape.full),
        pressScale: 0.96,
        // 行里垂直居中；高度 48 保证触控目标
        child: SizedBox(
          width: 52,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: theme.motion.stateLayerDuration,
              curve: Curves.easeOut,
              width: 52,
              height: 32,
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: BorderRadius.circular(M3EShape.full),
                border: Border.all(
                  color: on || !active ? Colors.transparent : colors.outline,
                  width: 2,
                ),
              ),
              child: AnimatedAlign(
                duration: theme.motion.stateLayerDuration,
                curve: Curves.easeOut,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedContainer(
                    duration: theme.motion.stateLayerDuration,
                    curve: Curves.easeOut,
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                    ),
                    child: on
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: !active ? colors.surface : colors.onPrimary,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
