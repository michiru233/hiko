import '../models/lyric_line.dart';

/// LRC 歌词解析器
/// 支持标准时间戳、多时间戳行、[offset:+/-ms] 偏移量、说话人前缀提取
class LrcParser {
  // 元数据标签：[ar:歌手], [ti:歌名], [al:专辑], [by:制作], [offset:500] 等
  static final _tagRegex = RegExp(r'^\[([a-zA-Z]+):([^\]]*)\]$');

  // 时间戳格式：[01:23.45] / [01:23.456] / [00:01:23.45]
  static final _timestampRegex = RegExp(
    r'\[(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]',
  );

  // 说话人前缀提取：[speaker:角色] / 【角色】 / 角色:
  static final _speakerPrefixRegex = RegExp(
    r'^(?:\[speaker:([^\]]+)\]|【([^】]+)】|([^\s:：]{1,12})[:：])\s*(.*)$',
  );

  static ParsedLyrics parse(String content, {String? sourceFilePath}) {
    if (content.trim().isEmpty) return ParsedLyrics.empty;

    final lines = content.split(RegExp(r'\r?\n'));
    final rawEntries = <({Duration time, String text, String? speaker})>[];

    String? title;
    String? artist;
    String? album;
    String? by;
    int offsetMs = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // 1. 检查元数据标签
      final tagMatch = _tagRegex.firstMatch(line);
      if (tagMatch != null) {
        final key = tagMatch.group(1)!.toLowerCase();
        final value = tagMatch.group(2)!.trim();
        switch (key) {
          case 'ti':
            title = value;
            break;
          case 'ar':
            artist = value;
            break;
          case 'al':
            album = value;
            break;
          case 'by':
            by = value;
            break;
          case 'offset':
            offsetMs = int.tryParse(value) ?? 0;
            break;
        }
        continue;
      }

      // 2. 提取同一行开头的全部时间戳（支持多时间戳 [00:10.00][00:25.00]台词）
      final matches = _timestampRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // 歌词正文在最后一个时间戳后面
      final textStart = matches.last.end;
      var text = line.substring(textStart).trim();

      // 提取可选说话人
      String? speaker;
      final speakerMatch = _speakerPrefixRegex.firstMatch(text);
      if (speakerMatch != null) {
        speaker = speakerMatch.group(1) ?? speakerMatch.group(2) ?? speakerMatch.group(3);
        text = (speakerMatch.group(4) ?? text).trim();
      }

      // 3. 为每个时间戳生成一行记录
      for (final match in matches) {
        final time = _parseTimestamp(
          hoursStr: match.group(1),
          minutesStr: match.group(2)!,
          secondsStr: match.group(3)!,
          fractionStr: match.group(4),
          offsetMs: offsetMs,
        );

        rawEntries.add((time: time, text: text, speaker: speaker));
      }
    }

    if (rawEntries.isEmpty) {
      return ParsedLyrics(
        lines: const [],
        title: title,
        artist: artist,
        album: album,
        by: by,
        offsetMs: offsetMs,
        sourceFilePath: sourceFilePath,
        format: 'lrc',
      );
    }

    // 4. 按时间升序排序
    rawEntries.sort((a, b) => a.time.compareTo(b.time));

    // 5. 生成 LyricLine 并计算每句的 endTime（下一句的 startTime）
    final parsedLines = <LyricLine>[];
    for (var i = 0; i < rawEntries.length; i++) {
      final current = rawEntries[i];
      Duration? endTime;

      if (i + 1 < rawEntries.length) {
        endTime = rawEntries[i + 1].time;
      }

      parsedLines.add(LyricLine(
        startTime: current.time,
        endTime: endTime,
        text: current.text,
        speaker: current.speaker,
      ));
    }

    return ParsedLyrics(
      lines: parsedLines,
      title: title,
      artist: artist,
      album: album,
      by: by,
      offsetMs: offsetMs,
      sourceFilePath: sourceFilePath,
      format: 'lrc',
    );
  }

  static Duration _parseTimestamp({
    String? hoursStr,
    required String minutesStr,
    required String secondsStr,
    String? fractionStr,
    required int offsetMs,
  }) {
    final hours = hoursStr != null ? int.parse(hoursStr) : 0;
    final minutes = int.parse(minutesStr);
    final seconds = int.parse(secondsStr);

    var millis = 0;
    if (fractionStr != null) {
      if (fractionStr.length == 1) {
        millis = int.parse(fractionStr) * 100;
      } else if (fractionStr.length == 2) {
        millis = int.parse(fractionStr) * 10;
      } else {
        millis = int.parse(fractionStr.substring(0, 3));
      }
    }

    var totalMs = (hours * 3600 + minutes * 60 + seconds) * 1000 + millis + offsetMs;
    if (totalMs < 0) totalMs = 0;

    return Duration(milliseconds: totalMs);
  }
}
