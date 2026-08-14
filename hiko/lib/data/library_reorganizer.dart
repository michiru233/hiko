import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/track.dart';
import 'library_provider.dart';
import 'scanner.dart' as scanner;

/// 整理变动统计指标
class ReorganizeStats {
  final int scannedAlbums;
  final int updatedAlbums;
  final int removedAlbums;
  final int tracksAdded;
  final int tracksRemoved;
  final int tracksModified;

  const ReorganizeStats({
    this.scannedAlbums = 0,
    this.updatedAlbums = 0,
    this.removedAlbums = 0,
    this.tracksAdded = 0,
    this.tracksRemoved = 0,
    this.tracksModified = 0,
  });

  bool get hasChanges =>
      updatedAlbums > 0 ||
      removedAlbums > 0 ||
      tracksAdded > 0 ||
      tracksRemoved > 0 ||
      tracksModified > 0;

  ReorganizeStats copyWith({
    int? scannedAlbums,
    int? updatedAlbums,
    int? removedAlbums,
    int? tracksAdded,
    int? tracksRemoved,
    int? tracksModified,
  }) =>
      ReorganizeStats(
        scannedAlbums: scannedAlbums ?? this.scannedAlbums,
        updatedAlbums: updatedAlbums ?? this.updatedAlbums,
        removedAlbums: removedAlbums ?? this.removedAlbums,
        tracksAdded: tracksAdded ?? this.tracksAdded,
        tracksRemoved: tracksRemoved ?? this.tracksRemoved,
        tracksModified: tracksModified ?? this.tracksModified,
      );

  ReorganizeStats operator +(ReorganizeStats other) => ReorganizeStats(
        scannedAlbums: scannedAlbums + other.scannedAlbums,
        updatedAlbums: updatedAlbums + other.updatedAlbums,
        removedAlbums: removedAlbums + other.removedAlbums,
        tracksAdded: tracksAdded + other.tracksAdded,
        tracksRemoved: tracksRemoved + other.tracksRemoved,
        tracksModified: tracksModified + other.tracksModified,
      );
}

/// 整理结果
class ReorganizeResult {
  final ReorganizeStats stats;
  final List<Album> albums;

  const ReorganizeResult({
    required this.stats,
    required this.albums,
  });
}

/// 库与专辑整理服务：
/// 重新扫描音频文件，自动同步歌曲删除、改名、新增以及元数据/封面变动，
/// 同时 100% 保留用户的收藏、播放进度及 DLsite 刮削信息。
class LibraryReorganizer {
  final Ref _ref;

  LibraryReorganizer(this._ref);

  /// 整理全库专辑
  Future<ReorganizeResult> reorganizeAll({
    void Function(int current, int total, String currentAlbumTitle)? onProgress,
  }) async {
    final currentAlbums = _ref.read(libraryProvider);
    if (currentAlbums.isEmpty) {
      return const ReorganizeResult(
        stats: ReorganizeStats(),
        albums: [],
      );
    }

    final newAlbumList = <Album>[];
    var totalStats = const ReorganizeStats();
    final processedSourceDirs = <String>{};

    // 按 sourcePath 目录聚合，避免同目录重复全量扫描
    for (var i = 0; i < currentAlbums.length; i++) {
      final oldAlbum = currentAlbums[i];
      onProgress?.call(i + 1, currentAlbums.length, oldAlbum.title);

      final dir = _findAlbumDir(oldAlbum);
      if (dir != null && processedSourceDirs.contains(dir)) {
        // 同目录已在先前专辑扫描中产出过新专辑，避免重复添加
        continue;
      }

      final singleResult = await reorganizeSingleAlbum(oldAlbum);
      totalStats += singleResult.stats;

      if (dir != null && Directory(dir).existsSync()) {
        processedSourceDirs.add(dir);
      }

      newAlbumList.addAll(singleResult.albums);
    }

    // 更新状态库并持久化
    await _ref.read(libraryProvider.notifier).replaceAll(newAlbumList);

    return ReorganizeResult(
      stats: totalStats.copyWith(scannedAlbums: currentAlbums.length),
      albums: newAlbumList,
    );
  }

