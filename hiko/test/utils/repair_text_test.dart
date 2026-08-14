import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/utils/repair_text.dart';

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

    test('还原 EUC-JP 日文乱码（老式标签）', () {
      final mojibake = latin1.decode(eucJp.encode('プロローグ'));
      expect(repairText(mojibake), 'プロローグ');
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
    test('mojibake（UTF-8 被按 Latin-1 解码的典型标记）视为乱码', () {
      expect(looksGarbled(latin1.decode(gbk.encode('你好'))), isTrue);
      expect(looksGarbled('ÄãºÃ'), isTrue);
      // UTF-8 日文 mojibake：含 ã€ / æ— 标记
      expect(looksGarbled('ã€Šæ—¥æœ¬èªžã€'), isTrue);
      // Shift-JIS 双字节高位落在 C1 控制区 → 不可用文本
      expect(looksGarbled(latin1.decode(shiftJis.encode('雨夜の耳語'))), isTrue);
    });

    test('正常文本非乱码', () {
      expect(looksGarbled('你好'), isFalse);
      expect(looksGarbled('雨夜の耳語'), isFalse);
      expect(looksGarbled('Cafe'), isFalse);
      expect(looksGarbled(null), isFalse);
      expect(looksGarbled(''), isFalse);
    });

    test('合法重音 Latin 标签保留（Café 不再误判）', () {
      expect(looksGarbled('Café'), isFalse);
      expect(looksGarbled('Prélude à l\'après-midi'), isFalse);
    });

    test('不可用文本视为乱码（控制字符/替换字符/密集问号）', () {
      expect(looksGarbled('AB\u0000CD'), isTrue);
      expect(looksGarbled('a\uFFFDb'), isTrue);
      expect(looksGarbled('??'), isTrue);
      expect(looksGarbled('Track ??'), isTrue);
    });
  });

  group('isUsableText', () {
    test('空值/空白不可用', () {
      expect(isUsableText(null), isFalse);
      expect(isUsableText(''), isFalse);
      expect(isUsableText('   '), isFalse);
    });

    test('正常文本可用', () {
      expect(isUsableText('你好世界'), isTrue);
      expect(isUsableText('雨夜の耳語'), isTrue);
      expect(isUsableText('Café'), isTrue);
    });

    test('替换字符/控制字符不可用', () {
      expect(isUsableText('a\uFFFDb'), isFalse);
      expect(isUsableText('a\u0000b'), isFalse);
      expect(isUsableText('a\u0085b'), isFalse); // NEL（C1 控制区）
    });

    test('密集问号不可用，单个问号可用', () {
      expect(isUsableText('??'), isFalse);
      expect(isUsableText('Track ?? 01'), isFalse);
      expect(isUsableText('？'), isTrue);
      expect(isUsableText('これでいい？'), isTrue);
    });
  });
}
