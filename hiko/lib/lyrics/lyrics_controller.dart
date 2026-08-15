import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../playback/playback_controller.dart';
import 'desktop_lyrics_service.dart';
import 'lyrics_resolver.dart';
import 'models/lyric_line.dart';

/// 歌词播放与显示状态
@immutable
class LyricsState {
  final ParsedLyrics parsedLyrics;
  final int activeIndex;
  final bool isLoading;
  final bool autoScrollEnabled;
  final String? lastTrackUrl;

  const LyricsState({
    this.parsedLyrics = ParsedLyrics.empty,
    this.activeIndex = -1,
    this.isLoading = false,
    this.autoScrollEnabled = true,
    this.lastTrackUrl,
  });

  List<LyricLine> get lines => parsedLyrics.lines;
  bool get hasLyrics => parsedLyrics.isNotEmpty;
  LyricLine? get currentLine =>
      (activeIndex >= 0 && activeIndex < lines.length) ? lines[activeIndex] : null;

  LyricsState copyWith({
    ParsedLyrics? parsedLyrics,
    int? activeIndex,
    bool? isLoading,
    bool? autoScrollEnabled,
    String? lastTrackUrl,
  }) {
    return LyricsState(
      parsedLyrics: parsedLyrics ?? this.parsedLyrics,
      activeIndex: activeIndex ?? this.activeIndex,
      isLoading: isLoading ?? this.isLoading,
      autoScrollEnabled: autoScrollEnabled ?? this.autoScrollEnabled,
      lastTrackUrl: lastTrackUrl ?? this.lastTrackUrl,
    );
  }
}

class LyricsController extends StateNotifier<LyricsState> {
  LyricsController(this._ref) : super(const LyricsState()) {
    _listenToPlayback();
  }

  final Ref _ref;
  Timer? _resumeAutoScrollTimer;
  String? _lastEmittedLineText;

  void _listenToPlayback() {
    _ref.listen<PlaybackState>(playbackProvider, (previous, next) {
      final currentTrack = next.currentTrack;

      // 1. 曲目切换
      if (currentTrack?.url != state.lastTrackUrl) {
        _onTrackChanged(currentTrack, next);
        return;
      }

      // 2. 播放进度更新 -> 二分查找高亮行
      if (state.hasLyrics && next.position >= 0) {
        final positionDuration = Duration(milliseconds: (next.position * 1000).round());
        final newIndex = _findActiveIndex(state.lines, positionDuration);

        if (newIndex != state.activeIndex) {
          state = state.copyWith(activeIndex: newIndex);
          _syncToDesktopHUD(next);
        }
      }
    });
  }

  Future<void> _onTrackChanged(Track? track, PlaybackState playback) async {
    if (track == null) {
      state = const LyricsState();
      _syncToDesktopHUD(playback);
      return;
    }

    state = state.copyWith(
      isLoading: true,
      activeIndex: -1,
      lastTrackUrl: track.url,
      autoScrollEnabled: true,
    );

    final lyrics = await LyricsResolver.resolve(track, album: playback.album);

    // 校验异步返回时曲目是否仍为当前曲目
    if (state.lastTrackUrl == track.url) {
      final currentPos = Duration(milliseconds: (playback.position * 1000).round());
      final initialIndex = (lyrics != null && lyrics.isNotEmpty)
          ? _findActiveIndex(lyrics.lines, currentPos)
          : -1;

      state = state.copyWith(
        parsedLyrics: lyrics ?? ParsedLyrics.empty,
        activeIndex: initialIndex,
        isLoading: false,
      );

      _syncToDesktopHUD(playback);
    }
  }

  /// O(log N) 二分查找当前活跃的歌词行索引
  /// 查找满足 lines[i].startTime <= position 的最大 i
  static int _findActiveIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    if (position < lines.first.startTime) return -1;
    if (position >= lines.last.startTime) return lines.length - 1;

    var low = 0;
    var high = lines.length - 1;
    var result = 0;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final midLine = lines[mid];

      if (midLine.startTime <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }

  /// 点击某行歌词跳转播放进度
  void seekToLine(int index) {
    if (index < 0 || index >= state.lines.length) return;
    final line = state.lines[index];
    final seconds = line.startTime.inMilliseconds / 1000.0;

    _ref.read(playbackProvider.notifier).seek(seconds);
    resumeAutoScroll();
  }

  /// 用户手动滚动歌词列表时调用：暂停自动跟随
  void userScrolled() {
    if (state.autoScrollEnabled) {
      state = state.copyWith(autoScrollEnabled: false);
    }

    _resumeAutoScrollTimer?.cancel();
    _resumeAutoScrollTimer = Timer(const Duration(seconds: 3), () {
      resumeAutoScroll();
    });
  }

  /// 恢复自动跟随滚动
  void resumeAutoScroll() {
    _resumeAutoScrollTimer?.cancel();
    if (!state.autoScrollEnabled) {
      state = state.copyWith(autoScrollEnabled: true);
    }
  }

  /// 将当前歌词行同步至系统桌面 HUD
  void _syncToDesktopHUD(PlaybackState playback) {
    final currentLine = state.currentLine;
    final lineText = currentLine?.text ?? (playback.currentTrack?.name ?? '');

    if (_lastEmittedLineText != lineText) {
      _lastEmittedLineText = lineText;
      _ref.read(desktopLyricsServiceProvider).updateLyrics(
            currentLine: lineText,
            speaker: currentLine?.speaker,
            translation: currentLine?.translation,
          );
    }
  }

  @override
  void dispose() {
    _resumeAutoScrollTimer?.cancel();
    super.dispose();
  }
}

/// 歌词状态全局 Provider
final lyricsProvider = StateNotifierProvider<LyricsController, LyricsState>((ref) {
  return LyricsController(ref);
});
