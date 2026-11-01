import 'package:flutter/material.dart';

import '../theme/m3e_theme.dart';
import '../tokens/shape_tokens.dart';
import 'm3e_nav_badge.dart';
import 'm3e_navigation_destination.dart';

/// M3E 导航抽屉（移动端形态，1.99.65）。
///
/// 从屏幕左缘往右拖拉出，日常隐藏 —— 安卓的 drawer 惯例，手势由
/// `Scaffold.drawerEnableOpenDragGesture` 提供（左缘 20dp 起手，配合
/// `MainActivity` 的系统手势排除区），本组件只负责外观与内容。
///
/// 与 [M3ENavRail]（桌面侧栏）同源：同一份 [M3ENavigationDestination]，
/// 差别只在容器 —— 抽屉 308dp、右缘 `xl` 圆角、`surfaceContainerLow` 底
/// （浮在内容之上，比 `surface` 的侧栏高一档材质），条目 56dp 通栏、
/// 选中铺 `secondaryContainer` 色块。
class M3ENavDrawer extends StatelessWidget {
  const M3ENavDrawer({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.header,
    this.hint,
  });

  /// 抽屉宽度：308dp，占 390dp 窄屏的 79%，露出右侧内容便于点遮罩关闭。
  static const double width = 308;

  final List<M3ENavigationDestination> destinations;

  /// 选中项下标；-1 表示没有选中项（例如当前是分类视图）。
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// 顶部品牌区（与桌面侧栏共用同一份「H logo + Hiko / 音声收藏室」）。
  final Widget? header;

  /// 底部说明文案（「从屏幕左缘往右拖可随时拉出」这类）。
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    return Drawer(
      width: width,
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(M3EShape.xl),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 18),
                child: header,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: <Widget>[
                  for (var i = 0; i < destinations.length; i++)
                    _NavDrawerItem(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      onTap: destinations[i].enabled
                          ? () => onSelected(i)
                          : null,
                    ),
                ],
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Text(
                  hint!,
                  style: theme.type.labelSmall.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavDrawerItem extends StatelessWidget {
  const _NavDrawerItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final M3ENavigationDestination destination;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final foreground = onTap == null
        ? colors.onSurface.withValues(alpha: 0.38)
        : selected
            ? colors.onSecondaryContainer
            : colors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: selected,
        button: onTap != null,
        child: Material(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: M3EShape.radius(M3EShape.full),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: M3EShape.radius(M3EShape.full),
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 24,
                      color: foreground,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.type.labelLarge.copyWith(
                          color: foreground,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    if (destination.badge != null && destination.badge! > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: NavBadge(count: destination.badge!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
