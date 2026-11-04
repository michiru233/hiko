import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/fonts/sfnt_parser.dart';

/// 只为测试构造最小 sfnt：一张 name 表 + 一张 cmap 表。
/// 不依赖任何系统字体文件，用例在 CI 上可复现。
void main() {
  group('parseSfnt 容器判定', () {
    test('空字节 / 太短 → notSfnt', () {
      expect(parseSfnt(Uint8List(0)).error, SfntError.notSfnt);
      expect(parseSfnt(Uint8List.fromList([1, 2, 3])).error, SfntError.notSfnt);
    });

    test('ttc 字体集合 → collection', () {
      final bytes = _buildSfnt(magic: 'ttcf');
      expect(parseSfnt(bytes).error, SfntError.collection);
    });

    test('woff / woff2 → woff', () {
      expect(parseSfnt(_buildSfnt(magic: 'wOFF')).error, SfntError.woff);
      expect(parseSfnt(_buildSfnt(magic: 'wOF2')).error, SfntError.woff);
    });

    test('表目录越界 → truncated', () {
      final bytes = _buildSfnt(family: 'X');
      // 把 numTables 改成 4095，目录区必然越界
      final broken = Uint8List.fromList(bytes);
      broken[4] = 0x0F;
      broken[5] = 0xFF;
      expect(parseSfnt(broken).error, SfntError.truncated);
    });

    test('表 offset 越过文件尾 → truncated', () {
      final bytes = _buildSfnt(family: 'X');
      final broken = Uint8List.fromList(bytes);
      // 第一条表记录的 offset 字段（12 + 8）改成 0xFFFFFF
      broken[20] = 0xFF;
      broken[21] = 0xFF;
      broken[22] = 0xFF;
      broken[23] = 0xFF;
      expect(parseSfnt(broken).error, SfntError.truncated);
    });

    test('缺 name 表 → noName', () {
      expect(
        parseSfnt(_buildSfnt(family: 'X', withName: false)).error,
        SfntError.noName,
      );
    });

    test('缺 cmap 表 → noCmap', () {
      expect(
        parseSfnt(_buildSfnt(family: 'X', withCmap: false)).error,
        SfntError.noCmap,
      );
    });
  });

  group('族名', () {
    test('Windows/UTF-16BE 族名正常解码', () {
      final result = parseSfnt(_buildSfnt(family: '思源宋体 CN'));
      expect(result.isOk, isTrue);
      expect(result.info!.family, '思源宋体 CN');
    });

    test('只有 nameID 4（full name）时也能回退读到', () {
      final result = parseSfnt(_buildSfnt(family: 'Hiko Test', nameId: 4));
      expect(result.info!.family, 'Hiko Test');
    });

    test('族名里的控制字符与首尾空白被清掉', () {
      final result = parseSfnt(_buildSfnt(family: '  A\u0000B  '));
      expect(result.info!.family, 'AB');
    });

    test('没有可用名称记录 → family 为 null（调用方回退文件名）', () {
      final result = parseSfnt(_buildSfnt(family: ''));
      expect(result.isOk, isTrue);
      expect(result.info!.family, isNull);
    });
  });

  group('日文覆盖探针', () {
    test('20 个假名全覆盖 → hasJapanese', () {
      final bytes = _buildSfnt(
        family: 'JP',
        codepoints: const [
          0x3042,
          0x3044,
          0x3046,
          0x3048,
          0x304A,
          0x304B,
          0x304D,
          0x304F,
          0x3051,
          0x3053,
          0x30A2,
          0x30A4,
          0x30A6,
          0x30A8,
          0x30AA,
          0x30AB,
          0x30AD,
          0x30AF,
          0x30B1,
          0x30B3,
        ],
      );
      final info = parseSfnt(bytes).info!;
      expect(info.kanaHits, 20);
      expect(info.hasJapanese, isTrue);
    });

    test('只有 15 个假名 → 不算日文字体（阈值 16）', () {
      final bytes = _buildSfnt(
        family: 'Half',
        codepoints: const [
          0x3042,
          0x3044,
          0x3046,
          0x3048,
          0x304A,
          0x304B,
          0x304D,
          0x304F,
          0x3051,
          0x3053,
          0x30A2,
          0x30A4,
          0x30A6,
          0x30A8,
          0x30AA,
        ],
      );
      final info = parseSfnt(bytes).info!;
      expect(info.kanaHits, 15);
      expect(info.hasJapanese, isFalse);
    });

    test('只有拉丁字形 → 假名 0 命中', () {
      final info = parseSfnt(
        _buildSfnt(family: 'Latin', codepoints: const [0x41, 0x42, 0x30]),
      ).info!;
      expect(info.kanaHits, 0);
      expect(info.hasJapanese, isFalse);
    });

    test('format 12 子表同样能命中（增补面路径不崩）', () {
      final bytes = _buildSfnt(
        family: 'Wide',
        format12: true,
        codepoints: const [0x3042, 0x3044, 0x3046, 0x3048, 0x304A],
      );
      final info = parseSfnt(bytes).info!;
      expect(info.kanaHits, 5);
    });
  });

  group('其它标志', () {
    test('OTTO → flavor otf', () {
      expect(
        parseSfnt(_buildSfnt(family: 'X', otto: true)).info!.flavor,
        'otf',
      );
    });

    test('有 fvar → variable', () {
      final bytes = _buildSfnt(family: 'V', withFvar: true);
      expect(parseSfnt(bytes).info!.variable, isTrue);
    });

    test('损坏的 cmap 子表不抛异常（当作不覆盖）', () {
      final bytes = _buildSfnt(family: 'X', codepoints: const [0x3042]);
      final broken = Uint8List.fromList(bytes);
      // 把 cmap 子表的 segCountX2 改成 0xFFFF（越界），解析必须不崩
      final cmapOffset = _tableOffset(broken, 'cmap');
      final subOffset = cmapOffset + 4 + 8;
      broken[subOffset + 6] = 0xFF;
      broken[subOffset + 7] = 0xFF;
      final result = parseSfnt(broken);
      expect(result.isOk, isTrue);
      expect(result.info!.kanaHits, 0);
    });
  });
}

