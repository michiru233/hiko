import 'dart:async';

import 'package:flutter/material.dart';

import '../m3e/m3e.dart';
import 'activity_overlay.dart';

/// toast 的默认停留时长 —— 这是「读得完」的时间，不是过渡动效，
/// 所以不进 `M3EMotion`。1.99.49 从默认参数里的裸数字提成具名常量：
/// 账本锁只放行**具名**时长，调用点随手写数字会红。
const Duration kToastLinger = Duration(milliseconds: 3200);

/// 全局 toast。应用运行时优先使用 MaterialApp 根通知层，测试或嵌入场景
/// 没有通知层时回退到根 Overlay；同一时刻只保留最新一条。
OverlayEntry? _activeToastEntry;
Timer? _activeToastTimer;

void showHikoToast(
  BuildContext context,
  String message, {
  Duration duration = kToastLinger,
}) {
  if (activityOverlayController.isAttached) {
    activityOverlayController.showToast(message, duration: duration);
    return;
  }

  _dismissActiveToast();

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      bottom: 96,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: M3ETheme.of(context)
                    .motion
                    .duration(M3ESpringType.effects, M3ESpringSpeed.normal),
                builder: (_, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                // 1.99.30 M3E：inverseSurface 反色面、角 4（plan §8.8 Snackbar）
                child: _M3EToastSurface(message: message),
              ),
          ),
        ),
      ),
    ),
  );
  _activeToastEntry = entry;
  Overlay.of(context, rootOverlay: true).insert(entry);
  _activeToastTimer = Timer(duration, () {
    try {
      entry.remove();
    } catch (_) {
      // Overlay 已随页面销毁：无事可做
    }
    if (identical(_activeToastEntry, entry)) _activeToastEntry = null;
  });
}

void _dismissActiveToast() {
  _activeToastTimer?.cancel();
  _activeToastTimer = null;
  final entry = _activeToastEntry;
  _activeToastEntry = null;
  if (entry != null) {
    try {
      entry.remove();
    } catch (_) {}
  }
}

/// toast 材质（1.99.30）：M3E 反色面，角 4；无祖先 M3E 主题时回退 Material 配色。
class _M3EToastSurface extends StatelessWidget {
  const _M3EToastSurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.maybeOf(context);
    final Color bg;
    final Color fg;
    if (m3e != null) {
      bg = m3e.colors.inverseSurface;
      fg = m3e.colors.onInverseSurface;
    } else {
      final scheme = Theme.of(context).colorScheme;
      bg = scheme.inverseSurface;
      fg = scheme.onInverseSurface;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: M3EShape.radius(M3EShape.xs),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: M3ETheme.of(context).type.bodySmall.copyWith(
          color: fg,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
