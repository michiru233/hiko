import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/album.dart';
import 'platform_service.dart';

/// Android 平台操作：MethodChannel 调原生插件（HikoPlugin.kt）。
/// 导入为事件流式回传（onAlbum/onProgress），避免整份 JSON 一次过桥 OOM。
class AndroidPlatformService implements PlatformService {
  static const _channel = MethodChannel('top.voicehub.hiko/plugin');

  /// SAF 目录选择 + 扫描；返回新专辑列表与所选目录 tree URI（未落盘，由调用方 merge+save）
  @override
  Future<ImportScanResult> importAudioFolder({
    void Function(int processed, int total, String phase, String unit)? onProgress,
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
          onProgress?.call(
            (args['processed'] as num).toInt(),
            (args['total'] as num).toInt(),
            args['phase'] as String? ?? 'albums',
            args['unit'] as String? ?? 'albums',
          );
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
      return (
        albums: canceled ? <Album>[] : albums,
        treeUri: result['scannedPath'] as String?,
      );
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }

  /// 扫描已授权的常驻音乐目录（SAF tree URI），事件流与导入一致，不弹选择器
  @override
  Future<List<Album>> scanSavedFolder(String treeUri,
      {void Function(int processed, int total, String phase, String unit)? onProgress}) async {
    final albums = <Album>[];
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAlbum':
          final json = Map<String, dynamic>.from(call.arguments as Map);
          albums.add(Album.fromJson(json));
        case 'onProgress':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          onProgress?.call(
            (args['processed'] as num).toInt(),
            (args['total'] as num).toInt(),
            args['phase'] as String? ?? 'albums',
            args['unit'] as String? ?? 'albums',
          );
      }
      return null;
    });
    try {
      await _channel.invokeMethod('scanFolder', {'uri': treeUri});
      return albums;
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

  /// Android 走 SAF 单树导入（树内递归多专辑），无需目录多选
  @override
  Future<List<String>?> pickDirectories() async => null;

  @override
  Future<List<Album>> cleanMissing(List<Album> albums) async {
    final allTracks = [for (final a in albums) for (final t in a.tracks) t];
    // 封面 URI 一并探测(对齐桌面:file://content:// 可探测,dataURL 内嵌永不失效不探测)
    final coverUris = [
      for (final a in albums)
        if (a.localCover != null && _probeableUri(a.localCover!)) a.localCover!,
    ];
    if (allTracks.isEmpty && coverUris.isEmpty) return albums;
    final result = Map<String, dynamic>.from(await _channel.invokeMethod(
      'probeUris',
      {
        'uris': [
          for (final t in allTracks) t.url,
          ...coverUris,
        ],
      },
    ) as Map);
    final aliveFlags = (result['alive'] as List).cast<bool>();
    final probeList = [for (final t in allTracks) t.url, ...coverUris];
    final aliveByUrl = <String, bool>{
      for (var i = 0; i < probeList.length; i++) probeList[i]: aliveFlags[i],
    };
    final kept = <Album>[];
    for (final album in albums) {
      final alive = album.tracks
          .where((t) => aliveByUrl[t.url] ?? true)
          .toList();
      // 封面失效 → 置空(与音轨探测同一批返回,对齐 desktop platform_service 行为)
      var localCover = album.localCover;
      if (localCover != null &&
          _probeableUri(localCover) &&
          !(aliveByUrl[localCover] ?? true)) {
        localCover = null;
      }
      if (alive.isEmpty && album.tracks.isNotEmpty) continue; // 整张失效
      if (alive.length == album.tracks.length && localCover == album.localCover) {
        kept.add(album);
      } else {
        kept.add(album.copyWith(tracks: alive, localCover: localCover));
      }
    }
    return kept;
  }

  /// 可探测的 URI 形态:SAF content:// 与本地 file://;dataURL 无磁盘实体
  static bool _probeableUri(String uri) =>
      uri.startsWith('content://') || uri.startsWith('file://');
}
