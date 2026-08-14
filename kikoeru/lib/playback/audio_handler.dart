import 'package:audio_service/audio_service.dart';

import '../models/album.dart';
import '../models/track.dart';
import 'playback_controller.dart';

/// audio_service 处理器：Android 后台播放 + 通知 + 锁屏控制。
/// 桌面端（macOS/Windows）不启用 audio_service，本类不初始化。
/// 通知/锁屏按键经 MediaSession 回调到这里，再转发给 [PlaybackController]，
/// 队列切换逻辑始终留在播放控制器（对应旧版 audio:command 转发设计）。
class KikoeruAudioHandler extends BaseAudioHandler {
  KikoeruAudioHandler(this._controller) {
    _controller.addListener((_) => _syncNowPlaying());
    // 进度/播放状态 → audio_service playbackState（通知与锁屏进度条）
    _controller.player.positionStream.listen((pos) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: pos,
        controls: _controls,
      ));
    });
    _controller.player.playerStateStream.listen((ps) {
      playbackState.add(playbackState.value.copyWith(
        playing: ps.playing,
        controls: _controls,
      ));
    });
  }

  final PlaybackController _controller;

  /// 通知控制按钮：上一首 / 播放暂停 / 下一首（MediaAction.playPause 为切换语义）
  static const _controls = [
    MediaControl.skipToPrevious,
    MediaControl(
      androidIcon: 'drawable/audio_service_pause',
      label: '播放/暂停',
      action: MediaAction.playPause,
    ),
    MediaControl.skipToNext,
  ];

  void _syncNowPlaying() {
    final s = _controller.state;
    final album = s.album;
    final track = s.currentTrack;
    if (album == null || track == null) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(_toMediaItem(album, track));
  }

  MediaItem _toMediaItem(Album album, Track track) => MediaItem(
        id: track.url,
        title: track.name,
        artist: album.artist,
        album: album.title,
        // data URI 封面（audio_service 在 Android 侧解码为通知大图标）
        artUri: album.localCover != null ? Uri.tryParse(album.localCover!) : null,
        duration: track.duration > 0
            ? Duration(milliseconds: (track.duration * 1000).round())
            : null,
      );

  @override
  Future<void> play() => _controller.toggle();
  @override
  Future<void> pause() => _controller.pause();
  @override
  Future<void> skipToNext() => _controller.next();
  @override
  Future<void> skipToPrevious() => _controller.prev();
  @override
  Future<void> seek(Duration position) =>
      _controller.seek(position.inMilliseconds / 1000.0);
}
