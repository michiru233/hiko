import 'package:clock/clock.dart';

/// 音频输出自愈判定（纯逻辑，可单测，不 import 播放器）。
///
/// 根因背景：蓝牙输出设备断连/切换时 libmpv 的 coreaudio 输出死亡，
/// mpv 继续播放但声音进死设备。输入=mpv 日志事件与设备列表变化，
/// 输出=是否此刻执行修复动作（setProperty('audio-device','auto')）。
class AudioHealDecider {
  AudioHealDecider({
    this.debounce = const Duration(seconds: 2),
    this.window = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? clock.now;

  /// 防抖：自愈后 2 秒内的同波重复事件直接吞掉。
  final Duration debounce;

  /// 限流：自愈后 10 秒窗口内不重复触发，避免反复重接打断正常播放。
  final Duration window;

  final DateTime Function() _now;
  DateTime? _lastHealAt;

  static final RegExp _deadOutputPattern =
      RegExp(r'coreaudio|audio device|ao\b', caseSensitive: false);

  /// mpv 日志文本是否指向音频输出设备问题（纯函数）。
  static bool logSuggestsDeadOutput(String message) =>
      _deadOutputPattern.hasMatch(message);

  /// 是否应执行自愈：仅播放中判定；日志命中或设备列表变化触发。
  bool shouldHeal({
    required bool playing,
    required bool logHit,
    required bool deviceListChanged,
  }) {
    if (!playing) return false;
    if (!logHit && !deviceListChanged) return false;
    final now = _now();
    final last = _lastHealAt;
    if (last != null) {
      final since = now.difference(last);
      if (since < debounce) return false; // 防抖
      if (since < window) return false; // 限流
    }
    _lastHealAt = now;
    return true;
  }

  /// 手动触发（设置页按钮）绕过限流。
  void force() => _lastHealAt = null;

  void reset() => _lastHealAt = null;
}
