import 'package:flutter/material.dart';

import '../m3e/m3e.dart';

/// 桌面与移动端通用的轻量右键/长按上下文菜单项
class HikoContextMenuItem<T> {
  const HikoContextMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.isDestructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool isDestructive;
}

/// 弹出圆角、微缩动画的右键菜单（1.99.30 M3E 化，plan §8.8：角 4、项 48dp、
/// 分组分隔线 outlineVariant；材质 surfaceContainerHigh + 海拔 3，不再有玻璃模糊）
Future<T?> showHikoContextMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<HikoContextMenuItem<T>> items,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _HikoContextMenuRoute<T>(
      position: position,
      items: items,
    ),
  );
}

class _HikoContextMenuRoute<T> extends PopupRoute<T> {
  _HikoContextMenuRoute({
    required this.position,
    required this.items,
  });

  final Offset position;
  final List<HikoContextMenuItem<T>> items;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _HikoContextMenuOverlay<T>(
      position: position,
      items: items,
      animation: animation,
    );
  }
}

class _HikoContextMenuOverlay<T> extends StatelessWidget {
  const _HikoContextMenuOverlay({
    required this.position,
    required this.items,
    required this.animation,
  });

  final Offset position;
  final List<HikoContextMenuItem<T>> items;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final colors = M3ETheme.of(context).colors;

    // 菜单尺寸与边距计算（项 48dp，plan §8.8）
    const menuWidth = 190.0;
    const padding = 12.0;
    final estimatedHeight = items.length * 48.0 + 12.0;

    double left = position.dx;
    double top = position.dy;

    // 靠边自适应避让
    if (left + menuWidth > screenSize.width - padding) {
      left = screenSize.width - menuWidth - padding;
    }
    if (left < padding) left = padding;

    if (top + estimatedHeight > screenSize.height - padding) {
      top = position.dy - estimatedHeight;
    }
    if (top < padding) top = padding;

    // 曲线与缩放动画：从微缩 0.94 平滑放大并淡入
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        // 外部点击遮罩（非按钮：NoSplash 防全屏水波纹，点击即关菜单已是反馈）
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            type: MaterialType.transparency,
            child: FadeTransition(
              opacity: curvedAnimation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(curvedAnimation),
                alignment: Alignment(
                  position.dx > screenSize.width / 2 ? 0.8 : -0.8,
                  position.dy > screenSize.height / 2 ? 0.8 : -0.8,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(M3EShape.xs),
                    boxShadow: M3EElevation.shadow(
                      M3EElevation.level3,
                      colors.shadow,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(M3EShape.xs),
                    child: SizedBox(
                      width: menuWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int i = 0; i < items.length; i++) ...[
                              _HikoMenuItemWidget<T>(
                                item: items[i],
                                onTap: () =>
                                    Navigator.of(context).pop(items[i].value),
                              ),
                              if (i < items.length - 1 &&
                                  items[i + 1].isDestructive &&
                                  !items[i].isDestructive)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  child: Divider(
                                    height: 1,
                                    thickness: 0.6,
                                    color: colors.outlineVariant,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HikoMenuItemWidget<T> extends StatefulWidget {
  const _HikoMenuItemWidget({
    required this.item,
    required this.onTap,
  });

  final HikoContextMenuItem<T> item;
  final VoidCallback onTap;

  @override
  State<_HikoMenuItemWidget<T>> createState() => _HikoMenuItemWidgetState<T>();
}

class _HikoMenuItemWidgetState<T> extends State<_HikoMenuItemWidget<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;

    final textColor = widget.item.isDestructive
        ? colors.error
        : colors.onSurface;

    final hoverBg = widget.item.isDestructive
        ? colors.error.withValues(alpha: 0.10)
        : colors.onSurface.withValues(alpha: 0.06);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(M3EShape.xs),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hovered ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(M3EShape.xs),
            ),
            child: Row(
              children: [
                if (widget.item.icon != null) ...[
                  Icon(
                    widget.item.icon,
                    size: 18,
                    color: textColor.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      decoration: TextDecoration.none,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
