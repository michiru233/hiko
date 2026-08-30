import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../utils/repair_text.dart';

/// 单曲元数据（桌面端，对应旧版 music-metadata 解析）
class TrackMetadata {
  final String? title;

  /// 曲目艺术家（MP3=TPE1 leadPerformer；其他格式=解析库的 artist）
  final String? artist;

  /// 专辑艺术家（MP3=TPE2 bandOrOrchestra；其他格式=null）
  final String? albumArtist;
  final String? album;
  final int? trackNumber; // TRACKNUMBER（排序用）
  final double duration; // 秒
  final Uint8List? picture;

  const TrackMetadata({
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.trackNumber,
    this.duration = 0,
    this.picture,
  });
}

/// 解析单曲元数据；[getImage] 默认 false（避免无谓解码每个音轨的内嵌大图）
/// 标签损坏/解析失败返回 null（容忍坏标签，文件仍可导入）
Future<TrackMetadata?> readTrackMetadata(
  String path, {
  bool getImage = false,
}) async {
  // MP3 走精确解析：泛型 AudioMetadata 会把 TPE2(专辑艺术家) 优先映射进 artist
  // （parser.dart: artist: bandOrOrchestra ?? leadPerformer），拿不到曲目艺术家。
  // MP3Parser 直接返回 Mp3Metadata，TPE1/TPE2 分离，且同样解析 MPEG 帧算时长。
  if (path.toLowerCase().endsWith('.mp3')) {
    final mp3 = _readMp3Metadata(path, getImage: getImage);
    if (mp3 != null) return mp3;
  }
  try {
    final meta = readMetadata(File(path), getImage: getImage);
    return TrackMetadata(
      title: repairText(meta.title),
      artist: repairText(meta.artist),
      album: repairText(meta.album),
      trackNumber: meta.trackNumber,
      duration: (meta.duration?.inMilliseconds ?? 0) / 1000.0,
      picture: meta.pictures.isNotEmpty ? meta.pictures.first.bytes : null,
    );
  } catch (_) {
    return null;
  }
}

/// MP3 精确解析（TPE1/TPE2 分离）；失败返回 null 由调用方回退泛型解析
TrackMetadata? _readMp3Metadata(String path, {bool getImage = false}) {
  RandomAccessFile? ra;
  try {
    ra = File(path).openSync();
    final m = MP3Parser(fetchImage: getImage).parse(ra);
    return TrackMetadata(
      title: repairText(m.songName),
      artist: repairText(m.leadPerformer),
      albumArtist: repairText(m.bandOrOrchestra),
      album: repairText(m.album),
      trackNumber: m.trackNumber,
      duration: (m.duration?.inMilliseconds ?? 0) / 1000.0,
      picture: m.pictures.isNotEmpty ? m.pictures.first.bytes : null,
    );
  } catch (_) {
    return null;
  } finally {
    ra?.closeSync();
  }
}

/// 针对单曲按需提取内嵌封面字节（单次调用）
Future<Uint8List?> readEmbeddedPicture(String path) async {
  try {
    final meta = readMetadata(File(path), getImage: true);
    if (meta.pictures.isNotEmpty) {
      return meta.pictures.first.bytes;
    }
  } catch (_) {}
  return null;
}
