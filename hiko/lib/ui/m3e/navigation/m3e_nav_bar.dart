import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/m3e_theme.dart';
import '../tokens/shape_tokens.dart';
import 'm3e_nav_badge.dart';
import 'm3e_navigation_destination.dart';

/// M3E 导航栏（compact 形态，贴屏幕底部）。
///
/// 规范：容器 80dp（含手势区由外层 SafeArea 处理）、项高 64dp、
/// 选中指示器 64×32 全圆、图标 24dp、标签 labelMedium。
///
/// **最多 5 个目的地**（M3 的导航栏上限）。超过的由调用方折叠成「更多」，
/// 本组件不做溢出判断 —— 谁更懂产品语义，谁决定折哪几个。
class M3ENavBar extends StatelessWidget {
  const M3ENavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<M3ENavigationDestination> destinations;

  /// 选中项下标；-1 表示「没有一项选中」（例如当前是分类视图）。
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// 内容高度（不含系统手势区）
  static const double contentHeight = 64;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    return Semantics(
      container: true,
      child: Container(
        height: contentHeight + MediaQuery.paddingOf(context).bottom,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        color: colors.surfaceContainer,
        child: Row(
          children: <Widget>[
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _NavBarItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onTap: destinations[i].enabled
                      ? () => onSelected(i)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
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

    return Semantics(
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: theme.motion.stateLayerDuration,
              curve: Curves.easeOut,
              width: 64,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? colors.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(M3EShape.full),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 24,
                    color: foreground,
                  ),
                  if (destination.badge != null && destination.badge! > 0)
                    Positioned(
                      right: 6,
                      top: 2,
                      child: NavBadge(count: destination.badge!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.type.labelMedium.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// 计算「可见目的地 + 更多」的折叠方案。
///
/// 规则（1.99.27 裁决，见 plan-hiko-m3e-redesign.md §8.1）：
/// 最多 5 格。调用方给出必须常驻的格数（例如「正在播放」），
/// 剩余位置留给导航项，放不下的折进「更多」。
({List<M3ENavigationDestination> visible, List<M3ENavigationDestination> overflow})
    foldDestinations(
  List<M3ENavigationDestination> all, {
  int reservedSlots = 0,
  int maxSlots = 5,
}) {
  final capacity = math.max(1, maxSlots - reservedSlots - 1); // -1 给「更多」
  if (all.length <= capacity) {
    return (visible: all, overflow: const <M3ENavigationDestination>[]);
  }
  return (
    visible: all.take(capacity).toList(growable: false),
    overflow: all.skip(capacity).toList(growable: false),
  );
}
