import 'package:flutter/material.dart';

import '../theme/m3e_theme.dart';
import '../tokens/shape_tokens.dart';

/// 抽屉把手（1.99.65）：贴在屏幕左缘的小竖条，提示「这里可以往右划」。
///
/// 只在移动端、抽屉关闭时出现。本身**不吃手势**（外层包 `IgnorePointer`）——
/// 划出的手势归 `Scaffold.drawerEnableOpenDragGesture`，把手指从这条 4dp
/// 上拖出去也是划出，不会因为落在把手外面而失败。
class M3ENavEdgeHandle extends StatelessWidget {
  const M3ENavEdgeHandle({super.key});

  /// 把手宽（竖直、贴左缘）。
  static const double width = 4;

  /// 把手高。
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.outlineVariant.withValues(alpha: 0.8),
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(M3EShape.full),
          ),
        ),
      ),
    );
  }
}
