import 'package:flutter/material.dart';

/// 移动端底部导航（1.99.4，裁决 Q2=B / Q6=B）。
///
/// 一级项由设置驱动（与桌面侧栏**共用**一份 `settings.navViews`），末尾另有
/// **两个固定格**：它们不占 `navViews` 表、用户关不掉。
///
/// 1. 「正在播放」→ 打开全屏播放页（1.99.6，裁决 Q6=A / Q7=A / Q11=A）。
///    固定下来的理由是「左划收起播放栏」必须有一条**一定找得回来**的路；
///    没有正在播放的专辑时置灰不可点，但**格子留在原位**（不跳位、不消失）。
/// 2. 「设置」。
///
/// 不用 `BottomNavigationBar`：超过 5 项时它的标签会挤压溢出，
/// 这里自绘整行 —— 放得下时均分宽度，放不下时整行横向滑动。
///
/// 1.99.6 从 `home_screen.dart` 的私有 `_MobileBottomNav` 抽出为公开组件，
/// 理由与 1.97.1 抽筛选标记一致：**可测**（widget 测试跑在 macOS 宿主上，
/// `Platform.isAndroid` 恒为 false，移动布局在整页测试里够不着）。
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.views,
    required this.currentIndex,
    required this.onTapView,
    required this.onOpenPlayer,
    required this.onOpenSettings,
    this.playerEnabled = false,
  });

  /// 由 `settings.navViews` 驱动的一级视图（「本地音声」必定在列）
  final List<String> views;

  /// 当前高亮的视图下标 —— 对应 [views]；两个固定格永不参与高亮
  final int currentIndex;

  /// 点击一级视图（参数是 [views] 的下标）
  final ValueChanged<int> onTapView;

  /// 点击固定格「正在播放」→ 全屏播放页
  final VoidCallback onOpenPlayer;

  /// 点击固定格「设置」
  final VoidCallback onOpenSettings;

  /// 有正在播放的专辑才可点（没有则置灰）
  final bool playerEnabled;

  /// 导航视图 → Material 图标（桌面侧栏的字符图标映射见 sidebar.dart）
  static const icons = <String, IconData>{
    '本地音声': Icons.grid_view_rounded,
    '最近添加': Icons.schedule_rounded,
    '最近播放': Icons.history_rounded,
    '收藏夹': Icons.favorite_border_rounded,
    '在线': Icons.cloud_outlined,
    '在线收藏': Icons.favorite_rounded,
    '统计': Icons.bar_chart_rounded,
  };

  /// 固定格「正在播放」的文案与图标。
  /// 1.99.6 沿用 1.99.4 那一格的图标：同一格的语义从「空壳视图」换成
  /// 「打开全屏播放页」，外观不变才不会让老用户以为多了个新东西。
  static const playerLabel = '正在播放';
  static const playerIcon = Icons.play_arrow_rounded;

  /// 固定格「设置」的文案与图标
  static const settingsLabel = '设置';
  static const settingsIcon = Icons.settings_outlined;

  /// 一格的最小宽度（放不下时整行横向滑动，宽度就按它定格）
  static const itemWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 两个固定格也参与「放不放得下」的估算（1.99.6 起从 +1 变 +2）
        final fits = (views.length + 2) * itemWidth <= constraints.maxWidth;

        Widget cell({
          required String label,
          required IconData icon,
          required bool selected,
          required bool enabled,
          required VoidCallback onTap,
        }) {
          final color = !enabled
              ? theme.disabledColor
              : selected
                  ? theme.colorScheme.primary
                  : theme.hintColor;
          final child = InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: color),
                  ),
                ],
              ),
            ),
          );
          // 禁用格同样要占位（Expanded / 固定宽），否则「正在播放」消失会
          // 让整行跟着跳位
          return fits
              ? Expanded(child: child)
              : SizedBox(width: itemWidth, child: child);
        }

        final row = Row(
          children: [
            for (final (i, view) in views.indexed)
              cell(
                label: view,
                icon: icons[view] ?? Icons.circle_outlined,
                selected: i == currentIndex,
                enabled: true,
                onTap: () => onTapView(i),
              ),
            // 固定两格（顺序固定：正在播放、设置），不占 navViews 表
            cell(
              label: playerLabel,
              icon: playerIcon,
              selected: false,
              enabled: playerEnabled,
              onTap: onOpenPlayer,
            ),
            cell(
              label: settingsLabel,
              icon: settingsIcon,
              selected: false,
              enabled: true,
              onTap: onOpenSettings,
            ),
          ],
        );
        if (fits) return row;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: row,
        );
      },
    );
  }
}