  /// 整理单张专辑（或其所在文件夹）
  Future<ReorganizeResult> reorganizeSingleAlbum(Album oldAlbum) async {
    final dir = _findAlbumDir(oldAlbum);

    // 1. 如果源目录不存在，降级检查各曲目文件有效性（剔除不存在的曲目）
    if (dir == null || !await Directory(dir).exists()) {
      return _cleanMissingForSingle(oldAlbum);
    }

    // 2. 源目录存在，重新调用 scanner 扫描最新文件与元数据
    final scannedAlbums = await scanner.scanPath(dir);

    // 目录内没有任何音频文件 → 专辑全部歌曲已被删除
    if (scannedAlbums.isEmpty) {
      return ReorganizeResult(
        stats: ReorganizeStats(
          scannedAlbums: 1,
          removedAlbums: 1,
          tracksRemoved: oldAlbum.tracks.length,
        ),
        albums: [],
      );
    }

    // 3. 将扫描出的新专辑与旧专辑属性进行合并
    final mergedAlbums = <Album>[];
    var updatedCount = 0;
    var tracksAdded = 0;
    var tracksRemoved = 0;
    var tracksModified = 0;

    // 构建旧曲目速查表
    final oldTrackMap = <String, Track>{
      for (final t in oldAlbum.tracks) t.url: t,
    };
    final oldUrls = oldTrackMap.keys.toSet();

    for (final fresh in scannedAlbums) {
      final freshUrls = fresh.tracks.map((t) => t.url).toSet();

      // 计算曲目变动
      final added = freshUrls.difference(oldUrls).length;
      final removed = oldUrls.difference(freshUrls).length;
      var modified = 0;

      for (final t in fresh.tracks) {
        final oldT = oldTrackMap[t.url];
        if (oldT != null) {
          final nameChanged = oldT.name != t.name;
          final durChanged = (oldT.duration - t.duration).abs() > 0.5;
          if (nameChanged || durChanged) {
            modified++;
          }
        }
      }

      final hasDlsite =
          oldAlbum.dlsiteTitle != null && oldAlbum.dlsiteTitle!.isNotEmpty;

      // 合并用户已有状态：收藏、播放进度、刮削标签、DLsite标题等
      final merged = fresh.copyWith(
        title: hasDlsite ? oldAlbum.title : fresh.title,
        artist: (hasDlsite && oldAlbum.artist != '本地导入')
            ? oldAlbum.artist
            : fresh.artist,
        albumArtist: (hasDlsite && oldAlbum.albumArtist.isNotEmpty)
            ? oldAlbum.albumArtist
            : fresh.albumArtist,
        rjCode: oldAlbum.rjCode ?? fresh.rjCode,
        dlsiteTitle: oldAlbum.dlsiteTitle ?? fresh.dlsiteTitle,
        tags: oldAlbum.tags.isNotEmpty ? oldAlbum.tags : fresh.tags,
        genre: oldAlbum.genre != '未分类' ? oldAlbum.genre : fresh.genre,
        played: oldAlbum.played > 0
            ? oldAlbum.played.clamp(
                0.0,
                fresh.totalDuration > 0 ? fresh.totalDuration : oldAlbum.played,
              )
            : 0.0,
        favorite: oldAlbum.favorite,
        localCover: fresh.localCover ?? oldAlbum.localCover,
      );

      final isDifferent = added > 0 ||
          removed > 0 ||
          modified > 0 ||
          oldAlbum.title != merged.title ||
          oldAlbum.artist != merged.artist ||
          oldAlbum.tracks.length != merged.tracks.length ||
          oldAlbum.localCover != merged.localCover ||
          (oldAlbum.totalDuration - merged.totalDuration).abs() > 0.5;

      if (isDifferent) {
        updatedCount++;
      }

      tracksAdded += added;
      tracksRemoved += removed;
      tracksModified += modified;

      mergedAlbums.add(merged);
    }

    return ReorganizeResult(
      stats: ReorganizeStats(
        scannedAlbums: 1,
        updatedAlbums: updatedCount > 0 ? 1 : 0,
        tracksAdded: tracksAdded,
        tracksRemoved: tracksRemoved,
        tracksModified: tracksModified,
      ),
      albums: mergedAlbums,
    );
  }

