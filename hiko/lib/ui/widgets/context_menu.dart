import 'dart:ui';
import 'package:flutter/material.dart';

/// 桌面与移动端通用的轻量、柔和圆角右键/长按上下文菜单项
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

/// 弹出精致、圆角、柔和微缩动画的右键菜单
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 菜单尺寸与边距计算
    const menuWidth = 176.0;
    const padding = 12.0;
    final estimatedHeight = items.length * 36.0 + 12.0;

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

    final bgColor = isDark
        ? const Color(0xE6262830) // 半透深灰
        : const Color(0xF5FAF9F7); // 半透暖米白
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.12);

    return Stack(
      children: [
        // 外部点击遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.translucent,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: menuWidth,
                      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor, width: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < items.length; i++) ...[
                            _HikoMenuItemWidget<T>(
                              item: items[i],
                              onTap: () => Navigator.of(context).pop(items[i].value),
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
                                  color: borderColor,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final destructiveColor = isDark
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFD34C44);
    final normalColor = isDark
        ? const Color(0xFFE4E4E8)
        : const Color(0xFF2C2D30);

    final textColor = widget.item.isDestructive ? destructiveColor : normalColor;

    final hoverBg = widget.item.isDestructive
        ? (isDark
            ? const Color(0x33FF6B6B)
            : const Color(0x1AD34C44))
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (widget.item.icon != null) ...[
                Icon(
                  widget.item.icon,
                  size: 14,
                  color: textColor.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
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
    );
  }
}
