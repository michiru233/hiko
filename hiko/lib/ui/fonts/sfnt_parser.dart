/// sfnt 容器解析（TrueType / OpenType）。
///
/// 只做两件事，别的一概不碰：
/// 1. 从 `name` 表取**族名**（导入列表要显示「思源宋体 CN」而不是文件名）；
/// 2. 用 `cmap` 的**固定探针码位**判断是否覆盖日文假名/常用汉字（导入时提示用）。
///
/// 为什么手写而不加依赖：要的只是两张表里的几十个字节，引一个字体库会把
/// 整个 `cmap` 展开成几十万条映射，导入一个 20MB 的 CJK 字体就够卡住主线程。
/// 这里只对探针做二分/线性查找，内存恒定为 0。
///
/// **所有读取都走 bounds-check**：字体文件来自用户，任何越界都当作
/// 「不是合法字体」处理，绝不抛异常（[parseSfnt] 的返回值里带错误码）。
library;

import 'dart:typed_data';

/// 解析失败的原因（用于给用户可读文案）。
enum SfntError {
  /// 前 4 字节不像 sfnt。
  notSfnt,

  /// `.ttc` 字体集合：一个文件多套字体，Flutter 的 FontLoader 支持有限。
  collection,

  /// `.woff` / `.woff2`：Web 压缩字体，引擎不认。
  woff,

  /// 文件被截断或表目录损坏。
  truncated,

  /// 找不到 `name` 表（取不到族名）。
  noName,

  /// 找不到可用的 `cmap` 表。
  noCmap,
}

/// 解析结果。
class SfntInfo {
  const SfntInfo({
    required this.family,
    required this.hasJapanese,
    required this.kanaHits,
    required this.kanjiHits,
    required this.variable,
    required this.flavor,
  });

  /// name 表里的族名；读不到时是 null（调用方回退文件名）。
  final String? family;

  /// 假名命中 ≥16/20，认为这个字体能显示日文。
  final bool hasJapanese;

  final int kanaHits;
  final int kanjiHits;

  /// 含 `fvar` 表（可变字体）。字重是否生效看平台，UI 只做提示。
  final bool variable;

  /// 'ttf' / 'otf'，用于落盘扩展名。
  final String flavor;
}

class SfntParseResult {
  const SfntParseResult._(this.info, this.error);

  factory SfntParseResult.ok(SfntInfo info) => SfntParseResult._(info, null);

  factory SfntParseResult.fail(SfntError error) =>
      SfntParseResult._(null, error);

  final SfntInfo? info;
  final SfntError? error;

  bool get isOk => info != null;
}

/// 日文探针：20 个平假名 + 20 个常用汉字（含「音」重复位补「漢」）。
const List<int> _kanaProbes = <int>[
  0x3042, 0x3044, 0x3046, 0x3048, 0x304A, // あいうえお
  0x304B, 0x304D, 0x304F, 0x3051, 0x3053, // かきくけこ
  0x30A2, 0x30A4, 0x30A6, 0x30A8, 0x30AA, // アイウエオ
  0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3, // カキクケコ
];

const List<int> _kanjiProbes = <int>[
  0x65E5, 0x672C, 0x8A9E, 0x6587, 0x5B57, // 日本語文字
  0x97F3, 0x697D, 0x66F2, 0x540D, 0x6B4C, // 音楽曲名歌
  0x624B, 0x6642, 0x9593, 0x518D, 0x751F, // 手時間再生
  0x8A2D, 0x5B9A, 0x58F0, 0x6F22, 0x97FF, // 設定声漢響
];

