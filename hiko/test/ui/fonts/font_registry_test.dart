import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/fonts/font_models.dart';
import 'package:hiko/ui/fonts/font_registry.dart';

void main() {
  late Directory tmp;
  late UserFont font;
  var calls = 0;
  var failNext = false;

  setUp(() async {
    FontRegistry.resetForTest();
    tmp = await Directory.systemTemp.createTemp('hiko-font-registry');
    final file = File('${tmp.path}/abcdef123456.ttf')
      ..writeAsBytesSync(List<int>.filled(64, 1));
    font = UserFont(
      id: 'abcdef123456',
      family: '测试',
      file: file.path,
      bytes: 64,
      addedAt: 1,
      japanese: true,
      format: 'ttf',
    );
    calls = 0;
    failNext = false;
    FontRegistry.debugLoader = (family, data) async {
      calls++;
      if (failNext) throw StateError('boom');
      expect(family, FontRegistry.familyOf(font.id));
      expect(data.lengthInBytes, 64);
    };
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    FontRegistry.resetForTest();
  });

  test('同一 id 只注册一次', () async {
    expect(await FontRegistry.ensureLoaded(font), isTrue);
    expect(await FontRegistry.ensureLoaded(font), isTrue);
    expect(calls, 1);
    expect(FontRegistry.isLoaded(font.id), isTrue);
  });

  test('加载失败不写入已加载集合，可重试', () async {
    failNext = true;
    expect(await FontRegistry.ensureLoaded(font), isFalse);
    expect(FontRegistry.isLoaded(font.id), isFalse);
    failNext = false;
    expect(await FontRegistry.ensureLoaded(font), isTrue);
    expect(calls, 2);
  });

  test('文件缺失 → false，不抛异常', () async {
    File(font.file).deleteSync();
    expect(await FontRegistry.ensureLoaded(font), isFalse);
  });

  test('族名是 ASCII 自造串，与用户字体名无关', () {
    expect(FontRegistry.familyOf('abcdef123456'), 'HikoUser_abcdef123456');
  });
}
