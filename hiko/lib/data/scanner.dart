import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/track.dart';
import '../utils/natural_compare.dart';
import '../utils/repair_text.dart';
import '../utils/rj.dart';
import 'cover.dart';
import 'metadata.dart';

const audioExtensions = {
  '.mp3', '.m4a', '.wav', '.flac', '.ogg', '.aac', '.opus', '.webm',
};
const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

String _ext(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;
String _toFileUrl(String path) => Uri.file(path).toString();

/// sha1 前 16 位 hex（与 Android stableId 同源）
String stableId(String value) =>
    sha1.convert(utf8.encode(value)).toString().substring(0, 16);

/// 递归收集目录下所有文件（跳过 . 开头条目）
/// 在后台 Isolate 中同步执行文件系统扫描，主 UI 线程零 I/O 停顿
Future<List<String>> collectFiles(String rootPath) async {
  return compute(_collectFilesSync, rootPath);
}

List<String> _collectFilesSync(String rootPath) {
  final out = <String>[];
  void walk(String dirPath) {
    try {
      final dir = Directory(dirPath);
      final entries = dir.listSync(followLinks: false);
      for (final e in entries) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          walk(e.path);
        } else if (e is File) {
          out.add(e.path);
        }
      }
    } catch (_) {}
  }

  walk(rootPath);
  return out;
}

/// 单文件解析结果（跨 isolate 可序列化）
class FileMeta {
  final String path;
  final String dirPath;
  final String dirName;
  final String? title;
  final String? artist; // 曲目艺术家（MP3=TPE1）
  final String? albumArtist; // 专辑艺术家（MP3=TPE2）
  final String? album;
  final int? trackNumber;
  final double duration;
  final String? cover; // 压缩后 dataURL

  FileMeta({
    required this.path,
    required this.dirPath,
    required this.dirName,
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.trackNumber,
    this.duration = 0,
    this.cover,
  });
}

/// compute 载荷：一批文件路径
class ParseBatch {
  final List<String> paths;
  const ParseBatch(this.paths);
}

/// compute 入口：批量解析元数据（单文件失败返回 null 容错；默认不提取大图）
Future<List<FileMeta?>> parseBatch(ParseBatch job) async {
  return Future.wait(job.paths.map((p) async {
    final meta = await readTrackMetadata(p, getImage: false);
    if (meta == null) return null;
    final dirPath = p.substring(0, p.lastIndexOf(Platform.pathSeparator));
    return FileMeta(
      path: p,
      dirPath: dirPath,
      dirName: _fileName(dirPath),
      title: meta.title,
      artist: meta.artist,
      albumArtist: meta.albumArtist,
      album: meta.album,
      trackNumber: meta.trackNumber,
      duration: meta.duration,
      cover: null,
    );
  }));
}

/// 混合分组键（对齐 Android ImportScanner）：
/// 有可用 ALBUM 标签（或无标签时继承目录多数文件的专辑名）→ 按「专辑艺术家|专辑名」聚合；
/// 否则按文件夹。专辑名/艺术家先规范化（trim + 去尾部 NUL）。
String _groupKey(FileMeta m, Map<String, String?> directoryAlbums) {
  final albumName = m.album ?? directoryAlbums[m.dirPath];
  final albumKey = (albumName != null && !looksGarbled(albumName) && albumName.trim().isNotEmpty)
      ? albumName
      : null;
  final normalizedAlbum = albumKey == null ? null : normalizeTag(albumKey);
  // 分组的「专辑艺术家」固定用 TPE2：artist 现在是第一轨曲目艺术家（TPE1），
  // 同专辑各轨声优可能不同，用它分组会把一张专辑拆散
  final normalizedArtist = normalizeTag((m.albumArtist ?? m.artist) ?? '');
  return normalizedAlbum != null
      ? 'tag:$normalizedArtist|$normalizedAlbum'
      : 'dir:${m.dirPath}';
}