int _tableOffset(Uint8List bytes, String tag) {
  final numTables = (bytes[4] << 8) | bytes[5];
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final t = String.fromCharCodes(bytes, rec, rec + 4);
    if (t == tag) {
      return (bytes[rec + 8] << 24) |
          (bytes[rec + 9] << 16) |
          (bytes[rec + 10] << 8) |
          bytes[rec + 11];
    }
  }
  throw StateError('table $tag not found');
}

/// 构造一个最小可解析的 sfnt。
Uint8List _buildSfnt({
  String family = '',
  List<int> codepoints = const [],
  bool format12 = false,
  bool otto = false,
  bool withFvar = false,
  bool withName = true,
  bool withCmap = true,
  String? magic,
  int nameId = 1,
}) {
  final tables = <String, Uint8List>{};
  if (withName) tables['name'] = _nameTable(family, nameId);
  if (withCmap) tables['cmap'] = _cmapTable(codepoints, format12: format12);
  if (withFvar) tables['fvar'] = Uint8List(16);

  final tags = tables.keys.toList()..sort();
  final numTables = tags.length;
  final headerSize = 12 + numTables * 16;
  var cursor = headerSize;
  final offsets = <String, int>{};
  for (final tag in tags) {
    cursor = (cursor + 3) & ~3;
    offsets[tag] = cursor;
    cursor += tables[tag]!.length;
  }

  final out = Uint8List(cursor);
  final data = ByteData.sublistView(out);
  final head = magic ?? (otto ? 'OTTO' : '\u0000\u0001\u0000\u0000');
  for (var i = 0; i < 4; i++) {
    out[i] = head.codeUnitAt(i) & 0xFF;
  }
  data.setUint16(4, numTables);
  for (var i = 0; i < numTables; i++) {
    final tag = tags[i];
    final rec = 12 + i * 16;
    for (var c = 0; c < 4; c++) {
      out[rec + c] = tag.codeUnitAt(c);
    }
    data.setUint32(rec + 8, offsets[tag]!);
    data.setUint32(rec + 12, tables[tag]!.length);
    out.setRange(
      offsets[tag]!,
      offsets[tag]! + tables[tag]!.length,
      tables[tag]!,
    );
  }
  return out;
}

