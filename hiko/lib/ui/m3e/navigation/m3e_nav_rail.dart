import 'package:flutter/material.dart';

import '../adaptive/hiko_breakpoints.dart';
import '../theme/m3e_theme.dart';
import '../tokens/shape_tokens.dart';
import 'm3e_nav_badge.dart';
import 'm3e_navigation_destination.dart';

/// M3E 导航栏（桌面/平板形态，竖向）。
///
/// 收起 96dp / 展开 220dp（宽度由 [HikoShell] 的 SizedBox 决定，本组件只负责内容）。
/// 项高 64dp，选中指示器 56×32 全圆；收起态图标在上、标签在下，
/// 展开态图标在左、标签在右 —— 两种形态共用同一份目的地数据。
///
/// 视觉上不再有分隔线：M3E 用 `surfaceContainerLow` 与内容的 `surface`
/// 之间的明度差划出导航区，而不是画一条线（见 §3 原则 1）。
class M3ENavRail extends StatelessWidget {
  const M3ENavRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.expanded,
    this.header,
    this.trailing,
  });

  final List<M3ENavigationDestination> destinations;

  /// 选中项下标；-1 表示没有选中项（例如当前是分类视图）。
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// 是否展开（图标 + 文字）。null 时按窗口断点：expanded → 展开。
  final bool? expanded;

  /// 顶部品牌区（可选）
  final Widget? header;

  /// 底部固定区（设置入口）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final isExpanded =
        expanded ?? hikoWindowSizeOf(context) == HikoWindowSize.expanded;
    return ColoredBox(
      color: theme.colors.surfaceContainerLow,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (header != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isExpanded ? 20 : 0,
                  18,
                  isExpanded ? 20 : 0,
                  14,
                ),
                child: isExpanded ? header : Center(child: header),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 8),
                children: <Widget>[
                  for (var i = 0; i < destinations.length; i++)
                    _NavRailItem(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      expanded: isExpanded,
                      onTap: destinations[i].enabled
                          ? () => onSelected(i)
                          : null,
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isExpanded ? 12 : 8,
                  8,
                  isExpanded ? 12 : 8,
                  12,
                ),
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavRailItem extends StatelessWidget {
  const _NavRailItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final M3ENavigationDestination destination;
  final bool selected;
  final bool expanded;
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

    final indicator = AnimatedContainer(
      duration: theme.motion.stateLayerDuration,
      curve: Curves.easeOut,
      width: 56,
      height: 32,
      decoration: BoxDecoration(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(M3EShape.full),
      ),
      child: Icon(
        selected ? destination.selectedIcon : destination.icon,
        size: 24,
        color: foreground,
      ),
    );

    final badge = destination.badge != null && destination.badge! > 0
        ? NavBadge(count: destination.badge!)
        : null;

    final label = Text(
      destination.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (selected
              ? theme.type.labelMediumEmphasized
              : theme.type.labelMedium)
          .copyWith(color: foreground),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: M3ENavRailItemSurface(
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: expanded
              ? Row(
                  children: <Widget>[
                    indicator,
                    const SizedBox(width: 12),
                    Expanded(child: label),
                    // 展开态：计数跟在标签右侧（对齐旧侧栏的信息位），
                    // 不叠在图标上 —— 叠上去 24dp 图标会被 16dp 徽标压掉一半。
                    if (badge != null) ...<Widget>[
                      const SizedBox(width: 8),
                      badge,
                    ],
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        indicator,
                        if (badge != null)
                          Positioned(right: -2, top: -2, child: badge),
                      ],
                    ),
                    const SizedBox(height: 4),
                    label,
                  ],
                ),
        ),
      ),
    );
  }
}

/// rail 的固定动作项（底部「设置」）。
///
/// 与导航项同一套几何，但没有选中态、没有指示器 —— 它不是目的地，是动作。
class M3ENavRailAction extends StatelessWidget {
  const M3ENavRailAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.expanded,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final isExpanded =
        expanded ?? hikoWindowSizeOf(context) == HikoWindowSize.expanded;
    final foreground = onTap == null
        ? colors.onSurface.withValues(alpha: 0.38)
        : colors.onSurfaceVariant;
    return M3ENavRailItemSurface(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: isExpanded
            ? Row(
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Icon(icon, size: 24, color: foreground),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.type.labelMedium.copyWith(color: foreground),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 24, color: foreground),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: theme.type.labelSmall.copyWith(color: foreground),
                  ),
                ],
              ),
      ),
    );
  }
}

/// rail 项的交互面（抽成公开类，单测可以直接命中）。
class M3ENavRailItemSurface extends StatelessWidget {
  const M3ENavRailItemSurface({
    super.key,
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(M3EShape.lg),
            child: ColoredBox(color: Colors.transparent, child: child),
          ),
        ),
      ),
    );
  }
}