/// 解析字体字节流。**永不抛异常**。
SfntParseResult parseSfnt(Uint8List bytes) {
  if (bytes.length < 12) return SfntParseResult.fail(SfntError.notSfnt);
  final head = _u32(bytes, 0);
  if (head == 0x74746366) return SfntParseResult.fail(SfntError.collection);
  if (head == 0x774F4646 || head == 0x774F4632) {
    return SfntParseResult.fail(SfntError.woff);
  }
  final isOtto = head == 0x4F54544F; // 'OTTO'
  final isTrue = head == 0x74727565; // 'true'
  final isTyp1 = head == 0x74797031; // 'typ1'
  if (head != 0x00010000 && !isOtto && !isTrue && !isTyp1) {
    return SfntParseResult.fail(SfntError.notSfnt);
  }

  final numTables = _u16(bytes, 4);
  if (numTables == 0 || numTables > 4096) {
    return SfntParseResult.fail(SfntError.truncated);
  }
  final dirStart = 12;
  final dirEnd = dirStart + numTables * 16;
  if (dirEnd > bytes.length) {
    return SfntParseResult.fail(SfntError.truncated);
  }

  final tables = <String, (int offset, int length)>{};
  for (var i = 0; i < numTables; i++) {
    final rec = dirStart + i * 16;
    final tag = String.fromCharCodes(bytes, rec, rec + 4);
    final offset = _u32(bytes, rec + 8);
    final length = _u32(bytes, rec + 12);
    if (offset < 0 || length < 0 || offset + length > bytes.length) {
      return SfntParseResult.fail(SfntError.truncated);
    }
    tables[tag] = (offset, length);
  }

  final nameTable = tables['name'];
  if (nameTable == null) return SfntParseResult.fail(SfntError.noName);
  final family = _readFamilyName(bytes, nameTable.$1, nameTable.$2);

  final cmapTable = tables['cmap'];
  if (cmapTable == null) return SfntParseResult.fail(SfntError.noCmap);
  final subtable = _pickCmapSubtable(bytes, cmapTable.$1, cmapTable.$2);
  if (subtable == null) return SfntParseResult.fail(SfntError.noCmap);

  var kana = 0;
  for (final cp in _kanaProbes) {
    if (_cmapCovers(bytes, subtable.$1, subtable.$2, cp)) kana++;
  }
  var kanji = 0;
  for (final cp in _kanjiProbes) {
    if (_cmapCovers(bytes, subtable.$1, subtable.$2, cp)) kanji++;
  }

  return SfntParseResult.ok(
    SfntInfo(
      family: family,
      hasJapanese: kana >= 16,
      kanaHits: kana,
      kanjiHits: kanji,
      variable: tables.containsKey('fvar'),
      flavor: isOtto ? 'otf' : 'ttf',
    ),
  );
}

/// 给用户看的错误文案。
String describeSfntError(SfntError error) => switch (error) {
  SfntError.notSfnt => '这不是一个字体文件',
  SfntError.collection => '不支持字体集合（.ttc），请选单个 .ttf / .otf',
  SfntError.woff => '不支持 Web 字体（.woff / .woff2）',
  SfntError.truncated => '字体文件损坏或不完整',
  SfntError.noName => '字体缺少名称表，无法读取字体名',
  SfntError.noCmap => '字体缺少字符映射表，无法使用',
};

// ---------------------------------------------------------------------------
// 底层读取（全部 bounds-check）
// ---------------------------------------------------------------------------

int _u8(Uint8List b, int o) => b[o];

int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

int _s16(Uint8List b, int o) {
  final v = _u16(b, o);
  return v >= 0x8000 ? v - 0x10000 : v;
}

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

bool _fits(Uint8List b, int offset, int length) =>
    offset >= 0 && length >= 0 && offset + length <= b.length;

// ---------------------------------------------------------------------------
// name 表
// ---------------------------------------------------------------------------

/// 记录打分：族名优先 nameID 1，其次 16（typographic），最后 4（full name）；
/// 平台优先 Windows/Unicode（UTF-16BE），其次 Mac。
int _nameScore(int platformId, int languageId, int nameId) {
  final nameScore = switch (nameId) {
    1 => 30,
    16 => 20,
    4 => 10,
    _ => 0,
  };
  if (nameScore == 0) return 0;
  final platformScore = switch (platformId) {
    3 => languageId == 0x0409 ? 10 : 8,
    0 => 9,
    1 => 5,
    _ => 1,
  };
  return nameScore + platformScore;
}

