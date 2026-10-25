import 'package:flutter/widgets.dart';

/// 导航目的地（rail / bar 共用一份数据）。
///
/// 一个目的地 = 标签 + 静息图标 + 选中图标 + 可选计数。
/// 选中态用「实心图标」表达（M3E 的导航指示器语言），
/// 所以每个目的地必须给出两个图标 —— 只用颜色区分会被深色模式吃掉对比度。
@immutable
class M3ENavigationDestination {
  const M3ENavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// 计数徽标。null 或 <= 0 不显示。
  final int? badge;

  final bool enabled;
}
