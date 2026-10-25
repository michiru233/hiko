import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E 列表项。
///
/// 行高按 M3 规范：单行 56、双行 72、三行 88（三行本版未开放，等用到再加）。
/// 圆角是「静息 4、选中 16」—— 这正是 M3E 的列表处理：默认贴在一起像一张连续面板，
/// 选中/按压时才把那一行「拎出来」变成独立圆角块。
class M3EListItem extends StatelessWidget {
  const M3EListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.selectedColor,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 选中态：底色 `secondaryContainer` + 圆角 16 + 标题 emphasized
  final bool selected;

  final bool enabled;

  /// 覆盖选中底色（例如「正在播放」用 primaryContainer）。
  final Color? selectedColor;

  double get _height => subtitle == null ? 56 : 72;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;

    final foreground =
        enabled ? colors.onSurface : colors.onSurface.withValues(alpha: 0.38);
    final subtitleColor = enabled
        ? colors.onSurfaceVariant
        : colors.onSurface.withValues(alpha: 0.38);

    final radius = BorderRadius.circular(selected ? M3EShape.lg : M3EShape.xs);
    final background = selected
        ? (selectedColor ?? colors.secondaryContainer)
        : Colors.transparent;

    final body = AnimatedContainer(
      duration: theme.motion.stateLayerDuration,
      curve: Curves.easeOut,
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: background, borderRadius: radius),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            IconTheme.merge(
              data: IconThemeData(
                size: 24,
                color: selected ? colors.onSecondaryContainer : foreground,
              ),
              child: leading!,
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (selected
                          ? theme.type.bodyLargeEmphasized
                          : theme.type.bodyLarge)
                      .copyWith(color: foreground),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.type.bodyMedium.copyWith(color: subtitleColor),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 16),
            IconTheme.merge(
              data: IconThemeData(
                size: 24,
                color: selected ? colors.onSecondaryContainer : subtitleColor,
              ),
              child: trailing!,
            ),
          ],
        ],
      ),
    );

    if (!enabled || (onTap == null && onLongPress == null)) {
      return body;
    }
    return M3EPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: radius,
      pressScale: 0.99,
      semanticLabel: title,
      child: body,
    );
  }
}

/// M3E 列表容器。
///
/// 只负责排布与间距，不画底 —— 底色由外层（sheet / card / 页面）决定，
/// 否则会出现「列表自带一层 surfaceContainer，套在卡片里再叠一层」的双底问题。
class M3EList extends StatelessWidget {
  const M3EList({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.gap = 0,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// 项间距。M3E 的「表达性列表」用 12dp 把每行拆成独立块；
  /// 密集的曲目表用 0（连续行），由调用方按内容密度选。
  final double gap;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && gap > 0) items.add(SizedBox(height: gap));
      items.add(children[i]);
    }
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }
}
