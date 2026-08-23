import 'dart:async';

import 'package:flutter/material.dart';

/// 全局 toast（1.32）：插入根 Overlay（rootOverlay: true），永远浮于
/// showDialog / 底部弹层之上。旧实现走 SnackBar 通道，会被后插入的
/// 对话框 OverlayEntry 盖住——「点按钮弹的提示被对话框挡住」的根因。
/// 样式沿用旧 SnackBar 主题：深底白字、圆角 7、floating 边距；同一时刻只保留一条。
OverlayEntry? _activeToastEntry;
Timer? _activeToastTimer;

void showHikoToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 3200),
}) {
  _dismissActiveToast();

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      bottom: 96,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 180),
          builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
              style: const TextStyle(color: Colors.white, fontSize: 12),
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
