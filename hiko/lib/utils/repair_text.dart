import 'dart:convert';

import 'package:charset/charset.dart';

/// 修复非 UTF-8 标签的乱码（对应旧版 ImportScanner.repairText）：
/// 中文标签字节常被按 ISO-8859-1 解码成拉丁字符（你好 → ÄãºÃ），日文（Shift-JIS）同理。
/// 用 GBK（GB18030 常见范围）/ Shift_JIS 逐一还原并打分（假名 +3、汉字 +2、日文标点 +1），
/// 取分最高的结果；仅当得分 >0 才采纳，避免误伤正常 Latin-1 文本（如 Cafe）。
String? repairText(String? s) {
  if (s == null || s.trim().isEmpty) return s;
  if (hasCjkOrKana(s)) return s; // 已是正常中文/日文，无需修复
  if (!s.codeUnits.any((c) => c >= 0xA0 && c <= 0xFF)) return s; // 无 Latin-1 扩展字符

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
        if ((code >= 0x3040 && code <= 0x30FF) ||
            (code >= 0xFF61 && code <= 0xFF9F)) {
          score += 3; // 假名
        } else if (code >= 0x4E00 && code <= 0x9FFF) {
          score += 2; // 汉字
        } else if (code >= 0x3000 && code <= 0x303F) {
          score += 1; // 日文标点
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

/// 字符串是否仍像乱码（含 Latin-1 扩展字符但无中文/日文），用于回退到文件名
bool looksGarbled(String? s) {
  if (s == null || s.isEmpty) return false;
  final latinExt = s.codeUnits.where((c) => c >= 0xA0 && c <= 0xFF).length;
  final good = s.codeUnits
      .where((c) =>
          (c >= 0x4E00 && c <= 0x9FFF) ||
          (c >= 0x3040 && c <= 0x30FF) ||
          (c >= 0xFF61 && c <= 0xFF9F))
      .length;
  return latinExt > 0 && good == 0;
}
