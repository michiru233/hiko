import 'package:flutter/foundation.dart';

/// 表示单行歌词或台词片段
@immutable
class LyricLine implements Comparable<LyricLine> {
  /// 起始时间戳
  final Duration startTime;

  /// 结束时间戳（可选，VTT 直接提供，LRC 自动计算至下一句开始）
  final Duration? endTime;

  /// 歌词/台词纯文本
  final String text;

  /// 说话人/声优角色名（例如从 VTT `<v Alice>` 或 LRC `【角色】:` 提取）
  final String? speaker;

  /// 翻译行（可选）
  final String? translation;

  const LyricLine({
    required this.startTime,
    this.endTime,
    required this.text,
    this.speaker,
    this.translation,
  });

  /// 判断当前播放时间是否在这一行的时间区间内
  bool isActive(Duration position) {
    if (position < startTime) return false;
    if (endTime != null && position >= endTime!) return false;
    return true;
  }

  LyricLine copyWith({
    Duration? startTime,
    Duration? endTime,
    String? text,
    String? speaker,
    String? translation,
  }) {
    return LyricLine(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      speaker: speaker ?? this.speaker,
      translation: translation ?? this.translation,
    );
  }

  @override
  int compareTo(LyricLine other) => startTime.compareTo(other.startTime);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine &&
          runtimeType == other.runtimeType &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          text == other.text &&
          speaker == other.speaker &&
          translation == other.translation;

  @override
  int get hashCode => Object.hash(startTime, endTime, text, speaker, translation);

  @override
  String toString() =>
      'LyricLine(${startTime.inMilliseconds}ms -> ${endTime?.inMilliseconds}ms, speaker: $speaker, text: "$text")';
}

/// 解析后的整篇歌词文档
@immutable
class ParsedLyrics {
  final List<LyricLine> lines;
  final String? title;
  final String? artist;
  final String? album;
  final String? by;
  final int offsetMs;
  final String? sourceFilePath;
  final String? format; // 'lrc' | 'vtt' | 'srt'

  const ParsedLyrics({
    this.lines = const [],
    this.title,
    this.artist,
    this.album,
    this.by,
    this.offsetMs = 0,
    this.sourceFilePath,
    this.format,
  });

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  static const empty = ParsedLyrics();
}
