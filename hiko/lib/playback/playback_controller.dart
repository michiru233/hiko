import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/library_provider.dart';
import '../data/settings_store.dart';
import '../models/album.dart';
import '../models/track.dart';
import 'playback_rules.dart';

/// 播放器状态（UI 直接消费）
class PlaybackState {
  final Album? album; // 当前专辑
  final List<Track> queue; // 当前队列（= 专辑 tracks）
  final int queueIndex;
  final bool playing;
  final double position; // 秒（当前曲）
  final double duration; // 秒（当前曲）
  final PlaybackMode mode;

  const PlaybackState({
    this.album,
    this.queue = const [],
    this.queueIndex = -1,
    this.playing = false,
    this.position = 0,
    this.duration = 0,
    this.mode = PlaybackMode.list,
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
  }) =>
      PlaybackState(
        album: album ?? this.album,
        queue: queue ?? this.queue,
        queueIndex: queueIndex ?? this.queueIndex,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        mode: mode ?? this.mode,
      );
}

/// 播放控制器：just_audio 封装 + 队列/播放模式/进度持久化。
/// 纯逻辑可单测部分在 [QueueRules]；本类只做 just_audio 接线。
class PlaybackController extends StateNotifier<PlaybackState> {
  PlaybackController(this._ref) : super(const PlaybackState()) {
    _player.playbackEventStream.listen(_onPlaybackEvent);
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
  }

  final Ref _ref;
  final AudioPlayer _player = AudioPlayer();
  double? _pendingSeek;
  double _lastPersistAt = 0;

  AudioPlayer get player => _player;

  /// 播放指定专辑的第 index 首（对应旧版 chooseImported）
  Future<void> playAlbum(Album album, {int index = 0}) async {
    final queue = album.tracks;
    if (queue.isEmpty) return;
    final idx = index.clamp(0, queue.length - 1);
    state = PlaybackState(
      album: album,
      queue: queue,
      queueIndex: idx,
      playing: true,
      mode: state.mode,
    );
    _persistProgress(0);
    try {
      await _player.setUrl(queue[idx].url);
      await syncVolume();
      await _player.play();
    } catch (e) {
      debugPrint('[playback] 播放失败，跳过此曲: $e');
      state = state.copyWith(playing: false);
      _step(1);
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
  }

  /// 音量与增益同步：根据 baseVolume 与 gain 计算有效合成音量
  /// libmpv 引擎支持超过 1.0 的浮点软增益（1.0 ~ 3.0x）
  Future<void> syncVolume({double? baseVolume, double? gain}) async {
    final settings = _ref.read(settingsProvider);
    final vol = (baseVolume ?? settings.volume).clamp(0.0, 1.0);
    final g = (gain ?? settings.audioGain).clamp(1.0, 3.0);
    final effective = (vol * g).toDouble();
    try {
      await _player.setVolume(effective);
    } catch (e) {
      debugPrint('[playback] syncVolume 失败（容忍）: $e');
    }
  }

  /// 音量设置：播放器未加载/初始化失败时容忍（UI 音量状态仍由 settings 管理）
  Future<void> setVolume(double volume) async {
    await syncVolume(baseVolume: volume);
  }

  /// 增益设置：动态应用增益倍率
  Future<void> setAudioGain(double gain) async {
    await syncVolume(gain: gain);
  }

  Future<void> setMode(PlaybackMode mode) async {
    state = state.copyWith(mode: mode);
  }

  /// 切曲（对应旧版 stepTrack 逻辑）
  Future<void> _step(int dir) async {
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

  void _onPlaybackEvent(PlaybackEvent event) {
    // 播放完成：单曲循环重播，否则按模式切下一首（对应旧版 ended 处理）
    if (event.processingState == ProcessingState.completed) {
      if (state.mode == PlaybackMode.single) {
        _player.seek(Duration.zero);
        _player.play();
        return;
      }
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
    final played = QueueRules.cumulativePlayed(
      albums: _ref.read(libraryProvider),
      album: album,
      queueIndex: s.queueIndex,
      position: s.position,
    );
    _ref.read(libraryProvider.notifier).updatePlayed(album.id, played);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackController, PlaybackState>((ref) {
  return PlaybackController(ref);
});
