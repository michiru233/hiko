import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E 连通式按钮组（connected button group）。
///
/// 高 40dp、全圆外轮廓、选中段是内嵌的药丸（`secondaryContainer`）。
/// 与 M3 的分段按钮语义相同，但几何按 M3E：**整组一个容器**，
/// 而不是几颗独立按钮挨在一起 —— 后者在窄屏上会出现「三个胶囊互相挤压」。
class M3EButtonGroup extends StatelessWidget {
  const M3EButtonGroup({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 40,
  });

  final List<String> labels;

  /// 选中段下标；-1 表示无选中。
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(M3EShape.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < labels.length; i++)
            _Segment(
              label: labels[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    return M3EPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(M3EShape.full),
      pressScale: 0.96,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: theme.motion.stateLayerDuration,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(M3EShape.full),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (selected
                  ? theme.type.labelLargeEmphasized
                  : theme.type.labelLarge)
              .copyWith(
            color: selected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
