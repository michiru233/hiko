import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/library_provider.dart';
import '../data/settings_store.dart';
import '../models/album.dart';
import '../models/track.dart';
import 'gain_chain.dart';
import 'hiko_media_kit_player.dart';
import 'playback_rules.dart';
import 'sleep_timer.dart';

/// 播放器状态（UI 直接消费）
class PlaybackState {
  final Album? album; // 当前专辑
  final List<Track> queue; // 当前队列（= 专辑 tracks）
  final int queueIndex;
  final bool playing;
  final double position; // 秒（当前曲）
  final double duration; // 秒（当前曲）
  final PlaybackMode mode;
  final SleepTimerMode sleepMode; // 睡眠定时模式（仅内存，不持久化）
  final Duration? sleepRemaining; // 倒计时剩余（timed 模式）

  const PlaybackState({
    this.album,
    this.queue = const [],
    this.queueIndex = -1,
    this.playing = false,
    this.position = 0,
    this.duration = 0,
    this.mode = PlaybackMode.list,
    this.sleepMode = SleepTimerMode.off,
    this.sleepRemaining,
  });

  Track? get currentTrack =>
      (queueIndex >= 0 && queueIndex < queue.length) ? queue[queueIndex] : null;

  PlaybackState copyWith({
    Album? album,
    List<Track>? queue,
    int? queueIndex,
    bool? playing,
    double? position,
    double? duration,
    PlaybackMode? mode,
    SleepTimerMode? sleepMode,
    Duration? sleepRemaining,
  }) =>
      PlaybackState(
        album: album ?? this.album,
        queue: queue ?? this.queue,
        queueIndex: queueIndex ?? this.queueIndex,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        mode: mode ?? this.mode,
        sleepMode: sleepMode ?? this.sleepMode,
        sleepRemaining: sleepRemaining ?? this.sleepRemaining,
      );
}

