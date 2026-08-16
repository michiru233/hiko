import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/album.dart';
import '../models/track.dart';
import '../utils/natural_compare.dart';
import '../utils/repair_text.dart';
import 'models/lyric_line.dart';
import 'parsers/lrc_parser.dart';
import 'parsers/vtt_parser.dart';

/// 歌词解析与多编码扫描器
class LyricsResolver {
  static const lyricExtensions = {'.lrc', '.vtt', '.srt'};
  static const subfolderNames = {'lyrics', 'lyric', 'lrc', 'sub', 'subs', 'subtitles', 'vtt'};

  /// 为指定音轨和专辑解析歌词
  static Future<ParsedLyrics?> resolve(Track track, {Album? album}) async {
    final trackPath = _resolveLocalFilePath(track.url);
    if (trackPath == null) return null;

    final lyricFile = await _findSidecarFile(track, trackPath, album: album);
    if (lyricFile == null) return null;

    try {
      final bytes = await lyricFile.readAsBytes();
      final decodedText = decodeBytesSafely(bytes);
      if (decodedText == null || decodedText.trim().isEmpty) return null;

      final ext = p.extension(lyricFile.path).toLowerCase();
      if (ext == '.vtt' || ext == '.srt') {
        return VttParser.parse(decodedText, sourceFilePath: lyricFile.path);
      } else {
        return LrcParser.parse(decodedText, sourceFilePath: lyricFile.path);
      }
    } catch (e) {
      debugPrint('[LyricsResolver] 解析歌词失败 ${lyricFile.path}: $e');
      return null;
    }
  }

  /// 寻找同目录或子目录下的匹配歌词文件
  static Future<File?> _findSidecarFile(Track track, String trackPath, {Album? album}) async {
    final trackDir = Directory(p.dirname(trackPath));
    if (!await trackDir.exists()) return null;

    final trackStem = p.basenameWithoutExtension(trackPath);

    // 搜索目标目录：同级目录 + 常见字幕子目录
    final searchDirs = <Directory>[trackDir];
    try {
      await for (final entity in trackDir.list(followLinks: false)) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path).toLowerCase();
          if (subfolderNames.contains(dirName)) {
            searchDirs.add(entity);
          }
        }
      }
    } catch (_) {}

    // 优先级 1: 精确同名匹配 (e.g. 01.mp3 -> 01.lrc / 01.vtt)
    for (final dir in searchDirs) {
      for (final ext in lyricExtensions) {
        final directCandidate = File(p.join(dir.path, '$trackStem$ext'));
        if (await directCandidate.exists()) return directCandidate;

        // 大写扩展名检查 (.LRC, .VTT)
        final upperCandidate = File(p.join(dir.path, '$trackStem${ext.toUpperCase()}'));
        if (await upperCandidate.exists()) return upperCandidate;
      }
    }

    // 收集所有歌词文件
    final allLyricFiles = <File>[];
    for (final dir in searchDirs) {
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File && lyricExtensions.contains(p.extension(entity.path).toLowerCase())) {
            allLyricFiles.add(entity);
          }
        }
      } catch (_) {}
    }

    if (allLyricFiles.isEmpty) return null;

    // 优先级 2: 前缀音轨编号模糊匹配 (例如 "01. Intro.mp3" 匹配 "01.lrc" 或 "01 - 遭遇.lrc")
    final indexPrefix = RegExp(r'^(\d{1,3})');
    final trackMatch = indexPrefix.firstMatch(trackStem);
    if (trackMatch != null) {
      final trackNum = int.tryParse(trackMatch.group(1)!);
      for (final file in allLyricFiles) {
        final stem = p.basenameWithoutExtension(file.path);
        final fileMatch = indexPrefix.firstMatch(stem);
        if (fileMatch != null && int.tryParse(fileMatch.group(1)!) == trackNum) {
          return file;
        }
      }
    }

    // 优先级 3: 单曲专辑或歌词数量与音轨数量一致时，按自然序一一对应
    if (album != null && album.tracks.length == allLyricFiles.length) {
      allLyricFiles.sort((a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)));
      final trackIndex = album.tracks.indexWhere((t) => t.url == track.url);
      if (trackIndex >= 0 && trackIndex < allLyricFiles.length) {
        return allLyricFiles[trackIndex];
      }
    }

    // 优先级 4: 如果目录内仅有 1 个歌词文件且专辑仅 1 首歌
    if (allLyricFiles.length == 1 && (album == null || album.tracks.length == 1)) {
      return allLyricFiles.first;
    }

    return null;
  }

  /// 安全多编码探测还原：UTF-8 BOM -> 严格 UTF-8 -> Shift-JIS / GBK / EUC-JP 字符打分
  static String? decodeBytesSafely(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    // 1. BOM 标头探测
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _decodeUtf16BE(bytes.sublist(2));
      } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _decodeUtf16LE(bytes.sublist(2));
      }
    }

    // 2. 先尝试标准 UTF-8
    try {
      final utf8Candidate = utf8.decode(bytes, allowMalformed: false);
      if (!looksGarbled(utf8Candidate)) {
        return utf8Candidate;
      }
    } catch (_) {
      // 不是合法的 UTF-8，进入多编码候选评测
    }

    // 3. 候选字符集评分：Shift-JIS、GBK、EUC-JP、Latin-1
    final candidates = <Encoding>[shiftJis, gbk, eucJp, latin1];
    String? bestText;
    var bestScore = -1;

    for (final codec in candidates) {
      try {
        final decoded = codec.decode(bytes);
        final score = _evaluateTextQuality(decoded);
        if (score > bestScore) {
          bestScore = score;
          bestText = decoded;
        }
      } catch (_) {}
    }

    if (bestText != null && bestScore > 0) {
      return bestText;
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 评分依据：假名(+3)、汉字(+2)、日中标点符号(+1)
  static int _evaluateTextQuality(String text) {
    if (!isUsableText(text) || looksGarbled(text)) return -100;
    var score = 0;
    for (final code in text.codeUnits) {
      if (code >= 0x3040 && code <= 0x30FF) {
        score += 3; // 平假名 / 片假名
      } else if (code >= 0x4E00 && code <= 0x9FFF) {
        score += 2; // CJK 汉字
      } else if (code >= 0x3000 && code <= 0x303F || (code >= 0xFF61 && code <= 0xFF9F)) {
        score += 1; // 标点 / 半角假名
      }
    }
    return score;
  }

  static String _decodeUtf16LE(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length - 1; i += 2) {
      buffer.writeCharCode(bytes[i] | (bytes[i + 1] << 8));
    }
    return buffer.toString();
  }

  static String _decodeUtf16BE(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length - 1; i += 2) {
      buffer.writeCharCode((bytes[i] << 8) | bytes[i + 1]);
    }
    return buffer.toString();
  }

  static String? _resolveLocalFilePath(String url) {
    if (url.startsWith('file://')) {
      try {
        return Uri.parse(url).toFilePath();
      } catch (_) {
        return null;
      }
    }
    if (url.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(url)) {
      return url;
    }
    return null;
  }
}
