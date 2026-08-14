import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru/utils/repair_text.dart';

void main() {
  group('repairText', () {
    test('还原 GBK 中文乱码（ÄãºÃ 型）', () {
      // 你好世界 的 GBK 字节被按 ISO-8859-1 解码
      final mojibake = latin1.decode(gbk.encode('你好世界'));
      expect(mojibake, isNot('你好世界'));
      expect(repairText(mojibake), '你好世界');
    });

    test('还原 Shift-JIS 日文乱码', () {
      final mojibake = latin1.decode(shiftJis.encode('雨夜の耳語'));
      expect(repairText(mojibake), '雨夜の耳語');
    });

    test('正常文本不动（Latin-1 无高字节）', () {
      expect(repairText('Cafe'), 'Cafe');
      expect(repairText('Hello'), 'Hello');
    });

    test('已是中文/日文不动', () {
      expect(repairText('你好世界'), '你好世界');
      expect(repairText('雨夜の耳語'), '雨夜の耳語');
    });

    test('空值透传', () {
      expect(repairText(null), isNull);
      expect(repairText(''), '');
      expect(repairText('   '), '   ');
    });
  });

  group('looksGarbled', () {
    test('含 Latin-1 扩展字符且无 CJK 视为乱码', () {
      expect(looksGarbled(latin1.decode(gbk.encode('你好'))), isTrue);
      expect(looksGarbled('ÄãºÃ'), isTrue);
    });

    test('正常文本非乱码', () {
      expect(looksGarbled('你好'), isFalse);
      expect(looksGarbled('雨夜の耳語'), isFalse);
      expect(looksGarbled('Cafe'), isFalse);
      expect(looksGarbled(null), isFalse);
      expect(looksGarbled(''), isFalse);
    });
  });
}