String? _readFamilyName(Uint8List bytes, int tableOffset, int tableLength) {
  if (!_fits(bytes, tableOffset, 6)) return null;
  final count = _u16(bytes, tableOffset + 2);
  final stringOffset = _u16(bytes, tableOffset + 4);
  if (count == 0 || count > 4096) return null;
  if (!_fits(bytes, tableOffset + 6, count * 12)) return null;

  var bestScore = 0;
  String? best;
  for (var i = 0; i < count; i++) {
    final rec = tableOffset + 6 + i * 12;
    final platformId = _u16(bytes, rec);
    final languageId = _u16(bytes, rec + 4);
    final nameId = _u16(bytes, rec + 6);
    final length = _u16(bytes, rec + 8);
    final offset = _u16(bytes, rec + 10);
    if (length == 0) continue;
    final score = _nameScore(platformId, languageId, nameId);
    if (score <= bestScore) continue;

    final start = tableOffset + stringOffset + offset;
    if (!_fits(bytes, start, length)) continue;
    // Windows/Unicode 平台是 UTF-16BE；Mac 平台按字节直读（MacRoman 的
    // 非 ASCII 部分会略微失真，但只在没有 Windows 记录时才走到）。
    final raw = platformId == 3 || platformId == 0
        ? _decodeUtf16Be(bytes, start, length)
        : String.fromCharCodes(bytes, start, start + length);
    final cleaned = _cleanName(raw);
    if (cleaned.isEmpty) continue;
    bestScore = score;
    best = cleaned;
  }
  return best;
}

String _decodeUtf16Be(Uint8List bytes, int start, int length) {
  final units = <int>[];
  for (var i = 0; i + 1 < length; i += 2) {
    units.add((bytes[start + i] << 8) | bytes[start + i + 1]);
  }
  return String.fromCharCodes(units);
}

/// 去掉 NUL / 控制字符，折叠空白，限长 64（防止畸形字体塞超长字符串）。
String _cleanName(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    if (rune == 0 || rune < 0x20) continue;
    if (rune == 0x7F) continue;
    buffer.writeCharCode(rune);
  }
  final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > 64 ? text.substring(0, 64) : text;
}

// ---------------------------------------------------------------------------
// cmap 表
// ---------------------------------------------------------------------------

/// 返回 (subtable 绝对偏移, format)。优先 format 12（能覆盖增补面），
/// 其次 format 4（BMP），再次 6 / 0。
(int offset, int format)? _pickCmapSubtable(
  Uint8List bytes,
  int tableOffset,
  int tableLength,
) {
  if (!_fits(bytes, tableOffset, 4)) return null;
  final count = _u16(bytes, tableOffset + 2);
  if (count == 0 || count > 1024) return null;
  if (!_fits(bytes, tableOffset + 4, count * 8)) return null;

  (int, int)? best;
  var bestScore = 0;
  for (var i = 0; i < count; i++) {
    final rec = tableOffset + 4 + i * 8;
    final platformId = _u16(bytes, rec);
    final encodingId = _u16(bytes, rec + 2);
    final offset = _u32(bytes, rec + 4);
    final sub = tableOffset + offset;
    if (!_fits(bytes, sub, 4)) continue;
    final format = _u16(bytes, sub);
    if (format != 4 && format != 12 && format != 6 && format != 0) continue;
    final score =
        switch (format) {
          12 => 40,
          4 => 30,
          6 => 20,
          _ => 10,
        } +
        switch ((platformId, encodingId)) {
          (3, 10) => 5,
          (3, 1) => 4,
          (0, _) => 3,
          _ => 0,
        };
    if (score <= bestScore) continue;
    bestScore = score;
    best = (sub, format);
  }
  return best;
}