/// 标签规范化（对齐 Android normalizeTag）：去首尾空白与尾部 NUL。
/// Dart 无标准库 NFC 规范化，ID3 文本实际均为 NFC 写入，此处只做必要清洗。
String normalizeTag(String s) => s.trim().replaceAll(RegExp(r'\u0000+$'), '');

/// 组内全部目录（去重）的文件夹封面：优先 (cover|front|folder|album|封面) 命名的图片，
/// 否则第一张图，压缩后 dataURL（对齐 Android 跨目录封面回退）
Future<String?> _groupDirCover(List<String> dirs) async {
  final images = <File>[];
  for (final dir in dirs) {
    try {
      await for (final e in Directory(dir).list(followLinks: false)) {
        if (e is File && imageExtensions.contains(_ext(e.path))) {
          images.add(e);
        }
      }
    } catch (_) {}
  }
  if (images.isEmpty) return null;
  File? pick;
  for (final f in images) {
    if (RegExp(r'cover|front|folder|album|封面', caseSensitive: false)
        .hasMatch(_fileName(f.path))) {
      pick = f;
      break;
    }
  }
  pick ??= images.first;
  try {
    // 大图不再因 >15MB 静默跳过：封面在 Isolate 内解码压缩（1.32 对齐 Android 降采样）
    return await coverDataUrlAsync(await pick.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// 目录的父目录路径（根/异常返回 null）
String? _parentDir(String dirPath) {
  final parts = dirPath.split(Platform.pathSeparator)..removeLast();
  if (parts.isEmpty) return null;
  final parent = parts.join(Platform.pathSeparator);
  return parent.isEmpty ? null : parent;
}

/// 按「第一首元数据」规则取专辑封面：从 TRACKNUMBER 排序后的首几条音轨提取内嵌封面。
/// 只对 TRACKNUMBER 最靠前（或未标号按文件名自然排序在前）的音轨尝试，前 3 首内首张存在即返回，
/// 避免极端序号的最后一轨内嵌图被误当封面；返回压缩后的 dataURL。
Future<String?> _firstEmbeddedCover(List<FileMeta> sorted) async {
  // 取排序最靠前的 ≤3 首；若本组不足 3 首则全量尝试
  final candidates = sorted.take(3).toList();
  for (final m in candidates) {
    final picBytes = await readEmbeddedPicture(m.path);
    if (picBytes != null && picBytes.isNotEmpty) {
      final cover = await coverDataUrlAsync(picBytes);
      if (cover != null) return cover;
    }
  }
  return null;
}

/// 标题清洗：替换换行；以换行/空白截断为单一标题，去掉多余空行与首尾空白。
/// 对齐旧版 sanityTitle：DLsite 的 TALB 标签常写入带重复/换行的冗长文本。
String _sanityTitle(String? title) {
  if (title == null) return '';
  final lines = title
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines.isEmpty ? title.trim() : lines.first;
}

/// 扫描根目录：文件级解析 + 混合分组 → 专辑列表。
/// [onProgress] 分两阶段实时回传（对齐 Android）：'files' 按文件计数，
/// 'albums' 按已组装专辑计数。
Future<List<Album>> scanPath(
  String rootPath, {
  void Function(int processed, int total, String phase)? onProgress,
}) async {
  final files = await collectFiles(rootPath);
  final audio = files.where((p) => audioExtensions.contains(_ext(p))).toList();
  if (audio.isEmpty) return [];

  // 并行多 Worker 分块解析：
  // 1. 每批增大至 40 首，大幅减少 isolate 跨线程调度开销；
  // 2. 根据 CPU 核心数启动并发 Worker (2..8 个并发)，多核全速吞吐。
  final concurrency = Platform.numberOfProcessors.clamp(2, 8);
  const batchSize = 40;
  final batches = <List<String>>[];
  for (var i = 0; i < audio.length; i += batchSize) {
    final end = i + batchSize > audio.length ? audio.length : i + batchSize;
    batches.add(audio.sublist(i, end));
  }

  var nextBatchIndex = 0;
  var processedFiles = 0;
  final allMetas = List<List<FileMeta?>>.filled(batches.length, const []);

  Future<void> worker() async {
    while (true) {
      int currentIdx;
      List<String> currentBatch;
      if (nextBatchIndex >= batches.length) return;
      currentIdx = nextBatchIndex++;
      currentBatch = batches[currentIdx];

      final results = await compute(parseBatch, ParseBatch(currentBatch));
      allMetas[currentIdx] = results;
      processedFiles += currentBatch.length;
      onProgress?.call(
        processedFiles.clamp(0, audio.length),
        audio.length,
        'files',
      );
    }
  }

  final workerCount = concurrency < batches.length ? concurrency : batches.length;
  await Future.wait(List.generate(workerCount, (_) => worker()));

  final metas = <FileMeta>[];
  for (final batchResults in allMetas) {
    metas.addAll(batchResults.whereType<FileMeta>());
  }

  // 无 ALBUM 标签曲目继承所在目录多数文件的专辑名（避免整张专辑被拆散）
  final byDir = <String, List<FileMeta>>{};
  for (final m in metas) {
    byDir.putIfAbsent(m.dirPath, () => []).add(m);
  }
  final directoryAlbums = <String, String?>{};
  for (final entry in byDir.entries) {
    directoryAlbums[entry.key] =
        mostCommon(entry.value.map((m) => m.album).toList());
  }

  // 聚合分组（保持首次出现顺序）；无标签曲目吸收进标签组
  final groups = <String, List<FileMeta>>{};
  for (final m in metas) {
    final inherited = m.album ?? directoryAlbums[m.dirPath];
    final meta = m.album == null && inherited != null
        ? FileMeta(
            path: m.path,
            dirPath: m.dirPath,
            dirName: m.dirName,
            title: m.title,
            artist: m.artist,
            albumArtist: m.albumArtist,
            album: inherited,
            trackNumber: m.trackNumber,
            duration: m.duration,
            cover: m.cover,
          )
        : m;
    groups.putIfAbsent(_groupKey(meta, directoryAlbums), () => []).add(meta);
  }

  final albums = <Album>[];
  final groupEntries = groups.entries.toList();
  for (var i = 0; i < groupEntries.length; i++) {
    final album = await _buildAlbum(groupEntries[i].key, groupEntries[i].value);
    if (album != null) {
      albums.add(album);
      onProgress?.call(albums.length, groupEntries.length, 'albums');
    }
  }
  return albums;
}

Future<Album?> _buildAlbum(String key, List<FileMeta> files) async {
  if (files.isEmpty) return null;
  // 排序：TRACKNUMBER 优先（缺失按文件名自然排序）
  final sorted = [...files]..sort((a, b) {
      final ta = a.trackNumber ?? 1 << 30;
      final tb = b.trackNumber ?? 1 << 30;
      if (ta != tb) return ta.compareTo(tb);
      return naturalCompare(_fileName(a.path), _fileName(b.path));
    });
  final isTagGroup = key.startsWith('tag:');
  final albumName = sorted
      .map((m) => m.album)
      .where((a) => a != null && a.trim().isNotEmpty && !looksGarbled(a))
      .firstOrNull;

  final rawTitle = isTagGroup
      ? (albumName ?? cleanFolderTitle(sorted.first.dirName))
      : cleanFolderTitle(sorted.first.dirName);
  final clean = _sanityTitle(rawTitle);
  final title = clean.isNotEmpty ? clean : '本地导入';
  // 艺术家取值链（1.43.0）：第一轨 TPE1（曲目艺术家/声优）→ 第一轨 TPE2
  // （专辑艺术家）→ 任何轨有效标签。修复解析库把 TPE2 优先映射进 artist、
  // 导致卡片显示社团而非声优的问题。
  bool tagOk(String? v) => v != null && v.trim().isNotEmpty && !looksGarbled(v);
  final first = sorted.first;
  final firstTpe1 = tagOk(first.artist) ? normalizeTag(first.artist!) : null;
  final firstTpe2 =
      tagOk(first.albumArtist) ? normalizeTag(first.albumArtist!) : null;
  final anyTpe1 =
      sorted.map((m) => tagOk(m.artist) ? normalizeTag(m.artist!) : null).firstOrNull;
  final anyTpe2 = sorted
      .map((m) => tagOk(m.albumArtist) ? normalizeTag(m.albumArtist!) : null)
      .firstOrNull;
  final artistValue = firstTpe1 ?? firstTpe2 ?? anyTpe1 ?? anyTpe2;
  // albumArtist 独立于 artist：取第一轨 TPE2，空则任何轨 TPE2
  final albumArtistValue = firstTpe2 ?? anyTpe2 ?? '';
  // 写库前规范化（去首尾空白/NUL）：标签里常见的尾随空格会让「同名艺术家」
  // 在按艺术家排序时被当成两个不同的人拆开
  final artist = artistValue ?? '本地导入';
  final albumArtist = albumArtistValue;
  final rjCode = extractRjCode([
    sorted.first.path,
    sorted.first.dirPath,
    title,
  ]);

  final tracks = <Track>[];
  var totalDuration = 0.0;
  for (var i = 0; i < sorted.length; i++) {
    final m = sorted[i];
    final fileName = _fileName(m.path);
    final stem = fileName.substring(0, _stemLength(fileName));
    final t = m.title;
    final name = (t != null && t.trim().isNotEmpty && !looksGarbled(t))
        ? t
        : (stem.isNotEmpty ? stem : 'Track ${i + 1}');
    tracks.add(Track(
      index: i,
      name: name,
      url: _toFileUrl(m.path),
      duration: m.duration,
    ));
    totalDuration += m.duration;
  }

  // 封面获取：按「专辑内第一首元数据」要求，优先取第一轨内嵌封面（DLsite 作品
  // 常把封面写进音频 APIC/内嵌图，外置图却常是曲目列表/角色介绍等功能图）。
  // 内嵌图失败才回退到外置图片（含父目录，DLsite 常见结构：封面在 RJ 目录、音频在其子目录）。
  var localCover = await _firstEmbeddedCover(sorted);
  if (localCover == null) {
    final dirs = <String>{
      ...sorted.map((m) => m.dirPath),
      ...sorted.map((m) => _parentDir(m.dirPath)).whereType<String>(),
    }.toList();
    localCover = await _groupDirCover(dirs);
  }

  final idValue = isTagGroup ? key : sorted.first.dirPath;
  return Album(
    id: 'local-${stableId(idValue)}',
    sourcePath: sorted.first.dirPath,
    title: title,
    artist: artist,
    albumArtist: albumArtist,
    rjCode: rjCode,
    group: '本地文件夹',
    genre: '未分类',
    duration: tracks.length,
    totalDuration: totalDuration,
    played: 0,
    favorite: false,
    date: DateTime.now(),
    tracks: tracks,
    localCover: localCover,
    color: const ['#c4b8e8', '#4b416c'],
    shape: 'radio',
    metaFromFolder: albumName == null, // 标题来自文件夹回退 → 待 DLsite 兜底
  );
}

int _stemLength(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name.length : dot;
}

/// 取出现最多的值（平局取最先出现者）
String? mostCommon(List<String?> values) {
  final counts = <String, int>{};
  String? best;
  var bestCount = 0;
  for (final v in values) {
    if (v == null || v.trim().isEmpty) continue;
    final c = (counts[v] ?? 0) + 1;
    counts[v] = c;
    if (c > bestCount) {
      best = v;
      bestCount = c;
    }
  }
  return best;
}
