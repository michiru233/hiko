import 'package:flutter/material.dart';

import '../theme/m3e_theme.dart';
import '../tokens/shape_tokens.dart';
import 'm3e_nav_badge.dart';
import 'm3e_navigation_destination.dart';

/// M3E 导航抽屉（移动端形态，1.99.65 / 1.99.66 收窄）。
///
/// 从屏幕左缘往右拖拉出、日常隐藏 —— 安卓的 drawer 惯例。拖拽由
/// `Scaffold.drawerEnableOpenDragGesture` + `drawerEdgeDragWidth` 提供
/// （见 [M3ENavDrawer.edgeDragWidth]），本组件只负责外观与内容。
///
/// 与 [M3ENavRail]（桌面侧栏）同源：同一份 [M3ENavigationDestination]，差别只在
/// 容器 —— 抽屉 [width]（216dp，够放「四字标签 + 三位数徽标」）、右缘 `xl` 圆角、
/// `surfaceContainerLow` 底（浮在内容之上，比 `surface` 的侧栏高一档材质），
/// 条目 48dp 通栏、选中铺 `secondaryContainer` 色块。
///
/// 1.99.66 的三处修正（用户实测反馈）：
/// 1. 宽度 308 → 216：只占 390dp 窄屏的 55%，右边留得下内容做对照；
/// 2. 头部不再被 `CrossAxisAlignment.stretch` 撑满 —— 头部是「谁传进来就多大」，
///    1.99.65 把 32dp 的 logo 拉成了 260dp 的大色块，问题就出在这里；
/// 3. 条目 56 → 48、内边距收紧，一屏能多放一项。
class M3ENavDrawer extends StatelessWidget {
  const M3ENavDrawer({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.header,
    this.hint,
    this.trailing,
    this.onTrailing,
  });

  /// 抽屉宽度：216dp。
  ///
  /// 最宽的一行是「四字标签 + `99+` 徽标」：抽屉外边距 8 + 条目内边距 12 + 图标
  /// 22 + 间隙 12 + 四字标签 ≈ 58@14sp + 间隙 6 + 徽标 ≈ 30 + 内边距 12 + 8 ≈
  /// 168dp，216 留了足够余量，同时右边能露出 174dp 的内容做对照。
  static const double width = 216;

  /// 左缘可拖宽度：48dp。
  ///
  /// `Scaffold` 默认 20dp，但安卓 10+ 把最外 ~24dp 划给了系统返回手势（应用抢不到
  /// 系统级手势），所以默认值等于「和系统抢同一条 20dp，多数时候抢输」。放宽到
  /// 48dp 后，从「边缘往里 24～48dp」起手都能稳定拉出；贴着最外面起手仍会走系统
  /// 返回，这一条只能靠顶部菜单按钮兜底。
  static const double edgeDragWidth = 48;

  final List<M3ENavigationDestination> destinations;

  /// 选中项下标；-1 表示没有选中项（例如当前是分类视图、或「正在播放」）。
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// 顶部品牌区。传什么都只占自身尺寸（不会被拉伸）。
  final Widget? header;

  /// 底部说明文案（「从屏幕左缘往右拖可随时拉出」这类）。
  final String? hint;

  /// 列表末尾的独立动作（1.99.66：移动端把「设置」放这里，替代原来的「更多」面板）。
  ///
  /// 与 [destinations] 分开是因为它不参与选中态、也不属于一级视图。
  final M3ENavigationDestination? trailing;

  final VoidCallback? onTrailing;

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
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                child: Align(alignment: Alignment.centerLeft, child: header),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
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
            if (trailing != null) ...<Widget>[
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _NavDrawerItem(
                  destination: trailing!,
                  selected: false,
                  onTap: onTrailing,
                ),
              ),
            ],
            if (hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 14, 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 22,
                      color: foreground,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: theme.type.labelLarge.copyWith(
                          color: foreground,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    if (destination.badge != null && destination.badge! > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
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
