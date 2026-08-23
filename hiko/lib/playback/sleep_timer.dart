import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// 睡眠定时模式:关闭 / 倒计时(15/30/60 分钟) / 播完当前曲停
enum SleepTimerMode { off, timed, endOfTrack }

/// 睡眠定时状态(仅内存,不跨会话持久化)
class SleepTimerState {
  final SleepTimerMode mode;
  final DateTime? deadline; // timed 模式:淡出完成并停止的时刻

  const SleepTimerState({this.mode = SleepTimerMode.off, this.deadline});
}

/// 睡眠定时纯逻辑:倒计时 / 淡出曲线 / 曲终拦截判定。
/// 全部为无 IO、无播放器依赖的纯函数,时间由 [clock] 读取(fake_async 可注入)。
class SleepTimerLogic {
  /// 倒计时到期前的淡出窗口:窗口内线性降 0
  static const fadeWindow = Duration(seconds: 10);

  static SleepTimerState startTimed(int minutes) => SleepTimerState(
        mode: SleepTimerMode.timed,
        deadline: clock.now().add(Duration(minutes: minutes)),
      );

  static const SleepTimerState endOfTrack =
      SleepTimerState(mode: SleepTimerMode.endOfTrack);

  /// 剩余时间(off / endOfTrack 返回 zero,由调用方区分展示)
  static Duration remaining(SleepTimerState s) =>
      s.deadline?.difference(clock.now()) ?? Duration.zero;

  static bool expired(SleepTimerState s) =>
      s.mode == SleepTimerMode.timed &&
      (s.deadline?.isBefore(clock.now()) ?? false);

  /// 淡出系数:窗口外 1.0;窗口内线性 1→0;到点 0
  static double fadeFactor(SleepTimerState s) {
    if (s.mode != SleepTimerMode.timed) return 1.0;
    final r = remaining(s);
    if (r <= Duration.zero) return 0.0;
    if (r >= fadeWindow) return 1.0;
    return r.inMilliseconds / fadeWindow.inMilliseconds;
  }

  /// 切歌拦截:播完当前曲停,或倒计时已到点 → 停止而非切下一首。
  /// 在 PlaybackController 切歌路径调用,保证下一首绝不起播。
  static bool shouldBlockTrackSwitch(SleepTimerState s) =>
      s.mode == SleepTimerMode.endOfTrack || expired(s);
}

/// 计时引擎:倒计时期间周期回调(剩余时间 + 淡出系数),到点回调 onExpired。
/// 不持有播放器,由宿主(PlaybackController)接线;Timer 驱动可在 fake_async 中 elapse 测试。
class SleepTimerEngine {
  SleepTimerEngine({this.onTick, this.onExpired});

  /// 回调允许宿主接线/更换(宿主为单一 PlaybackController,无共享)
  void Function(Duration remaining, double fadeFactor)? onTick;
  VoidCallback? onExpired;

  SleepTimerState state = const SleepTimerState();
  Timer? _ticker;

  static const tickInterval = Duration(milliseconds: 500);

  void startTimed(int minutes) {
    _ticker?.cancel();
    state = SleepTimerLogic.startTimed(minutes);
    _ticker = Timer.periodic(tickInterval, (_) => _tick());
    _tick();
  }

  void startEndOfTrack() {
    _ticker?.cancel();
    _ticker = null;
    state = SleepTimerLogic.endOfTrack;
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    state = const SleepTimerState();
  }

  void _tick() {
    if (SleepTimerLogic.expired(state)) {
      cancel();
      onExpired?.call();
      return;
    }
    onTick?.call(SleepTimerLogic.remaining(state), SleepTimerLogic.fadeFactor(state));
  }

  /// 引擎仅由 PlaybackController 持有并随其 dispose,不再额外暴露 dispose 钩子
  void dispose() => cancel();
}
