import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 桌面置顶悬浮歌词原生服务（macOS NSPanel）
class DesktopLyricsService {
  static const _channel = MethodChannel('top.voicehub.hiko/desktop_lyrics');
  bool _isShowing = false;
  bool _isLocked = false;

  bool get isShowing => _isShowing;
  bool get isLocked => _isLocked;

  /// 显示桌面置顶悬浮窗
  Future<void> show() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('showHUD');
      _isShowing = true;
    } catch (e) {
      debugPrint('[DesktopLyricsService] show error: $e');
    }
  }

  /// 隐藏桌面置顶悬浮窗
  Future<void> hide() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('hideHUD');
      _isShowing = false;
    } catch (e) {
      debugPrint('[DesktopLyricsService] hide error: $e');
    }
  }

  /// 切换显示/隐藏
  Future<bool> toggle() async {
    if (_isShowing) {
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
    if (!Platform.isMacOS) return;
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

  /// 锁定悬浮窗（开启鼠标穿透，点击直接操作下层窗口）
  Future<void> setLocked(bool locked) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setLocked', locked);
      _isLocked = locked;
    } catch (e) {
      debugPrint('[DesktopLyricsService] setLocked error: $e');
    }
  }
}

final desktopLyricsServiceProvider = Provider<DesktopLyricsService>((ref) {
  return DesktopLyricsService();
});
