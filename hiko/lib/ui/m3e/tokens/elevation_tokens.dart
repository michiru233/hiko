import 'package:flutter/widgets.dart';

/// M3 海拔（6 级）。
///
/// **M3E 的核心变化：层深靠色阶，不靠阴影。**
/// `surfaceContainerLowest → Lowest → Container → High → Highest` 的明度差
/// 负责区分平面；海拔只留给真正浮起的元素（FAB、菜单、播放条、对话框）。
///
/// 这条对 Hiko 是结构性利好：旧版玻璃卡在深色下只比底色亮 2，只能靠描边定义自己；
/// 换成色调面后明度差由角色决定（见 plan-hiko-m3e-redesign.md §1.1）。
abstract final class M3EElevation {
  /// 0dp：绝大多数平面（卡片、列表、栏）
  static const double level0 = 0;

  /// 1dp：抬升卡、模态 sheet
  static const double level1 = 1;

  /// 3dp：菜单、搜索栏、浮动 toolbar
  static const double level3 = 3;

  /// 6dp：FAB、FAB menu
  static const double level6 = 6;

  /// 8dp：拖拽中的元素
  static const double level8 = 8;

  /// 12dp：最高层（保留）
  static const double level12 = 12;

  /// 全部六级，顺序即标尺顺序。
  static const List<double> scale = <double>[
    level0,
    level1,
    level3,
    level6,
    level8,
    level12,
  ];

  /// 把海拔换成 Flutter 的阴影列表。
  ///
  /// 0dp 返回空表（不是「透明阴影」）—— 空表在合成阶段零开销，
  /// 而 alpha=0 的 BoxShadow 仍会参与绘制列表的遍历。
  static List<BoxShadow> shadow(double dp, Color color) {
    if (dp <= 0) return const <BoxShadow>[];
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: 0.30),
        blurRadius: dp * 2,
        offset: Offset(0, dp),
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.12),
        blurRadius: dp * 3,
        spreadRadius: -dp,
      ),
    ];
  }
}
