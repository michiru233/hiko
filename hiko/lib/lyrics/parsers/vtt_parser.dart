import '../models/lyric_line.dart';

/// WebVTT / SRT 字幕解析器
/// 支持时间区间 (00:01.000 --> 00:04.500 或 00:00:01.000)、<v 角色名> 说话人标签提取与样式清洗
class VttParser {
  static final _arrowRegex = RegExp(r'-->');
  static final _timeRegex = RegExp(
    r'(?:(\d{1,2}):)?(\d{2}):(\d{2})(?:[.,](\d{3}))?',
  );

  // 匹配 <v 说话人> 或 <v.class 说话人>
  static final _voiceTagRegex = RegExp(r'<v(?:\.[\w-]+)?\s+([^>]+)>(.*?)(?:<\/v>|$)', dotAll: true);

  // 匹配所有其它 HTML/VTT 标签 <b>, <i>, <c.color>, <ruby>, 时间标签等
  static final _tagStripRegex = RegExp(r'<\/?[^>]+>');

  static ParsedLyrics parse(String content, {String? sourceFilePath}) {
    if (content.trim().isEmpty) return ParsedLyrics.empty;

    final lines = content.split(RegExp(r'\r?\n'));
    final parsedLines = <LyricLine>[];

    var i = 0;
    // 跳过 WEBVTT 头部和空行
    while (i < lines.length && (lines[i].trim().isEmpty || lines[i].startsWith('WEBVTT'))) {
      i++;
    }

    while (i < lines.length) {
      final line = lines[i].trim();

      // 跳过空行及 NOTE / STYLE / REGION 块
      if (line.isEmpty) {
        i++;
        continue;
      }
      if (line.startsWith('NOTE') || line.startsWith('STYLE') || line.startsWith('REGION')) {
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          i++;
        }
        continue;
      }

      // 判断当前行是否包含时间戳区间，或者下一行是时间戳（当前行是序号）
      String? timingLine;
      if (line.contains(_arrowRegex)) {
        timingLine = line;
      } else if (i + 1 < lines.length && lines[i + 1].contains(_arrowRegex)) {
        i++;
        timingLine = lines[i].trim();
      }

      if (timingLine == null) {
        i++;
        continue;
      }

      final parts = timingLine.split(_arrowRegex);
      if (parts.length != 2) {
        i++;
        continue;
      }

      final startDuration = _parseVttTimestamp(parts[0].trim());
      final endDuration = _parseVttTimestamp(parts[1].trim().split(' ').first);

      if (startDuration == null) {
        i++;
        continue;
      }

      // 读取正文行
      i++;
      final payloadBuffer = StringBuffer();
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        if (payloadBuffer.isNotEmpty) payloadBuffer.write('\n');
        payloadBuffer.write(lines[i].trim());
        i++;
      }

      final rawPayload = payloadBuffer.toString();
      if (rawPayload.isEmpty) continue;

      final (:text, :speaker) = _sanitizePayload(rawPayload);

      parsedLines.add(LyricLine(
        startTime: startDuration,
        endTime: endDuration,
        text: text,
        speaker: speaker,
      ));
    }

    parsedLines.sort((a, b) => a.startTime.compareTo(b.startTime));

    return ParsedLyrics(
      lines: parsedLines,
      sourceFilePath: sourceFilePath,
      format: 'vtt',
    );
  }

  static Duration? _parseVttTimestamp(String input) {
    final match = _timeRegex.firstMatch(input);
    if (match == null) return null;

    final hours = match.group(1) != null ? int.parse(match.group(1)!) : 0;
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final millis = match.group(4) != null ? int.parse(match.group(4)!) : 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  static ({String text, String? speaker}) _sanitizePayload(String raw) {
    String? speaker;
    var text = raw;

    // 1. 提取 <v 说话人> 标签
    final voiceMatch = _voiceTagRegex.firstMatch(text);
    if (voiceMatch != null) {
      speaker = voiceMatch.group(1)?.trim();
      text = text.replaceAllMapped(_voiceTagRegex, (m) => m.group(2) ?? '');
    }

    // 2. 剥离样式与残留标签
    text = text.replaceAll(_tagStripRegex, '');

    // 3. 还原 HTML 实体转义
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();

    return (text: text, speaker: speaker);
  }
}
