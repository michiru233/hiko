import 'package:flutter/widgets.dart';

import 'hiko_breakpoints.dart';

/// 导航壳层：把「导航栏」与「内容」按断点装配到一起。
///
/// - `rail == null`（移动端）→ 只返回内容，底部导航由调用方的
///   `Scaffold.bottomNavigationBar` 提供；
/// - 否则 → 左侧 rail + 右侧内容。
///
/// 页面代码不判断平台、不判断宽度：壳的形态由这一层决定。
class HikoShell extends StatelessWidget {
  const HikoShell({
    super.key,
    required this.child,
    this.rail,
    this.forceRailExpanded,
  });

  final Widget child;

  /// 左侧导航栏（`M3ENavRail`）。null 表示当前形态没有 rail。
  final Widget? rail;

  /// 手动展开/收起覆盖。null 时按断点：expanded → 展开，其余收起。
  final bool? forceRailExpanded;

  /// rail 宽度：收起 96（M3E 规范）、展开 220。
  static const double collapsedWidth = 96;
  static const double expandedWidth = 220;

  @override
  Widget build(BuildContext context) {
    final railWidget = rail;
    if (railWidget == null) return child;
    final expanded =
        forceRailExpanded ?? hikoWindowSizeOf(context) == HikoWindowSize.expanded;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: expanded ? expandedWidth : collapsedWidth,
          child: railWidget,
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// 当前窗口下 rail 的宽度（compact/medium 收起 96，expanded 展开 220）。
///
/// 定位/滚动补偿这类「必须知道侧栏占了多少」的计算统一走它，
/// 避免在业务里再写一遍 96/220 魔法数。
double hikoRailWidthOf(BuildContext context) =>
    hikoWindowSizeOf(context) == HikoWindowSize.expanded
        ? HikoShell.expandedWidth
        : HikoShell.collapsedWidth;
