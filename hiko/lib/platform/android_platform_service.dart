import 'package:flutter/services.dart';

import '../models/album.dart';
import 'platform_service.dart';

/// Android 平台操作：MethodChannel 调原生插件（HikoPlugin.kt）。
/// 导入为事件流式回传（onAlbum/onProgress），避免整份 JSON 一次过桥 OOM。
class AndroidPlatformService implements PlatformService {
  static const _channel = MethodChannel('top.voicehub.hiko/plugin');

  /// SAF 目录选择 + 扫描；返回新专辑列表（未落盘，由调用方 merge+save）
  Future<List<Album>> importAudioFolder({
    void Function(int processed, int total)? onProgress,
  }) async {
    final albums = <Album>[];
    var total = 0;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAlbum':
          final json = Map<String, dynamic>.from(call.arguments as Map);
          albums.add(Album.fromJson(json));
        case 'onProgress':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          onProgress?.call((args['processed'] as num).toInt(), (args['total'] as num).toInt());
        default:
          total = (call.arguments as num?)?.toInt() ?? total;
      }
      return null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await _channel.invokeMethod('importAudioFolder') as Map,
      );
      final canceled = result['canceled'] as bool? ?? false;
      return canceled ? [] : albums;
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  @override
  Future<int> removeAlbumFiles(Album album) async {
    final files = [
      for (final t in album.tracks) t.url,
      if (album.localCover != null) album.localCover!,
    ];
    final result = Map<String, dynamic>.from(await _channel.invokeMethod(
      'deleteFiles',
      {'files': files, 'dirUri': album.sourcePath},
    ) as Map);
    return (result['deleted'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> revealInFolder(Album album) async {
    final uri = album.sourcePath.isNotEmpty
        ? album.sourcePath
        : album.tracks.isEmpty
            ? null
            : album.tracks.first.url;
    if (uri != null) {
      await _channel.invokeMethod('revealInFolder', {'uri': uri});
    }
  }

  @override
  Future<void> openDataDir() async {
    await _channel.invokeMethod('shareLibrary');
  }

  @override
  Future<List<Album>> cleanMissing(List<Album> albums) async {
    final allTracks = [for (final a in albums) for (final t in a.tracks) t];
    if (allTracks.isEmpty) return albums;
    final result = Map<String, dynamic>.from(await _channel.invokeMethod(
      'probeUris',
      {'uris': [for (final t in allTracks) t.url]},
    ) as Map);
    final aliveFlags = (result['alive'] as List).cast<bool>();
    final aliveByUrl = <String, bool>{
      for (var i = 0; i < allTracks.length; i++) allTracks[i].url: aliveFlags[i],
    };
    final kept = <Album>[];
    for (final album in albums) {
      final alive = album.tracks
          .where((t) => aliveByUrl[t.url] ?? true)
          .toList();
      if (alive.isEmpty && album.tracks.isNotEmpty) continue; // 整张失效
      kept.add(alive.length == album.tracks.length
          ? album
          : album.copyWith(tracks: alive));
    }
    return kept;
  }
}
