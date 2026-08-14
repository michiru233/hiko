import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

bool _isAudioPath(String path) => audioExtensions.contains(_ext(path));
bool _isImagePath(String path) => imageExtensions.contains(_ext(path));

String _fileName(String path) => path.split(Platform.pathSeparator).last;
String _toFileUrl(String path) => Uri.file(path).toString();

/// sha1 前 16 位 hex（与旧版 stableId 同源）
String stableId(String value) =>
    sha1.convert(utf8.encode(value)).toString().substring(0, 16);

/// 递归收集目录下所有文件（跳过 . 开头条目），对应旧版 findFiles
Future<List<File>> findFiles(Directory dir) async {
  final entries = <FileSystemEntity>[];
  try {
    await for (final e in dir.list(followLinks: false)) {
      if (e.path.split(Platform.pathSeparator).last.startsWith('.')) continue;
      entries.add(e);
    }
  } catch (_) {
    return [];
  }
  final nested = <File>[];
  for (final e in entries) {
    if (e is Directory) {
      nested.addAll(await findFiles(e));
    } else if (e is File) {
      nested.add(e);
    }
  }
  return nested;
}

/// 单封面文件读取上限 15MB（内存峰值控制，对应旧版 Android readBytes）
Uint8List? _readBytes(File file) {
  try {
    if (file.lengthSync() > 15 * 1024 * 1024) return null;
    return file.readAsBytesSync();
  } catch (_) {
    return null;
  }
}

/// 文件夹封面：优先 (cover|front|folder|album|封面) 命名的图片，否则第一张图
String? selectFolderArtwork(List<File> files) {
  final images = files.where((f) => _isImagePath(f.path)).toList();
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
  final bytes = _readBytes(pick);
  return bytes == null ? null : coverDataUrl(bytes);
}

/// 取出现最多的值，平局取最先出现者（对应旧版 mostCommon）
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

/// 把「直接含文件的目录」聚合成专辑组（对应旧版 groupFilesByFolder）
Map<String, List<String>> groupFilesByFolder(List<String> files) {
  final groups = <String, List<String>>{};
  for (final file in files) {
    final dir = file.substring(0, file.lastIndexOf(Platform.pathSeparator));
    groups.putIfAbsent(dir, () => []).add(file);
  }
  return groups;
}

/// 扫描一张专辑（目录 + 其直接文件），无音频返回 null（对应旧版 scanAlbum）。
/// 设计为在 compute isolate 中运行：参数/返回值必须可跨 isolate 发送，
/// 故入参是 String 路径列表而非 File 对象。
Future<Album?> scanAlbum(String albumPath, List<String> filePaths) async {
  final audioPaths = filePaths.where(_isAudioPath).toList()
    ..sort((a, b) => naturalCompare(_fileName(a), _fileName(b)));
  if (audioPaths.isEmpty) return null;

  final albumNames = <String?>[];
  final artists = <String?>[];
  final tracks = <Track>[];
  var totalDuration = 0.0;
  String? embeddedCover;

  for (var index = 0; index < audioPaths.length; index++) {
    final filePath = audioPaths[index];
    final meta = await readTrackMetadata(filePath);
    if (meta != null) {
      albumNames.add(meta.album);
      artists.add(meta.artist);
      if (meta.picture != null && embeddedCover == null) {
        embeddedCover = coverDataUrl(meta.picture!);
      }
    }
    final baseName = _fileName(filePath);
    final stem = baseName.contains('.')
        ? baseName.substring(0, baseName.lastIndexOf('.'))
        : baseName;
    // 标题优先元数据（已做乱码还原），仍像乱码则回退文件名（文件名恒为正确 Unicode）
    var name = 'Track ${index + 1}';
    if (meta?.title != null && meta!.title!.trim().isNotEmpty) {
      name = looksGarbled(meta.title) ? stem : meta.title!;
    } else {
      name = stem;
    }
    final duration = meta?.duration ?? 0;
    // 轨道不携带独立封面：同一张内嵌封面存专辑级 embeddedCover 即可，
    // 避免 N 份 base64 重复撑爆 library.json（比旧版更省）
    tracks.add(Track(
      index: index,
      name: name,
      url: _toFileUrl(filePath),
      duration: duration,
    ));
    totalDuration += duration;
  }

  final folderName = _fileName(albumPath);
  // 专辑名优先元数据 ALBUM（已做乱码还原）；无 ALBUM 标签（DLsite 下载常见）时
  // 回退文件夹名并剥离 "RJxxxxxx_" 前缀，避免直接显示原始目录名
  final metaTitle = mostCommon(albumNames);
  final title = metaTitle != null && !looksGarbled(metaTitle)
      ? metaTitle
      : cleanFolderTitle(folderName) ?? '本地导入';
  final metaArtist = mostCommon(artists);
  final artist = metaArtist != null && !looksGarbled(metaArtist)
      ? metaArtist
      : '本地导入';
  final rjCode = extractRjCode([
    albumPath,
    folderName,
    audioPaths.isEmpty ? null : _fileName(audioPaths.first),
  ]);
  final localCover = embeddedCover ??
      selectFolderArtwork(filePaths.where(_isImagePath).map(File.new).toList());

  return Album(
    id: 'local-${stableId(albumPath)}',
    sourcePath: albumPath,
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

/// 递归扫描根目录（对应旧版 scanFolder + importAudioFolder 的预扫描）：
/// 返回 [根路径, 全部文件路径]；专辑分组与逐张扫描在调用方分批 compute。
Future<List<String>> collectFiles(String rootPath) async {
  final files = await findFiles(Directory(rootPath));
  return files.map((f) => f.path).toList();
}
