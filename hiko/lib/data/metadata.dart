import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../utils/repair_text.dart';

/// 单曲元数据（桌面端，对应旧版 music-metadata 解析）
class TrackMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final double duration; // 秒
  final Uint8List? picture;

  const TrackMetadata({
    this.title,
    this.artist,
    this.album,
    this.duration = 0,
    this.picture,
  });
}

/// 解析单曲元数据；标签损坏/解析失败返回 null（容忍坏标签，文件仍可导入）
Future<TrackMetadata?> readTrackMetadata(String path) async {
  try {
    final meta = readMetadata(File(path), getImage: true);
    return TrackMetadata(
      title: repairText(meta.title),
      artist: repairText(meta.artist),
      album: repairText(meta.album),
      duration: (meta.duration?.inMilliseconds ?? 0) / 1000.0,
      picture: meta.pictures.isNotEmpty ? meta.pictures.first.bytes : null,
    );
  } catch (_) {
    return null;
  }
}
