import 'dart:async';

import 'package:flutter/material.dart';

import 'activity_overlay.dart';

/// 全局 toast。应用运行时优先使用 MaterialApp 根通知层，测试或嵌入场景
/// 没有通知层时回退到根 Overlay；同一时刻只保留最新一条。
OverlayEntry? _activeToastEntry;
Timer? _activeToastTimer;

void showHikoToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 3200),
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
              duration: const Duration(milliseconds: 180),
              builder: (_, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF292735),
                  borderRadius: BorderRadius.circular(7),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                      decoration: TextDecoration.none,
                  ),
                ),
              ),
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
