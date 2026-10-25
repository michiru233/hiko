import 'package:flutter/material.dart';

import '../tokens/elevation_tokens.dart';
import '../theme/m3e_theme.dart';

/// M3E 顶栏（plan §8.1）：compact 用 [M3EAppBar.small]（64dp），
/// expanded 用 [M3EAppBar.large]（152dp 大标题）。
///
/// 折叠行为说明（与计划的偏差，1.99.31）：large 的「滚动折叠到 64dp」在移动端
/// 由 1.99.9 的自定义 sliver 头承担（含 1.99.25 的回归锁），本组件只提供
/// **静态两档**；桌面顶栏不随内容滚动，接 [M3EAppBar.small]。
/// 底色：`surface`；在滚动容器内使用时传 `scrolled: true` 换 `surfaceContainer`。
///
/// [topInset] 给「作为 `Scaffold.appBar` 使用、且页面没有外层 SafeArea」的场景：
/// M3EAppBar 自身不读系统安全区，传 `MediaQuery.paddingOf(context).top`
/// 即可让内容落到状态栏下方；桌面首页/设置页已经在外层让出窗口 inset，传 0。
class M3EAppBar extends StatelessWidget implements PreferredSizeWidget {
  const M3EAppBar.small({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.scrolled = false,
    this.backgroundColor,
    this.padding,
    this.topInset = 0,
  }) : _height = 64,
       _titleMaxLines = 1;

  const M3EAppBar.large({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.scrolled = false,
    this.backgroundColor,
    this.padding,
    this.topInset = 0,
  }) : _height = 152,
       _titleMaxLines = 2;

  /// 中轴内容（面包屑 / 大标题）。
  final Widget title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool scrolled;

  /// 覆盖底色。压在封面/渐变上的全屏页传 `Colors.transparent`，
  /// 此时不画 `scrolled` 的 level1 投影。
  final Color? backgroundColor;

  /// 覆盖左右内边距（默认 24）。浮层顶栏常传 8~12，让图标更贴边。
  final EdgeInsetsGeometry? padding;

  /// 系统状态栏安全区（像素）。见类注释。
  final double topInset;

  final double _height;
  final int _titleMaxLines;

  @override
  Size get preferredSize => Size.fromHeight(_height + topInset);

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final overridden = backgroundColor != null;
    return Padding(
      padding: EdgeInsets.only(top: topInset),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          color:
              backgroundColor ??
              (scrolled ? colors.surfaceContainer : colors.surface),
          boxShadow: !overridden && scrolled
              ? M3EElevation.shadow(M3EElevation.level1, colors.shadow)
              : null,
        ),
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 24),
        alignment: _height > 100 ? Alignment.bottomLeft : Alignment.center,
        child: Row(
          children: [
            ?leading,
            if (leading != null) const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle.merge(
                maxLines: _titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: _height > 100
                    ? M3ETheme.of(context).type.headlineLarge
                    : M3ETheme.of(context).type.titleMedium,
                child: title,
              ),
            ),
            ...?actions,
          ],
        ),
      ),
    );
  }
}
