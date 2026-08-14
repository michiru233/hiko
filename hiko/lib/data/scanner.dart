import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
Future<List<String>> collectFiles(String rootPath) async {
  final out = <String>[];
  Future<void> walk(String dirPath) async {
    try {
      await for (final e in Directory(dirPath).list(followLinks: false)) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          await walk(e.path);
        } else if (e is File) {
          out.add(e.path);
        }
      }
    } catch (_) {}
  }

  await walk(rootPath);
  return out;
}

/// 单文件解析结果（跨 isolate 可序列化）
class FileMeta {
  final String path;
  final String dirPath;
  final String dirName;
  final String? title;
  final String? artist;
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

/// compute 入口：批量解析元数据（单文件失败返回 null 容错）
Future<List<FileMeta?>> parseBatch(ParseBatch job) async {
  return Future.wait(job.paths.map((p) async {
    final meta = await readTrackMetadata(p);
    if (meta == null) return null;
    final dirPath = p.substring(0, p.lastIndexOf(Platform.pathSeparator));
    return FileMeta(
      path: p,
      dirPath: dirPath,
      dirName: _fileName(dirPath),
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      trackNumber: meta.trackNumber,
      duration: meta.duration,
      cover: meta.picture == null ? null : coverDataUrl(meta.picture!),
    );
  }));
}

/// 混合分组键：有 ALBUM 标签 → 按专辑聚合；无标签 → 按文件夹
String _groupKey(FileMeta m) {
  final album = m.album;
  final hasAlbum = album != null && album.trim().isNotEmpty && !looksGarbled(album);
  return hasAlbum ? 'tag:|$album' : 'dir:${m.dirPath}';
}

/// 文件夹封面（按目录聚合图片文件，压缩后 dataURL）
Future<String?> _dirCover(String dirPath) async {
  try {
    final images = <File>[];
    await for (final e in Directory(dirPath).list(followLinks: false)) {
      if (e is File && imageExtensions.contains(_ext(e.path))) {
        images.add(e);
      }
    }
    File? pick;
    for (final f in images) {
      if (RegExp(r'cover|front|folder|album|封面', caseSensitive: false)
          .hasMatch(_fileName(f.path))) {
        pick = f;
        break;
      }
    }
    pick ??= images.isEmpty ? null : images.first;
    if (pick == null) return null;
    if (await pick.length() > 15 * 1024 * 1024) return null;
    return coverDataUrl(await pick.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// 扫描根目录：文件级解析 + 混合分组 → 专辑列表
Future<List<Album>> scanPath(String rootPath) async {
  final files = await collectFiles(rootPath);
  final audio = files.where((p) => audioExtensions.contains(_ext(p))).toList();

  // 分批 compute 解析（每批 10 个文件，避免 isolate 开销过大）
  const batchSize = 10;
  final metas = <FileMeta>[];
  for (var i = 0; i < audio.length; i += batchSize) {
    final end = i + batchSize > audio.length ? audio.length : i + batchSize;
    final batch = audio.sublist(i, end);
    final results = await compute(parseBatch, ParseBatch(batch));
    metas.addAll(results.whereType<FileMeta>());
  }

  // 聚合分组（保持首次出现顺序）
  final groups = <String, List<FileMeta>>{};
  for (final m in metas) {
    groups.putIfAbsent(_groupKey(m), () => []).add(m);
  }

  final albums = <Album>[];
  for (final entry in groups.entries) {
    final album = await _buildAlbum(entry.key, entry.value);
    if (album != null) albums.add(album);
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

  final title = isTagGroup
      ? (albumName ?? cleanFolderTitle(sorted.first.dirName) ?? '本地导入')
      : (cleanFolderTitle(sorted.first.dirName) ?? '本地导入');
  final artistValue = mostCommon(sorted.map((m) => m.artist).toList());
  final artist = (artistValue != null && !looksGarbled(artistValue))
      ? artistValue
      : '本地导入';
  final rjCode = extractRjCode([
    sorted.first.path,
    sorted.first.dirPath,
    title,
  ]);

  String? embeddedCover;
  final tracks = <Track>[];
  var totalDuration = 0.0;
  for (var i = 0; i < sorted.length; i++) {
    final m = sorted[i];
    embeddedCover ??= m.cover;
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
  var localCover = embeddedCover;
  if (localCover == null && !isTagGroup) {
    localCover = await _dirCover(sorted.first.dirPath);
  }

  final idValue = isTagGroup ? key : sorted.first.dirPath;
  return Album(
    id: 'local-${stableId(idValue)}',
    sourcePath: sorted.first.dirPath,
    title: title,
    artist: artist,
    albumArtist: '',
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
