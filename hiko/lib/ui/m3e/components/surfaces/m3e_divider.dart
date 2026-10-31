import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';

/// M3E 分割线（1.99.60）。
///
/// 只有一种画法：1dp `outlineVariant`。业务层此前散着三种——`height: 1` 的
/// 裸 `Divider`、带 `thickness` 的、以及还在用旧 `theme.dividerColor` 的
/// （`theme.dividerColor` 是 Material 2 遗留，换了配色方案不会跟着走）。
///
/// 不给 `thickness` 参数：1dp 是 M3E 的唯一规格，要更重就用 `M3ECard` 的边界
/// 或分区标题，而不是把一条线画粗。
class M3EDivider extends StatelessWidget {
  const M3EDivider({super.key, this.indent = 0, this.endIndent = 0, this.color});

  final double indent;
  final double endIndent;

  /// 默认 `outlineVariant`；只有「分隔线在彩色底上」这类场景才该覆盖。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: color ?? colors.outlineVariant,
    );
  }
}