  /// 当专辑文件夹不存在时的单专辑降级清理
  ReorganizeResult _cleanMissingForSingle(Album oldAlbum) {
    final aliveTracks = <Track>[];
    for (final t in oldAlbum.tracks) {
      final path = _pathFromUrl(t.url);
      if (path != null && File(path).existsSync()) {
        aliveTracks.add(t);
      }
    }

    final removedCount = oldAlbum.tracks.length - aliveTracks.length;
    if (aliveTracks.isEmpty) {
      return ReorganizeResult(
        stats: ReorganizeStats(
          scannedAlbums: 1,
          removedAlbums: 1,
          tracksRemoved: oldAlbum.tracks.length,
        ),
        albums: [],
      );
    }

    if (removedCount > 0) {
      final updated = oldAlbum.copyWith(tracks: aliveTracks);
      return ReorganizeResult(
        stats: ReorganizeStats(
          scannedAlbums: 1,
          updatedAlbums: 1,
          tracksRemoved: removedCount,
        ),
        albums: [updated],
      );
    }

    return ReorganizeResult(
      stats: const ReorganizeStats(scannedAlbums: 1),
      albums: [oldAlbum],
    );
  }

  /// 寻找专辑的最佳根目录
  static String? _findAlbumDir(Album album) {
    if (album.sourcePath.isNotEmpty && !album.sourcePath.startsWith('content://')) {
      final cleanPath = album.sourcePath.startsWith('file://')
          ? _pathFromUrl(album.sourcePath)
          : album.sourcePath;
      if (cleanPath != null && Directory(cleanPath).existsSync()) {
        return cleanPath;
      }
    }

    // 从曲目提取路径
    final trackPaths = album.tracks
        .map((t) => _pathFromUrl(t.url))
        .whereType<String>()
        .toList();
    if (trackPaths.isEmpty) return null;

    // 寻找所有曲目的公共根目录
    return _findCommonDirectory(trackPaths);
  }

  /// 从多个文件路径中寻找最长公共父目录
  static String? _findCommonDirectory(List<String> filePaths) {
    if (filePaths.isEmpty) return null;
    if (filePaths.length == 1) {
      final file = File(filePaths.first);
      return file.parent.path;
    }

    final sep = Platform.pathSeparator;
    final splitPaths = filePaths.map((p) => p.split(sep)).toList();

    var minLength = splitPaths.first.length;
    for (final parts in splitPaths) {
      if (parts.length < minLength) minLength = parts.length;
    }

    final commonSegments = <String>[];
    for (var i = 0; i < minLength - 1; i++) {
      final segment = splitPaths.first[i];
      if (splitPaths.every((parts) => parts[i] == segment)) {
        commonSegments.add(segment);
      } else {
        break;
      }
    }

    if (commonSegments.isEmpty) {
      return File(filePaths.first).parent.path;
    }

    var result = commonSegments.join(sep);
    if (Platform.isMacOS || Platform.isLinux) {
      if (!result.startsWith(sep)) result = '$sep$result';
    }
    return result;
  }

  static String? _pathFromUrl(String url) {
    if (url.startsWith('file:')) {
      try {
        return Uri.parse(url).toFilePath();
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

final libraryReorganizerProvider = Provider<LibraryReorganizer>((ref) {
  return LibraryReorganizer(ref);
});