/// 播放控制器：just_audio 封装 + 队列/播放模式/进度持久化。
/// 纯逻辑可单测部分在 [QueueRules]；本类只做 just_audio 接线。
class PlaybackController extends StateNotifier<PlaybackState> {
  PlaybackController(this._ref) : super(const PlaybackState()) {
    _player.processingStateStream.listen(_onProcessingStateChanged);
    _player.playerStateStream.listen((ps) {
      if (ps.playing != state.playing) {
        state = state.copyWith(playing: ps.playing);
      }
      if (ps.processingState == ProcessingState.ready && _pendingSeek != null) {
        // ExoPlayer 切轨后 seek 需要等 ready（对应旧版 pending 缓存策略）
        final seek = _pendingSeek!;
        _pendingSeek = null;
        _player.seek(Duration(milliseconds: (seek * 1000).round()));
      }
    });
    _player.positionStream.listen((pos) {
      state = state.copyWith(position: pos.inMilliseconds / 1000.0);
      _maybePersistProgress();
    });
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d.inMilliseconds / 1000.0);
    });
    unawaited(_gainSelfTest());
    // 生命周期兜底：切后台/失活时把断点写盘（退出 app 前最后一次机会）
    _lifecycle = AppLifecycleListener(
      onInactive: () => _persistProgress(),
      onHide: () => _persistProgress(),
    );
  }

  late final AppLifecycleListener _lifecycle;
  /// 发布验收自检（仅 --dart-define=HIKO_GAIN_SELFTEST=1 时运行，默认不生效）：
  /// 先加载 0.2s 静音激活引擎（just_audio 惰性创建 native player），
  /// 再依次应用 2.0x / 1.0x 增益，用 [gain] 日志验证 af 链读回与常规音量隔离。
  Future<void> _gainSelfTest() async {
    if (const String.fromEnvironment('HIKO_GAIN_SELFTEST') != '1') return;
    await Future<void>.delayed(const Duration(seconds: 6));
    try {
      final wav =
          File('${Directory.systemTemp.path}/hiko_gain_selftest.wav');
      await wav.writeAsBytes(_silentWav());
      await _player.setUrl(wav.uri.toString()).timeout(
            const Duration(seconds: 8),
          );
      debugPrint('[gain-selftest] 引擎已激活，应用常规音量 + 2.0x 增益');
      await syncVolume(gain: 2.0);
      await Future<void>.delayed(const Duration(seconds: 2));
      debugPrint('[gain-selftest] 恢复 1.0x（应清除 af 链）');
      await syncVolume(gain: 1.0);
    } catch (e) {
      debugPrint('[gain-selftest] 失败: $e');
    }
    debugPrint('[gain-selftest] 完成');
  }

  /// 8-bit PCM 单声道 8kHz 0.2s 静音 WAV（自检激活引擎用）
  static Uint8List _silentWav() {
    const rate = 8000;
    const samples = 1600;
    final b = ByteData(44 + samples);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + samples, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little); // fmt 块长度
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // 单声道
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate, Endian.little); // byte rate
    b.setUint16(32, 1, Endian.little); // block align
    b.setUint16(34, 8, Endian.little); // 位深
    str(36, 'data');
    b.setUint32(40, samples, Endian.little);
    for (var i = 0; i < samples; i++) {
      b.setUint8(44 + i, 128); // 静音
    }
    return b.buffer.asUint8List();
  }

  final Ref _ref;
  /// Android 端增益:just_audio AndroidLoudnessEnhancer(浮点增益域);
  /// 桌面端走 HikoJustAudioMediaKit af 链,不注入该效果。
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = Platform.isAndroid
      ? AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_loudness]))
      : AudioPlayer();
  final SleepTimerEngine _sleep = SleepTimerEngine();
  double? _pendingSeek;
  double _lastPersistAt = 0;
  bool _isSwitching = false;
  int _playSessionId = 0;
  bool _androidEnhancerUsable = true; // LoudnessEnhancer 初始化失败后置 false 走回退

  AudioPlayer get player => _player;

  /// 睡眠定时淡出:剩余时间与淡出系数 → 压低常规音量(不动增益通道)
  void _onSleepTick(Duration remaining, double fadeFactor) {
    state = state.copyWith(
      sleepMode: _sleep.state.mode,
      sleepRemaining: remaining,
    );
    final vol =
        (_ref.read(settingsProvider).volume * fadeFactor).clamp(0.0, 1.0);
    _player.setVolume(vol).catchError((Object e) {
      debugPrint('[sleep] 淡出设置音量失败（容忍）: $e');
      return;
    });
  }

  /// 睡眠定时到点:暂停并恢复常规音量
  Future<void> _onSleepExpired() async {
    await pause();
    await syncVolume();
    state = state.copyWith(sleepMode: SleepTimerMode.off, sleepRemaining: null);
  }

  /// 启动睡眠定时(分钟数:15/30/60);到期前 10 秒淡出,到点暂停
  Future<void> setSleepMinutes(int minutes) async {
    _sleep.onTick = _onSleepTick;
    _sleep.onExpired = _onSleepExpired;
    _sleep.startTimed(minutes);
    state = state.copyWith(sleepMode: SleepTimerMode.timed);
  }

  /// 播完当前曲停:拦截在切歌路径,下一首绝不起播
  void setSleepEndOfTrack() {
    _sleep.startEndOfTrack();
    state = state.copyWith(
      sleepMode: SleepTimerMode.endOfTrack,
      sleepRemaining: null,
    );
  }

  /// 关闭睡眠定时并恢复常规音量
  Future<void> setSleepOff() async {
    _sleep.cancel();
    state = state.copyWith(sleepMode: SleepTimerMode.off, sleepRemaining: null);
    await syncVolume();
  }

  /// 播放指定专辑的第 index 首（对应旧版 chooseImported）；
  /// [startPosition] > 0 时从断点秒数起播（「继续收听」）
  Future<void> playAlbum(Album album, {int index = 0, double startPosition = 0}) async {
    final queue = album.tracks;
    if (queue.isEmpty) return;
    final idx = index.clamp(0, queue.length - 1);
    final track = queue[idx];

    final currentSession = ++_playSessionId;
    _isSwitching = true;
    final startAt = startPosition.clamp(0.0, track.duration > 0 ? track.duration : double.infinity);

    // 先带入 Track 元数据中的 duration，杜绝 0:00 闪烁，并先设为 playing: true
    state = PlaybackState(
      album: album,
      queue: queue,
      queueIndex: idx,
      playing: true,
      duration: track.duration > 0 ? track.duration : 0.0,
      position: startAt,
      mode: state.mode,
    );
    if (startAt > 0) {
      _pendingSeek = startAt;
    }

    // 内存中更新进度与断点，避免切歌时主线程被全量写盘阻塞
    final played = QueueRules.cumulativePlayed(
      albums: _ref.read(libraryProvider),
      album: album,
      queueIndex: idx,
      position: startAt,
    );
    _ref.read(libraryProvider.notifier).updatePlayedInMemory(
          album.id,
          played,
          resumeTrackIndex: idx,
          resumePosition: startAt,
          lastPlayedAt: DateTime.now(),
        );

    try {
      if (_playSessionId != currentSession) return;
      await _player
          .setUrl(track.url)
          .timeout(const Duration(seconds: 8));
      if (_playSessionId != currentSession) return;
      await syncVolume();
      if (_playSessionId != currentSession) return;
      await _applyPlaybackRate();
      if (_playSessionId != currentSession) return;
      await _player.play();
    } catch (e) {
      debugPrint('[playback] 播放失败: $e');
      if (_playSessionId == currentSession) {
        state = state.copyWith(playing: false);
      }
    } finally {
      if (_playSessionId == currentSession) {
        _isSwitching = false;
      }
    }
  }

  Future<void> toggle() async {
    if (state.album == null) return;
    if (state.playing) {
      await pause();
    } else {
      await _player.play();
      state = state.copyWith(playing: true);
    }
  }

  Future<void> pause() async {
    await _player.pause();
    state = state.copyWith(playing: false);
    _persistProgress();
  }

  Future<void> next() => _step(1);
  Future<void> prev() => _step(-1);

  Future<void> seek(double seconds) async {
    if (!state.playing && state.album == null) return;
    final duration = state.duration;
    final target = seconds.clamp(0.0, duration > 0 ? duration : seconds);
    state = state.copyWith(position: target);
    try {
      await _player.seek(Duration(milliseconds: (target * 1000).round()));
    } catch (e) {
      _pendingSeek = target;
    }
    _persistProgress(); // seek 后断点立即落盘（不信任 15 秒节流窗口）
  }

  /// 音量与增益同步（两者通道分离）：
  /// - 桌面：常规音量走 just_audio setVolume（0~1）；增益走 af 链浮点软增益 + 软限幅
  /// - Android：增益首选 AndroidLoudnessEnhancer（dB=20×log10(g)，浮点域无削波）；
  ///   不可用时回退 volume×gain 且 clamp≤1.0 防削波；g=1.0 旁路（禁用效果器）
  Future<void> syncVolume({double? baseVolume, double? gain}) async {
    final settings = _ref.read(settingsProvider);
    final vol = (baseVolume ?? settings.volume).clamp(0.0, 1.0);
    final g = (gain ?? settings.audioGain).clamp(1.0, 4.0);
    if (Platform.isAndroid) {
      await _syncVolumeAndroid(vol, g);
      return;
    }
    try {
      await _player.setVolume(vol);
    } catch (e) {
      debugPrint('[playback] syncVolume 失败（容忍）: $e');
    }
    await HikoJustAudioMediaKit.setGlobalGain(g);
  }

  /// Android 音量+增益：LoudnessEnhancer 成功路径打 [gain] 自检日志（仅 define 门控）
  Future<void> _syncVolumeAndroid(double vol, double g) async {
    if (_androidEnhancerUsable) {
      try {
        if (g <= 1.0) {
          await _loudness.setEnabled(false); // 旁路直通
        } else {
          await _loudness.setEnabled(true);
          await _loudness.setTargetGain(gainToDb(g));
        }
        await _player.setVolume(vol);
        _logGainSelftest(
            'via=loudness gain=${g.toStringAsFixed(1)}x db=${gainToDb(g).toStringAsFixed(2)} volume=${vol.toStringAsFixed(2)}');
        return;
      } catch (e) {
        _androidEnhancerUsable = false;
        debugPrint('[playback] AndroidLoudnessEnhancer 不可用,回退 volume×gain clamp: $e');
      }
    }
    // 回退路径:常规音量与增益相乘后 clamp 0~1,宁可压顶也不硬削波
    final effective = (vol * g).clamp(0.0, 1.0);
    try {
      await _player.setVolume(effective);
    } catch (e) {
      debugPrint('[playback] syncVolume 回退失败（容忍）: $e');
    }
    _logGainSelftest(
        'via=fallback gain=${g.toStringAsFixed(1)}x effective=${effective.toStringAsFixed(2)}');
  }

  /// 增益自检日志：仅 --dart-define=HIKO_GAIN_SELFTEST=1 时输出（非常驻打印）
  void _logGainSelftest(String message) {
    if (const String.fromEnvironment('HIKO_GAIN_SELFTEST') != '1') return;
    debugPrint('[gain] $message');
  }

  /// 音量设置：播放器未加载/初始化失败时容忍（UI 音量状态仍由 settings 管理）
  Future<void> setVolume(double volume) async {
    await syncVolume(baseVolume: volume);
  }

  /// 增益设置：动态应用增益倍率
  Future<void> setAudioGain(double gain) async {
    await syncVolume(gain: gain);
  }

  /// 播放倍速（0.5~2.0）：持久化到 settings 并立即应用
  Future<void> setPlaybackRate(double rate) async {
    await _ref.read(settingsProvider.notifier).setPlaybackRate(rate);
    await _applyPlaybackRate();
  }

  /// 应用当前设置中的倍速到引擎（换源/设置变更后调用）
  Future<void> _applyPlaybackRate() async {
    final rate = _ref.read(settingsProvider).playbackRate;
    try {
      await _player.setSpeed(rate);
    } catch (e) {
      debugPrint('[playback] 设置倍速失败（容忍）: $e');
    }
  }

  Future<void> setMode(PlaybackMode mode) async {
    state = state.copyWith(mode: mode);
  }

  /// 切曲（对应旧版 stepTrack 逻辑）
  Future<void> _step(int dir) async {
    // 睡眠定时拦截在切歌路径：「播完当前曲停」/ 倒计时已到点 → 停止,下一首绝不起播
    if (SleepTimerLogic.shouldBlockTrackSwitch(_sleep.state)) {
      _sleep.cancel();
      state = state.copyWith(
        sleepMode: SleepTimerMode.off,
        sleepRemaining: null,
      );
      await pause();
      await syncVolume();
      return;
    }
    final s = state;
    final album = s.album;
    if (album == null) return;
    final albums = _ref.read(libraryProvider);
    final target = QueueRules.step(
      albums: albums,
      current: album,
      queueIndex: s.queueIndex,
      mode: s.mode,
      dir: dir,
    );
    if (target == null) return;
    await playAlbum(target.$1, index: target.$2);
  }

  void _onProcessingStateChanged(ProcessingState ps) {
    // 正在切换曲目过程中，忽略过时的 completed 事件，避免重入并发调用
    if (_isSwitching) return;

    // 播放完成：单曲循环重播，否则按模式切下一首（对应旧版 ended 处理）
    if (ps == ProcessingState.completed) {
      if (SleepTimerLogic.shouldBlockTrackSwitch(_sleep.state)) {
        // 睡眠定时(曲终停/已到点):拦在切歌前,当前曲播完即停
        _step(0);
        return;
      }
      if (state.mode == PlaybackMode.single) {
        _player.seek(Duration.zero);
        _player.play();
        return;
      }
      _persistProgress(); // 播完瞬间先把「播完」断点写盘（剩 <2s → 记下一轨开头）
      _step(1);
    }
  }

  /// 进度落盘：累计进度（已完成曲目 + 当前位置），15 秒节流
  void _maybePersistProgress() {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (now - _lastPersistAt < 15) return;
    _persistProgress(now);
  }

  void _persistProgress([double? now]) {
    _lastPersistAt = now ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
    final s = state;
    final album = s.album;
    if (album == null) return;
    final resume = QueueRules.resumePoint(
      tracks: album.tracks,
      queueIndex: s.queueIndex,
      position: s.position,
    );
    final played = QueueRules.cumulativePlayed(
      albums: _ref.read(libraryProvider),
      album: album,
      queueIndex: s.queueIndex,
      position: s.position,
    );
    _ref.read(libraryProvider.notifier).updatePlayed(
          album.id,
          played,
          resumeTrackIndex: resume.$1,
          resumePosition: resume.$2,
          lastPlayedAt: DateTime.now(),
        );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _sleep.dispose();
    _player.dispose();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackController, PlaybackState>((ref) {
  return PlaybackController(ref);
});