Uint8List _nameTable(String family, int nameId) {
  if (family.isEmpty) {
    // 只有 count=0 的空表
    return Uint8List.fromList([0, 0, 0, 0, 0, 6]);
  }
  final encoded = <int>[];
  for (final unit in family.codeUnits) {
    encoded
      ..add((unit >> 8) & 0xFF)
      ..add(unit & 0xFF);
  }
  final out = Uint8List(6 + 12 + encoded.length);
  final data = ByteData.sublistView(out);
  data.setUint16(0, 0); // format
  data.setUint16(2, 1); // count
  data.setUint16(4, 6 + 12); // stringOffset
  data.setUint16(6, 3); // platformID = Windows
  data.setUint16(8, 1); // encodingID = Unicode BMP
  data.setUint16(10, 0x0409); // languageID = en-US
  data.setUint16(12, nameId);
  data.setUint16(14, encoded.length);
  data.setUint16(16, 0); // offset
  out.setRange(18, 18 + encoded.length, encoded);
  return out;
}

Uint8List _cmapTable(List<int> codepoints, {required bool format12}) {
  final sorted = codepoints.toSet().toList()..sort();
  final sub = format12 ? _cmapFormat12(sorted) : _cmapFormat4(sorted);
  final out = Uint8List(12 + sub.length);
  final data = ByteData.sublistView(out);
  data.setUint16(0, 0); // version
  data.setUint16(2, 1); // numTables
  data.setUint16(4, 3); // platformID
  data.setUint16(6, format12 ? 10 : 1); // encodingID
  data.setUint32(8, 12); // subtable offset
  out.setRange(12, 12 + sub.length, sub);
  return out;
}

Uint8List _cmapFormat4(List<int> codepoints) {
  final segments = [
    for (final cp in codepoints)
      if (cp <= 0xFFFE) cp,
  ];
  final segCount = segments.length + 1; // + 结尾 0xFFFF 段
  final length = 16 + 8 * segCount;
  final out = Uint8List(length);
  final data = ByteData.sublistView(out);
  data.setUint16(0, 4);
  data.setUint16(2, length);
  data.setUint16(4, 0);
  data.setUint16(6, segCount * 2);
  data.setUint16(8, 0); // searchRange
  data.setUint16(10, 0); // entrySelector
  data.setUint16(12, 0); // rangeShift
  final endBase = 14;
  final startBase = endBase + segCount * 2 + 2;
  final deltaBase = startBase + segCount * 2;
  final rangeBase = deltaBase + segCount * 2;
  for (var i = 0; i < segments.length; i++) {
    data.setUint16(endBase + i * 2, segments[i]);
    data.setUint16(startBase + i * 2, segments[i]);
    data.setUint16(deltaBase + i * 2, (1 - segments[i]) & 0xFFFF);
    data.setUint16(rangeBase + i * 2, 0);
  }
  final last = segments.length;
  data.setUint16(endBase + last * 2, 0xFFFF);
  data.setUint16(startBase + last * 2, 0xFFFF);
  data.setUint16(deltaBase + last * 2, 1); // 0xFFFF + 1 → glyph 0
  data.setUint16(rangeBase + last * 2, 0);
  return out;
}

Uint8List _cmapFormat12(List<int> codepoints) {
  final length = 16 + 12 * codepoints.length;
  final out = Uint8List(length);
  final data = ByteData.sublistView(out);
  data.setUint16(0, 12);
  data.setUint16(2, 0);
  data.setUint32(4, length);
  data.setUint32(8, 0);
  data.setUint32(12, codepoints.length);
  for (var i = 0; i < codepoints.length; i++) {
    final rec = 16 + i * 12;
    data.setUint32(rec, codepoints[i]);
    data.setUint32(rec + 4, codepoints[i]);
    data.setUint32(rec + 8, 1);
  }
  return out;
}
