import 'dart:math';

import '../models/album.dart';
import '../models/track.dart';

/// 播放模式（对应旧版 app.js 四种）
enum PlaybackMode { list, single, shuffle, album }

extension PlaybackModeX on PlaybackMode {
  String get key => switch (this) {
        PlaybackMode.list => 'list',
        PlaybackMode.single => 'single',
        PlaybackMode.shuffle => 'shuffle',
        PlaybackMode.album => 'album',
      };

  static PlaybackMode fromKey(String? key) => switch (key) {
        'single' => PlaybackMode.single,
        'shuffle' => PlaybackMode.shuffle,
        'album' => PlaybackMode.album,
        _ => PlaybackMode.list,
      };
}

/// 队列推进规则（纯函数，可单测）。
/// 对应旧版 stepTrack / playRandomTrack / playNextAlbum 的行为：
/// - list：边界回绕
/// - single：由调用方处理重播，不参与换曲
/// - shuffle：专辑内随机，避免连播同一首
/// - album：专辑边界处跨专辑接续（跳过无音轨专辑）
class QueueRules {
  /// 计算 stepTrack(dir) 的目标（index, album）；返回 null 表示无目标
  static (Album album, int index)? step({
    required List<Album> albums,
    required Album current,
    required int queueIndex,
    required PlaybackMode mode,
    required int dir,
    Random? random,
  }) {
    final tracks = current.tracks;
    if (tracks.isEmpty) return null;
    if (mode == PlaybackMode.shuffle) {
      if (tracks.length <= 1) return (current, 0);
      final rng = random ?? Random();
      var idx = 0;
      do {
        idx = rng.nextInt(tracks.length);
      } while (idx == queueIndex);
      return (current, idx);
    }
    var idx = queueIndex + dir;
    if (idx >= tracks.length) {
      if (mode == PlaybackMode.album) {
        final next = _nextAlbum(albums, current.id, 1);
        if (next == null) return null;
        return (next, 0);
      }
      idx = 0;
    } else if (idx < 0) {
      if (mode == PlaybackMode.album) {
        final next = _nextAlbum(albums, current.id, -1);
        if (next == null) return null;
        return (next, next.tracks.length - 1);
      }
      idx = tracks.length - 1;
    }
    return (current, idx);
  }

  /// 循环查找 dir 方向下一张「有音轨」的专辑（跳过空专辑）
  static Album? _nextAlbum(List<Album> albums, String currentId, int dir) {
    if (albums.isEmpty) return null;
    final start = albums.indexWhere((a) => a.id == currentId);
    if (start < 0) return null;
    for (var i = 1; i <= albums.length; i++) {
      final next = albums[(start + dir * i + albums.length) % albums.length];
      if (next.tracks.isNotEmpty) return next;
    }
    return null;
  }

  /// 专辑内累计播放进度：已完成曲目时长之和 + 当前曲位置
  static double cumulativePlayed({
    required List<Album> albums,
    required Album album,
    required int queueIndex,
    required double position,
  }) {
    if (albums.isEmpty) return position;
    var sum = 0.0;
    for (var i = 0; i < queueIndex && i < album.tracks.length; i++) {
      sum += album.tracks[i].duration;
    }
    return sum + position;
  }

  /// 断点落盘目标：单轨只剩 <2 秒视为已播完，断点记为下一轨 0 秒；
  /// 已是最后一轨则回到第 0 轨 0 秒。其余情况 clamp 在当前轨时长内。
  static (int trackIndex, double position) resumePoint({
    required List<Track> tracks,
    required int queueIndex,
    required double position,
  }) {
    if (tracks.isEmpty) return (0, 0);
    final idx = queueIndex.clamp(0, tracks.length - 1);
    final duration = tracks[idx].duration;
    final remaining = duration - position;
    if (duration > 0 && remaining < 2) {
      final next = idx + 1;
      if (next >= tracks.length) return (0, 0);
      return (next, 0);
    }
    return (idx, position.clamp(0.0, duration > 0 ? duration : position));
  }

  /// 「继续收听」候选：最近一次播放过的专辑（有断点记录），
  /// 排除当前正在播放的专辑；无任何断点时返回 null。
  static Album? resumeCandidate(
    List<Album> albums, {
    String? playingAlbumId,
  }) {
    Album? best;
    for (final a in albums) {
      if (a.resumeTrackIndex < 0) continue;
      if (playingAlbumId != null && a.id == playingAlbumId) continue;
      final at = a.lastPlayedAt;
      if (best == null ||
          (at != null &&
              (best.lastPlayedAt == null || at.isAfter(best.lastPlayedAt!)))) {
        best = a;
      }
    }
    return best;
  }
}