/// 指定码位是否有字形（glyphId != 0）。
bool _cmapCovers(Uint8List bytes, int sub, int format, int cp) {
  try {
    return switch (format) {
      0 => _coversFormat0(bytes, sub, cp),
      4 => _coversFormat4(bytes, sub, cp),
      6 => _coversFormat6(bytes, sub, cp),
      12 => _coversFormat12(bytes, sub, cp),
      _ => false,
    };
  } catch (_) {
    // 畸形表（越界/数组长度不合法）一律当「不覆盖」，不影响导入
    return false;
  }
}

bool _coversFormat0(Uint8List bytes, int sub, int cp) {
  if (cp < 0 || cp > 0xFF) return false;
  if (!_fits(bytes, sub + 6, 256)) return false;
  return _u8(bytes, sub + 6 + cp) != 0;
}

bool _coversFormat4(Uint8List bytes, int sub, int cp) {
  if (cp < 0 || cp > 0xFFFF) return false;
  if (!_fits(bytes, sub, 14)) return false;
  final segCountX2 = _u16(bytes, sub + 6);
  if (segCountX2 == 0 || segCountX2.isOdd) return false;
  final segCount = segCountX2 ~/ 2;
  final endBase = sub + 14;
  final startBase = endBase + segCountX2 + 2; // 跳过 reservedPad
  final deltaBase = startBase + segCountX2;
  final rangeBase = deltaBase + segCountX2;
  if (!_fits(bytes, endBase, segCountX2) ||
      !_fits(bytes, startBase, segCountX2) ||
      !_fits(bytes, deltaBase, segCountX2) ||
      !_fits(bytes, rangeBase, segCountX2)) {
    return false;
  }
  for (var i = 0; i < segCount; i++) {
    final end = _u16(bytes, endBase + i * 2);
    if (end < cp) continue;
    final start = _u16(bytes, startBase + i * 2);
    if (start > cp) return false;
    final delta = _s16(bytes, deltaBase + i * 2);
    final rangeOffset = _u16(bytes, rangeBase + i * 2);
    if (rangeOffset == 0) {
      return ((cp + delta) & 0xFFFF) != 0;
    }
    final addr = rangeBase + i * 2 + rangeOffset + (cp - start) * 2;
    if (!_fits(bytes, addr, 2)) return false;
    final glyph = _u16(bytes, addr);
    if (glyph == 0) return false;
    return ((glyph + delta) & 0xFFFF) != 0;
  }
  return false;
}

bool _coversFormat6(Uint8List bytes, int sub, int cp) {
  if (!_fits(bytes, sub, 10)) return false;
  final first = _u16(bytes, sub + 6);
  final count = _u16(bytes, sub + 8);
  if (cp < first || cp >= first + count) return false;
  final addr = sub + 10 + (cp - first) * 2;
  if (!_fits(bytes, addr, 2)) return false;
  return _u16(bytes, addr) != 0;
}

bool _coversFormat12(Uint8List bytes, int sub, int cp) {
  if (!_fits(bytes, sub, 16)) return false;
  final nGroups = _u32(bytes, sub + 12);
  if (nGroups <= 0 || nGroups > 0x10000) return false;
  final groupsStart = sub + 16;
  final maxGroups = (bytes.length - groupsStart) ~/ 12;
  final groups = nGroups < maxGroups ? nGroups : maxGroups;
  for (var i = 0; i < groups; i++) {
    final rec = groupsStart + i * 12;
    final start = _u32(bytes, rec);
    final end = _u32(bytes, rec + 4);
    if (start < 0 || end < start) return false;
    if (cp < start) continue;
    if (cp > end) continue;
    final glyph = _u32(bytes, rec + 8);
    return (glyph + (cp - start)) != 0;
  }
  return false;
}
