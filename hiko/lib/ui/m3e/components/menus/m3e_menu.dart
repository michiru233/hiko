import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/elevation_tokens.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';

/// M3E 菜单（B1 第二件，1.99.40）。
///
/// 替掉仓库里并存的三种菜单：自绘 context menu、`PopupMenuButton`、裸
/// `MenuAnchor`。三者此前各有一套行高（38 / 42 / 48）、圆角（4 / 12）与字号
/// （12 / 13.5 / 14），同一「菜单」语义在三个面上长得不一样（审计 D-05 / C-09）。
///
/// 规格（plan-hiko-m3e-redesign §5）：
/// - 面板：`surfaceContainerHigh`、圆角 [M3EShape.xs]（4）、海拔
///   [M3EElevation.level3]、**去 surfaceTint**（层深靠色阶，不靠染色）；
/// - 行：48dp（双行 56）、`labelLarge`、左右 12dp、圆角 4、状态层走
///   [M3EPressable]（hover 8% / focus 10% / press 10%）；
/// - 高度：`min(400, 屏高 × 0.45)` —— 上限 400 是 1.99.5 的实测结论：
///   320 会把「全年龄」那一行永久切在折线下方。
///
/// **为什么不用 `MenuItemButton`**：它默认 `closeOnActivate = true`，点一下
/// 就关菜单；而分级筛选、防社死 / 外观切换这三个开关必须「点一下不关」，
/// 能让用户连着勾完。`MenuItemButton` 的 keep-open 只能靠子类覆写
/// `handleTap`，那还不如整个行自己画。
class M3EMenu extends StatelessWidget {
  const M3EMenu({
    super.key,
    required this.builder,
    required this.children,
    this.controller,
    this.alignmentOffset,
    this.minWidth = 200,
    this.maxWidth = 320,
    this.maxHeightCap = 400,
  });

  /// 触发器（chip / 工具条动作 / 图标钮）。拿到 [MenuController] 后自己决定
  /// 何时 `open()`；右键菜单还需要 `open(position:)` 定位。
  final MenuAnchorChildBuilder builder;

  final List<Widget> children;

  /// 外部控制器：需要程序化开关（右键菜单、键盘）时传入。
  final MenuController? controller;

  final Offset? alignmentOffset;

  final double minWidth;
  final double maxWidth;

  /// 高度上限的绝对封顶，实际取 `min(它, 屏高 × 0.45)`。
  final double maxHeightCap;

  /// `min(cap, 屏高 × 0.45)`：小屏按比例缩，大屏封顶，永不顶到天花板。
  static double maxHeightFor(BuildContext context, {double cap = 400}) {
    final scaled = MediaQuery.sizeOf(context).height * 0.45;
    return scaled < cap ? scaled : cap;
  }

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final maxHeight = maxHeightFor(context, cap: maxHeightCap);

    return MenuAnchor(
      controller: controller,
      alignmentOffset: alignmentOffset,
      // 圆角靠 Material 裁：不裁的话首尾行的状态层会溢出到圆角外。
      clipBehavior: Clip.antiAlias,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        // M3 默认会用 primary 给面板染色，这里显式关掉（层深靠色阶）。
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(colors.shadow),
        elevation: const WidgetStatePropertyAll(M3EElevation.level3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(M3EShape.xs),
          ),
        ),
        // 纵向 8dp：首尾行不贴边（M3 菜单规范）。
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
        minimumSize: WidgetStatePropertyAll(Size(minWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(maxWidth, maxHeight)),
      ),
      menuChildren: children,
      builder: builder,
    );
  }
}

/// 菜单里的**动作行**：点一下执行，然后关菜单。
///
/// [selected] 只画右侧勾、不铺底色（1.99.40 裁决）：8 行以上的密排菜单里
/// 整行 `secondaryContainer` 会在滚动时变成一块跳动的色带。
/// [destructive] 用 `error` 色（删除歌单这类不可撤销动作）。
class M3EMenuAction extends StatelessWidget {
  const M3EMenuAction({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
    this.subtitle,
    this.selected = false,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;

  /// 第二行说明（播放模式这类需要解释的行）。给了它就长到 56dp。
  final String? subtitle;

  final bool selected;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final active = enabled && onPressed != null;

    final foreground = !active
        ? colors.onSurface.withValues(alpha: 0.38)
        : destructive
        ? colors.error
        : colors.onSurface;
    final secondary = !active
        ? colors.onSurface.withValues(alpha: 0.38)
        : destructive
        ? colors.error
        : colors.onSurfaceVariant;

    final content = Row(
      children: <Widget>[
        if (leadingIcon != null) ...<Widget>[
          Icon(leadingIcon, size: 20, color: foreground),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.type.labelLarge.copyWith(color: foreground),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.type.bodySmall.copyWith(color: secondary),
                ),
              ],
            ],
          ),
        ),
        if (selected) ...<Widget>[
          const SizedBox(width: 12),
          Icon(
            Icons.check_rounded,
            size: 18,
            color: active
                ? colors.primary
                : colors.onSurface.withValues(alpha: 0.38),
          ),
        ],
      ],
    );

    return _M3EMenuRow(
      onTap: active ? onPressed : null,
      enabled: enabled,
      minHeight: subtitle == null ? 48 : 56,
      semanticLabel: label,
      child: content,
    );
  }
}

