import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/motion_tokens.dart';
import '../../tokens/shape_tokens.dart';

/// M3E 的交互基座：hover / focus / press 状态层 + 弹簧按压。
///
/// 所有可点组件（卡片、按钮、列表项、导航项）都走这一层，保证：
/// 1. 三种输入状态（指针悬停、键盘聚焦、按压）都有**同一种**视觉反馈；
/// 2. 按压缩放只有一处实现，不会出现「卡片 0.97、按钮 0.96」这种不一致；
/// 3. 动效开关（完整/减弱/关闭）在这里统一短路，子组件不需要各自判断。
///
/// 状态层透明度按 M3 规范：hover 8%、focus 10%、press 10%。
/// 这是叠在内容**之上**的一层（不是背景色变化），所以深色浅色都成立。
class M3EPressable extends StatefulWidget {
  const M3EPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.enabled = true,
    this.pressScale = 0.97,
    this.borderRadius,
    this.stateLayerColor,
    this.semanticLabel,
    this.onHoverChanged,
  });

  final Widget child;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 桌面右键 / 触摸长按菜单的**位置**回调（`globalPosition`）。
  /// 直接给坐标而不是内部转局部坐标：调用方要拿它定位弹出菜单。
  final void Function(Offset globalPosition)? onSecondaryTapDown;

  final bool enabled;

  /// 按下时的缩放终点。列表类 0.97、大卡片 0.98、图标按钮 0.94 由调用方定。
  final double pressScale;

  /// 状态层的裁剪圆角，默认 16（内容面基准）。
  final BorderRadius? borderRadius;

  /// 状态层颜色，默认 `onSurface`（浅色下压暗、深色下提亮，方向永远正确）。
  final Color? stateLayerColor;

  final String? semanticLabel;

  /// 悬停状态回调（1.99.46）：少数行需要在 hover 时**换内容**而不是叠状态层，
  /// 例如歌词行的「时间点 / 播放小图标」。状态层照旧由本组件负责。
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<M3EPressable> createState() => _M3EPressableState();
}

class _M3EPressableState extends State<M3EPressable>
    with SingleTickerProviderStateMixin {
  /// 用一个无界控制器直接跑弹簧：值是缩放倍率（1.0 起），不是 0~1 的进度。
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  M3EMotion _motion = const M3EMotion();
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 动效档可能随设置变化，每次依赖变化重新取（不缓存到 initState）。
    _motion = M3ETheme.of(context).motion;
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _setPressed(bool down) {
    if (!_interactive || _pressed == down) return;
    setState(() => _pressed = down);
    _animateScale(down ? widget.pressScale : 1);
  }

  void _animateScale(double target) {
    // 关闭动效：直接到终态，连弹簧模拟都不创建（§7.4 第 3 条）。
    if (!_motion.enabled) {
      _scale.value = target;
      return;
    }
    if (_motion.level == M3EMotionLevel.reduced) {
      _scale.animateTo(
        target,
        duration: _motion.duration(M3ESpringType.spatial, M3ESpringSpeed.fast),
        curve: _motion.fallbackCurve,
      );
      return;
    }
    _scale.animateWith(
      SpringSimulation(
        _motion.spring(M3ESpringType.spatial, M3ESpringSpeed.fast),
        _scale.value,
        target,
        0,
      ),
    );
  }

  double get _overlayAlpha {
    if (!_interactive) return 0;
    if (_pressed) return 0.10;
    if (_focused) return 0.10;
    if (_hovered) return 0.08;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final overlay = (widget.stateLayerColor ?? colors.onSurface)
        .withValues(alpha: _overlayAlpha);
    final radius = widget.borderRadius ?? BorderRadius.circular(M3EShape.lg);

    return Semantics(
      button: widget.onTap != null,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      // 不用 FocusableActionDetector：它在 3.47 的测试环境里不派发
      // onShowHoverHighlight（实测探针 0 次触发），hover 状态层就没法写回归锁。
      // 这里的 MouseRegion + Focus 组合语义等价，且每一路都可测。
      child: MouseRegion(
        cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) {
          if (_interactive && !_hovered) {
            setState(() => _hovered = true);
            widget.onHoverChanged?.call(true);
          }
        },
        onExit: (_) {
          if (_hovered) {
            setState(() => _hovered = false);
            widget.onHoverChanged?.call(false);
          }
        },
        child: Focus(
          canRequestFocus: _interactive,
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          onKeyEvent: (node, event) {
            if (!_interactive) return KeyEventResult.ignored;
            final isActivateKey = event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space;
            if (!isActivateKey) return KeyEventResult.ignored;
            if (event is KeyDownEvent) {
              _setPressed(true);
              return KeyEventResult.handled;
            }
            if (event is KeyUpEvent) {
              _setPressed(false);
              widget.onTap?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _interactive ? (_) => _setPressed(true) : null,
            onTapUp: _interactive ? (_) => _setPressed(false) : null,
            onTapCancel: _interactive ? () => _setPressed(false) : null,
            onTap: _interactive ? widget.onTap : null,
            onLongPress: _interactive ? widget.onLongPress : null,
            onSecondaryTapDown: widget.onSecondaryTapDown == null
                ? null
                : (details) =>
                    widget.onSecondaryTapDown!(details.globalPosition),
            child: AnimatedBuilder(
              animation: _scale,
              builder: (context, child) =>
                  Transform.scale(scale: _scale.value, child: child),
              child: Stack(
                children: <Widget>[
                  widget.child,
                  // 状态层必须盖在内容之上、且不吃事件。
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: _motion.stateLayerDuration,
                        decoration: BoxDecoration(
                          color: overlay,
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
