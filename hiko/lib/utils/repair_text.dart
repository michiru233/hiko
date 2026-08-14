import 'dart:convert';

import 'package:charset/charset.dart';

/// 修复非 UTF-8 标签的乱码（对应旧版 ImportScanner.repairText）：
/// 中文标签字节常被按 ISO-8859-1 解码成拉丁字符（你好 → ÄãºÃ），日文（Shift-JIS）同理。
/// 用 GBK（GB18030 常见范围）/ Shift_JIS 逐一还原并打分（假名 +3、汉字 +2、日文标点 +1），
/// 取分最高的结果；仅当得分 >0 才采纳，避免误伤正常 Latin-1 文本（如 Cafe）。
String? repairText(String? s) {
  if (s == null || s.trim().isEmpty) return s;
  if (hasCjkOrKana(s)) return s; // 已是正常中文/日文，无需修复
  // 含 0x80-0xFF（含 C1 控制区）——Shift-JIS/GBK 双字节高位大量落在 0x80-0x9F
  if (!s.codeUnits.any((c) => c >= 0x80 && c <= 0xFF)) return s;

  final List<int> bytes;
  try {
    bytes = latin1.encode(s);
  } catch (_) {
    return s; // 含 Latin-1 范围外的字符，非可还原的乱码特征
  }

  var best = '';
  var bestScore = 0;
  for (final codec in _candidates) {
    try {
      final candidate = codec.decode(bytes);      var score = 0;
      for (final code in candidate.codeUnits) {
        if (code >= 0x3040 && code <= 0x30FF) {
          score += 3; // 全角假名
        } else if (code >= 0x4E00 && code <= 0x9FFF) {
          score += 2; // 汉字
        } else if (code >= 0x3000 && code <= 0x303F ||
            (code >= 0xFF61 && code <= 0xFF9F)) {
          score += 1; // 日文标点 / 半角假名（GBK 字节常被误解，权重降低）
        }
      }
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    } catch (_) {}
  }
  return bestScore > 0 ? best : s;
}

/// 字符集候选：GBK 覆盖 GB18030 的 CJK 常见范围；Shift_JIS 覆盖日文
final _candidates = <Encoding>[gbk, shiftJis, eucJp];

/// 文本是否含 CJK 汉字/日文假名（视为正常文本，非乱码）
bool hasCjkOrKana(String s) => s.codeUnits.any((code) =>
    (code >= 0x4E00 && code <= 0x9FFF) ||
    (code >= 0x3040 && code <= 0x30FF) ||
    (code >= 0xFF61 && code <= 0xFF9F));

/// 文本是否可用（对齐 Android Id3v2Parser.isUsableText）：
/// 空、替换字符、控制字符、密集问号（2 个以上且占比 ≥1/3 或连续）视为不可用，
/// 调用方回退文件名/文件夹。
bool isUsableText(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  if (value.contains('\uFFFD') ||
      value.codeUnits.any((c) =>
          c <= 0x08 || (c >= 0x0E && c <= 0x1F) || (c >= 0x7F && c <= 0x9F))) {
    return false;
  }
  final questionCount =
      value.split('').where((ch) => ch == '?' || ch == '？').length;
  if (questionCount >= 2 &&
      (questionCount * 3 >= value.length ||
          value.contains('??') ||
          value.contains('？？'))) {
    return false;
  }
  return true;
}

/// 字符串是否仍像乱码（对齐 Android ImportScanner.looksGarbled）：
/// 不可用文本直接视为乱码；再查 UTF-8 被按 Latin-1 解码的典型 mojibake 标记
/// （Ã/Â/ã€/æ—/å¤/ï¿½ 等）。合法重音 Latin 文本（如 Café）不再仅因含高位字符被误判。
bool looksGarbled(String? s) {
  if (s == null || s.trim().isEmpty) return false;
  if (!isUsableText(s)) return true;
  const mojibakeMarkers = ['Ã', 'Â', 'ã€', 'ãƒ', 'ã‚', 'æ—', 'å¤', 'ï¿½'];
  return mojibakeMarkers.any(s.contains);
}
