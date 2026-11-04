import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/fonts/font_models.dart';
import 'package:hiko/ui/fonts/font_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FontLibraryNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tmp = await Directory.systemTemp.createTemp('hiko-fonts-test');
    notifier = FontLibraryNotifier(directory: () async => tmp);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('导入合法字体：落盘到 fonts/、族名取自 name 表、日文标记为 false', () async {
    final result = await notifier.importBytes(_fontBytes('测试字体'));
    expect(result.status, FontImportStatus.ok);
    final font = result.font!;
    expect(font.family, '测试字体');
    expect(font.format, 'ttf');
    expect(font.japanese, isFalse);
    expect(font.id, hasLength(12));
    expect(font.file, contains('${Platform.pathSeparator}fonts'));
    expect(File(font.file).existsSync(), isTrue);
    expect(notifier.state.fonts, hasLength(1));

    // 元数据已写进 prefs
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(FontLibraryNotifier.prefsKey)!;
    expect(raw, contains(font.id));
  });

  test('同内容重复导入 → duplicate，不再落第二份', () async {
    final bytes = _fontBytes('重复');
    final first = await notifier.importBytes(bytes);
    final second = await notifier.importBytes(Uint8List.fromList(bytes));
    expect(first.status, FontImportStatus.ok);
    expect(second.status, FontImportStatus.duplicate);
    expect(second.font!.id, first.font!.id);
    expect(notifier.state.fonts, hasLength(1));
    expect(Directory('${tmp.path}/fonts').listSync().length, 1);
  });

  test('超过 32MB → tooLarge', () async {
    final huge = Uint8List(FontLibraryNotifier.maxBytes + 1);
    final result = await notifier.importBytes(huge);
    expect(result.status, FontImportStatus.tooLarge);
  });

  test('不是字体 → badFormat，且不留下文件', () async {
    final result = await notifier.importBytes(
      Uint8List.fromList(List<int>.filled(64, 0x41)),
    );
    expect(result.status, FontImportStatus.badFormat);
    expect(notifier.state.fonts, isEmpty);
    final dir = Directory('${tmp.path}/fonts');
    expect(dir.existsSync() ? dir.listSync().length : 0, 0);
  });

  test('库内最多 20 个', () async {
    for (var i = 0; i < FontLibraryNotifier.maxFonts; i++) {
      final result = await notifier.importBytes(_fontBytes('字体$i'));
      expect(result.status, FontImportStatus.ok, reason: '第 $i 个');
    }
    final overflow = await notifier.importBytes(_fontBytes('溢出'));
    expect(overflow.status, FontImportStatus.libraryFull);
    expect(notifier.state.fonts, hasLength(FontLibraryNotifier.maxFonts));
  });

  test('删除：文件与元数据一起清掉', () async {
    final font = (await notifier.importBytes(_fontBytes('待删'))).font!;
    await notifier.remove(font);
    expect(notifier.state.fonts, isEmpty);
    expect(File(font.file).existsSync(), isFalse);
  });

  test('load：文件已丢失的条目被剔除', () async {
    final kept = (await notifier.importBytes(_fontBytes('保留'))).font!;
    final gone = (await notifier.importBytes(_fontBytes('丢失'))).font!;
    File(gone.file).deleteSync();

    final reloaded = FontLibraryNotifier(directory: () async => tmp);
    await reloaded.load();
    expect(reloaded.state.fonts.map((f) => f.id), <String>[kept.id]);
  });

  test('load：坏 JSON / 非法条目不会让库炸掉', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FontLibraryNotifier.prefsKey: '{not json',
    });
    final reloaded = FontLibraryNotifier(directory: () async => tmp);
    await reloaded.load();
    expect(reloaded.state.fonts, isEmpty);

    SharedPreferences.setMockInitialValues(<String, Object>{
      FontLibraryNotifier.prefsKey: jsonEncode(<String, Object?>{
        'version': 1,
        'fonts': <Object?>[
          <String, Object?>{'id': 'short'},
          UserFont(
            id: 'abcdef123456',
            family: 'OK',
            file: '${tmp.path}/fonts/abcdef123456.ttf',
            bytes: 10,
            addedAt: 1,
            japanese: true,
            format: 'ttf',
          ).toJson(),
        ],
      }),
    });
    Directory('${tmp.path}/fonts').createSync(recursive: true);
    File('${tmp.path}/fonts/abcdef123456.ttf').writeAsBytesSync(<int>[0]);
    final again = FontLibraryNotifier(directory: () async => tmp);
    await again.load();
    expect(again.state.fonts, hasLength(1));
    expect(again.state.fonts.single.family, 'OK');
  });

  test('UserFont.fromJson 对缺字段 / 非法格式返回 null', () {
    expect(UserFont.fromJson(null), isNull);
    expect(UserFont.fromJson(<String, Object?>{'id': 'x'}), isNull);
    expect(
      UserFont.fromJson(<String, Object?>{
        'id': 'abcdef123456',
        'family': 'F',
        'file': '/tmp/a.ttf',
        'bytes': 1,
        'addedAt': 1,
        'japanese': true,
        'format': 'woff',
      }),
      isNull,
    );
  });
}

/// 构造一个只含 name + cmap（空 format 4 子表）的最小 sfnt。
Uint8List _fontBytes(String family) {
  final name = _nameTable(family);
  final cmap = _cmapTable();
  final tables = <String, Uint8List>{'cmap': cmap, 'name': name};
  const headerSize = 12 + 2 * 16;
  var cursor = headerSize;
  final offsets = <String, int>{};
  for (final tag in tables.keys) {
    cursor = (cursor + 3) & ~3;
    offsets[tag] = cursor;
    cursor += tables[tag]!.length;
  }
  final out = Uint8List(cursor);
  final data = ByteData.sublistView(out);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, tables.length);
  var index = 0;
  for (final tag in tables.keys) {
    final rec = 12 + index * 16;
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
    index++;
  }
  return out;
}

Uint8List _nameTable(String family) {
  final encoded = <int>[];
  for (final unit in family.codeUnits) {
    encoded
      ..add((unit >> 8) & 0xFF)
      ..add(unit & 0xFF);
  }
  final out = Uint8List(18 + encoded.length);
  final data = ByteData.sublistView(out);
  data.setUint16(2, 1);
  data.setUint16(4, 18);
  data.setUint16(6, 3);
  data.setUint16(8, 1);
  data.setUint16(10, 0x0409);
  data.setUint16(12, 1);
  data.setUint16(14, encoded.length);
  data.setUint16(16, 0);
  out.setRange(18, 18 + encoded.length, encoded);
  return out;
}

Uint8List _cmapTable() {
  // 12 字节 cmap 头 + 24 字节 format 4（只有一个 0xFFFF 收尾段）
  final out = Uint8List(36);
  final data = ByteData.sublistView(out);
  data.setUint16(2, 1);
  data.setUint16(4, 3);
  data.setUint16(6, 1);
  data.setUint32(8, 12);
  data.setUint16(12, 4);
  data.setUint16(14, 24);
  data.setUint16(18, 2); // segCountX2
  data.setUint16(26, 0xFFFF); // endCode
  data.setUint16(30, 0xFFFF); // startCode
  data.setUint16(32, 1); // idDelta → glyph 0
  return out;
}
