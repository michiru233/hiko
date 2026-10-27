import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E 复选框（1.99.43）。
///
/// 视觉 18×18、圆角 4（`M3EShape.xs`），热区 40×40。
/// 选中：`primary` 实底 + `onPrimary` 勾；未选：2dp `outline` 描边；
/// 部分选中（[indeterminate]）：`primary` 实底 + 横杠。
///
/// **三态只在「全选」类语义里用**（离线下载的全选 / 组全选，1.99.53）：
/// 它表达的是「下面有些选了、有些没选」，而不是一个独立于二态的第三种值 ——
/// 点击仍按二态走（部分选中 → 全选）。设置页那种单个开关不要传它。
class M3ECheckbox extends StatelessWidget {
  const M3ECheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
    this.indeterminate = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final String? semanticLabel;

  /// 部分选中：`value == false` 时画横杠而不是空框。
  ///
  /// 只是**画什么**的开关，不改变 [value] 语义：调用方仍按「是否全选」传
  /// [value]，部分选中时传 `false` + `indeterminate: true`。
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final on = value;
    // 横杠与勾用同一套底色：都代表「这里不是空的」
    final filled = on || indeterminate;
    final active = enabled && onChanged != null;

    final fill = !active
        ? (filled
              ? colors.onSurface.withValues(alpha: 0.38)
              : Colors.transparent)
        : filled
        ? colors.primary
        : Colors.transparent;
    final border = !active
        ? colors.onSurface.withValues(alpha: 0.38)
        : filled
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
                  : indeterminate
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 2,
                        decoration: BoxDecoration(
                          color: active ? colors.onPrimary : colors.surface,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