/// 菜单里的**开关行**：点一下切换，**不关菜单**。
///
/// 受控 + 乐观更新：点击立刻翻本地值（不等 provider/设置回写），
/// [didUpdateWidget] 再把外部 `value` 同步回来 —— 这样「用快捷键改了状态、
/// 菜单还开着」也能刷新，不会显示成旧值。
class M3EMenuToggle extends StatefulWidget {
  const M3EMenuToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.leadingIcon,
    this.statusLabel,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? leadingIcon;

  /// 右侧次要文字（「已开启」「深色」）。给了就在勾前面显示。
  final String? statusLabel;

  final bool enabled;

  @override
  State<M3EMenuToggle> createState() => _M3EMenuToggleState();
}

class _M3EMenuToggleState extends State<M3EMenuToggle> {
  late bool _value = widget.value;

  @override
  void didUpdateWidget(covariant M3EMenuToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      setState(() => _value = widget.value);
    }
  }

  void _toggle() {
    if (!widget.enabled) return;
    setState(() => _value = !_value);
    widget.onChanged(_value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final on = _value;

    final foreground = !widget.enabled
        ? colors.onSurface.withValues(alpha: 0.38)
        : colors.onSurface;
    final statusColor = !widget.enabled
        ? colors.onSurface.withValues(alpha: 0.38)
        : on
        ? colors.primary
        : colors.onSurfaceVariant;

    return Semantics(
      // 开关语义：读屏能报出「已开启 / 已关闭」，而不是只有文字。
      toggled: on,
      child: _M3EMenuRow(
        onTap: widget.enabled ? _toggle : null,
        enabled: widget.enabled,
        closeOnTap: false,
        semanticLabel: widget.statusLabel == null
            ? widget.label
            : '${widget.label}，${widget.statusLabel}',
        child: Row(
          children: <Widget>[
            if (widget.leadingIcon != null) ...<Widget>[
              Icon(
                widget.leadingIcon,
                size: 20,
                color: on ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.type.labelLarge.copyWith(color: foreground),
              ),
            ),
            if (widget.statusLabel != null) ...<Widget>[
              const SizedBox(width: 12),
              Text(
                widget.statusLabel!,
                maxLines: 1,
                style: theme.type.labelMedium.copyWith(color: statusColor),
              ),
            ],
            if (on) ...<Widget>[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 18, color: colors.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 菜单里的**分区标题**（不可点）。原来的「禁用 `PopupMenuItem`」就是它 ——
/// 禁用条目会被读成「已禁用」并按 38% 灰压淡，而标题并不是一个坏掉的按钮。
class M3EMenuHeader extends StatelessWidget {
  const M3EMenuHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.type.labelMedium.copyWith(
          color: theme.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 菜单里的分隔线：1dp `outlineVariant`，上下各 8dp。
///
/// 不用 Material `Divider`：它读 `dividerColor`（旧主题桥的色），
/// 在对比度档下不会跟着 M3E 走。
class M3EMenuDivider extends StatelessWidget {
  const M3EMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 1,
              child: ColoredBox(color: colors.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 菜单里的**自定义行**：内容自己给（例如内嵌滑杆），外壳仍是 48dp 行 +
/// 状态层。音量菜单将来换 `M3ESlider` 时走这里。
class M3EMenuCustom extends StatelessWidget {
  const M3EMenuCustom({
    super.key,
    required this.child,
    this.onTap,
    this.minHeight = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _M3EMenuRow(
      onTap: onTap,
      minHeight: minHeight,
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

/// 所有行的公共外壳：最小高度 + 左右 12dp + 状态层 + 「点了就关」。
class _M3EMenuRow extends StatelessWidget {
  const _M3EMenuRow({
    required this.child,
    this.onTap,
    this.enabled = true,
    this.closeOnTap = true,
    this.minHeight = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final bool closeOnTap;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  void _handleTap(BuildContext context) {
    // 先关再执行：回调里常常会 push 一条路由 / 弹对话框，
    // 菜单压在下面既挡视觉又会跟着一起被 pop 掉。
    if (closeOnTap) MenuController.maybeOf(context)?.close();
    onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final body = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(padding: padding, child: child),
    );

    return M3EPressable(
      onTap: enabled && onTap != null ? () => _handleTap(context) : null,
      enabled: enabled,
      borderRadius: BorderRadius.circular(M3EShape.xs),
      pressScale: 0.99,
      semanticLabel: semanticLabel,
      child: body,
    );
  }
}
