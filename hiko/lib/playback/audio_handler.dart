import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';
import '../models/track.dart';
import 'playback_controller.dart';

/// audio_service 处理器：Android 与 macOS 后台播放 / 系统通知 / 锁屏与控制中心控制。
/// 将系统媒体按键（MPRemoteCommandCenter / MediaSession）与控制中心指令转发给 [PlaybackController]。
class HikoAudioHandler extends BaseAudioHandler with SeekHandler {
  HikoAudioHandler(this._controller) {
    _controller.addListener((_) {
      _syncNowPlaying();
      _syncPlaybackState();
    });

    // 进度/播放状态 → audio_service playbackState（通知、锁屏与 macOS 控制中心进度条）
    _controller.player.positionStream.listen((pos) {
      _syncPlaybackState(positionOverride: pos);
    });

    _controller.player.playerStateStream.listen((ps) {
      _syncPlaybackState(playingOverride: ps.playing);
    });
  }

  final PlaybackController _controller;
  static Directory? _artCacheDir;
  String? _lastCoverUrl;
  Uri? _cachedArtUri;

  /// 控制中心/通知栏支持的系统动作集（快进、快退、切歌、拖拽进度条）
  static const _systemActions = {
    MediaAction.seek,
    MediaAction.seekForward,
    MediaAction.seekBackward,
    MediaAction.skipToNext,
    MediaAction.skipToPrevious,
    MediaAction.stop,
  };

  void _syncPlaybackState({
    Duration? positionOverride,
    bool? playingOverride,
  }) {
    final s = _controller.state;
    final isPlaying = playingOverride ?? s.playing;
    final currentPos = positionOverride ??
        Duration(milliseconds: (s.position * 1000).round());
    final hasItem = s.album != null && s.currentTrack != null;

    final controls = [
      MediaControl.skipToPrevious,
      if (isPlaying)
        MediaControl.pause
      else
        MediaControl.play,
      MediaControl.skipToNext,
    ];

    playbackState.add(playbackState.value.copyWith(
      controls: hasItem ? controls : const [],
      systemActions: hasItem ? _systemActions : const {},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: hasItem
          ? AudioProcessingState.ready
          : AudioProcessingState.idle,
      playing: isPlaying,
      updatePosition: currentPos,
      bufferedPosition: currentPos,
      speed: isPlaying ? 1.0 : 0.0,
    ));
  }

  Future<void> _syncNowPlaying() async {
    final s = _controller.state;
    final album = s.album;
    final track = s.currentTrack;
    if (album == null || track == null) {
      mediaItem.add(null);
      return;
    }

    final artUri = await _resolveArtUri(album);
    // 异步完成期间若切了歌，校验是否还是当前同一首
    final cur = _controller.state;
    if (cur.album?.id != album.id || cur.currentTrack?.url != track.url) {
      return;
    }

    mediaItem.add(MediaItem(
      id: track.url,
      title: track.name,
      artist: album.artist.isNotEmpty && album.artist != '本地导入'
          ? album.artist
          : (album.group.isNotEmpty ? album.group : 'Hiko'),
      album: album.title,
      artUri: artUri,
      duration: track.duration > 0
          ? Duration(milliseconds: (track.duration * 1000).round())
          : null,
    ));
  }

  /// 将专辑封面（可能是 Base64 Data URL / file:// / http://）解析为系统组件可读取的 Uri
  Future<Uri?> _resolveArtUri(Album album) async {
    final cover = album.currentCover ?? album.localCover;
    if (cover == null || cover.isEmpty) return null;

    if (cover.startsWith('file://')) {
      return Uri.tryParse(cover);
    }
    if (cover.startsWith('http://') || cover.startsWith('https://')) {
      return Uri.tryParse(cover);
    }
    if (cover.startsWith('data:image/')) {
      if (_lastCoverUrl == cover && _cachedArtUri != null) {
        return _cachedArtUri;
      }
      try {
        final commaIdx = cover.indexOf(',');
        if (commaIdx == -1) return null;
        final base64Str = cover.substring(commaIdx + 1);
        final bytes = base64Decode(base64Str);

        final dir = await _getArtCacheDirectory();
        final file = File(p.join(dir.path, '${album.id}.jpg'));
        await file.writeAsBytes(bytes, flush: true);

        _lastCoverUrl = cover;
        _cachedArtUri = Uri.file(file.path);
        return _cachedArtUri;
      } catch (e) {
        debugPrint('[HikoAudioHandler] 缓存封面失败: $e');
        return null;
      }
    }

    if (cover.startsWith('/')) {
      return Uri.file(cover);
    }
    return Uri.tryParse(cover);
  }

  Future<Directory> _getArtCacheDirectory() async {
    if (_artCacheDir != null) return _artCacheDir!;
    final temp = await getTemporaryDirectory();
    final dir = Directory(p.join(temp.path, 'hiko_art_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _artCacheDir = dir;
    return dir;
  }

  @override
  Future<void> play() => _controller.toggle();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> stop() => _controller.pause();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
      case MediaButton.next:
        await _controller.toggle();
        break;
      case MediaButton.previous:
        await _controller.prev();
        break;
    }
  }

  @override
  Future<void> skipToNext() => _controller.next();

  @override
  Future<void> skipToPrevious() => _controller.prev();

  @override
  Future<void> seek(Duration position) =>
      _controller.seek(position.inMilliseconds / 1000.0);

  @override
  Future<void> fastForward() async {
    final pos = _controller.state.position + 15.0;
    await _controller.seek(pos);
  }

  @override
  Future<void> rewind() async {
    final pos = (_controller.state.position - 15.0).clamp(0.0, double.infinity);
    await _controller.seek(pos.toDouble());
  }
}
