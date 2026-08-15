import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 桌面置顶悬浮歌词状态
class DesktopLyricsStatus {
  final bool isShowing;
  final bool isLocked;

  const DesktopLyricsStatus({
    this.isShowing = false,
    this.isLocked = false,
  });

  DesktopLyricsStatus copyWith({
    bool? isShowing,
    bool? isLocked,
  }) {
    return DesktopLyricsStatus(
      isShowing: isShowing ?? this.isShowing,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

/// 桌面置顶悬浮歌词原生服务（macOS NSPanel）
class DesktopLyricsNotifier extends StateNotifier<DesktopLyricsStatus> {
  static const _channel = MethodChannel('top.voicehub.hiko/desktop_lyrics');

  DesktopLyricsNotifier() : super(const DesktopLyricsStatus()) {
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onVisibilityChanged':
        final visible = call.arguments as bool? ?? false;
        state = state.copyWith(isShowing: visible);
        break;
      case 'onLockChanged':
        final locked = call.arguments as bool? ?? false;
        state = state.copyWith(isLocked: locked);
        break;
    }
  }

  bool get isShowing => state.isShowing;
  bool get isLocked => state.isLocked;

  /// 显示桌面置顶悬浮窗
  Future<void> show() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('showHUD');
      // 重新开启默认自动解锁
      state = state.copyWith(isShowing: true, isLocked: false);
    } catch (e) {
      debugPrint('[DesktopLyricsService] show error: $e');
    }
  }

  /// 隐藏桌面置顶悬浮窗
  Future<void> hide() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('hideHUD');
      state = state.copyWith(isShowing: false);
    } catch (e) {
      debugPrint('[DesktopLyricsService] hide error: $e');
    }
  }

  /// 切换显示/隐藏
  Future<bool> toggle() async {
    if (state.isShowing) {
      await hide();
      return false;
    } else {
      await show();
      return true;
    }
  }

  /// 更新悬浮窗显示的台词文本与角色
  Future<void> updateLyrics({
    required String currentLine,
    String? speaker,
    String? translation,
  }) async {
    if (!Platform.isMacOS || !state.isShowing) return;
    try {
      await _channel.invokeMethod('updateLyrics', {
        'currentLine': currentLine,
        'speaker': speaker,
        'translation': translation,
      });
    } catch (e) {
      debugPrint('[DesktopLyricsService] updateLyrics error: $e');
    }
  }

  /// 锁定悬浮窗（开启/关闭鼠标穿透）
  Future<void> setLocked(bool locked) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setLocked', locked);
      state = state.copyWith(isLocked: locked);
    } catch (e) {
      debugPrint('[DesktopLyricsService] setLocked error: $e');
    }
  }
}

final desktopLyricsProvider =
    StateNotifierProvider<DesktopLyricsNotifier, DesktopLyricsStatus>((ref) {
  return DesktopLyricsNotifier();
});
