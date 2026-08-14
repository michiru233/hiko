import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../utils/repair_text.dart';

/// 单曲元数据（桌面端，对应旧版 music-metadata 解析）
class TrackMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber; // TRACKNUMBER（排序用）
  final double duration; // 秒
  final Uint8List? picture;

  const TrackMetadata({
    this.title,
    this.artist,
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
