import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/lyrics/lyrics_resolver.dart';
import 'package:hiko/lyrics/parsers/lrc_parser.dart';
import 'package:hiko/lyrics/parsers/vtt_parser.dart';

void main() {
  group('LrcParser Tests', () {
    test('parses basic LRC with tags, offset, and multiple timestamps', () {
      const lrcContent = '''
[ti:テスト音声]
[ar:声優A]
[al:同人アルバム]
[offset:+500]

[00:01.00]はじめまして、ご主人様。
[00:05.50][00:10.00]お茶が入りましたよ。
[00:15.20]【店員】いらっしゃいませ！
''';

      final result = LrcParser.parse(lrcContent);
      expect(result.title, 'テスト音声');
      expect(result.artist, '声優A');
      expect(result.album, '同人アルバム');
      expect(result.offsetMs, 500);
      expect(result.lines.length, 4); // 00:01, 00:05, 00:10, 00:15

      // 00:01.00 + 500ms offset = 1500ms
      expect(result.lines[0].startTime, const Duration(milliseconds: 1500));
      expect(result.lines[0].text, 'はじめまして、ご主人様。');
      expect(result.lines[0].speaker, isNull);

      // Multiple timestamps sorted: line 1 at 6000ms, line 2 at 10500ms
      expect(result.lines[1].startTime, const Duration(milliseconds: 6000));
      expect(result.lines[1].text, 'お茶が入りましたよ。');

      expect(result.lines[2].startTime, const Duration(milliseconds: 10500));
      expect(result.lines[2].text, 'お茶が入りましたよ。');

      // Speaker prefix extraction
      expect(result.lines[3].startTime, const Duration(milliseconds: 15700));
      expect(result.lines[3].speaker, '店員');
      expect(result.lines[3].text, 'いらっしゃいませ！');
    });

    test('handles empty or malformed LRC gracefully', () {
      expect(LrcParser.parse('').isEmpty, isTrue);
      expect(LrcParser.parse('   \n  \n').isEmpty, isTrue);
      expect(LrcParser.parse('[ar:OnlyTag]').isEmpty, isTrue);
    });
  });

  group('VttParser Tests', () {
    test('parses standard WebVTT cues, timestamps, and voice tags', () {
      const vttContent = '''
WEBVTT

NOTE This is a commentary note

00:00:01.000 --> 00:00:03.500
<v 妹>お兄ちゃん、起きて！

00:04.000 --> 00:07.250 align:start
<v.narrator ナレーション>朝の光が差し込む。<b>小鳥がさえずる。</b>

3
00:08.000 --> 00:10.000
&lt;特別な時間&gt; &amp; ひととき
''';

      final result = VttParser.parse(vttContent);
      expect(result.lines.length, 3);

      expect(result.lines[0].startTime, const Duration(seconds: 1));
      expect(result.lines[0].endTime, const Duration(milliseconds: 3500));
      expect(result.lines[0].speaker, '妹');
      expect(result.lines[0].text, 'お兄ちゃん、起きて！');

      expect(result.lines[1].startTime, const Duration(seconds: 4));
      expect(result.lines[1].endTime, const Duration(milliseconds: 7250));
      expect(result.lines[1].speaker, 'ナレーション');
      expect(result.lines[1].text, '朝の光が差し込む。小鳥がさえずる。'); // stripped <b>

      expect(result.lines[2].startTime, const Duration(seconds: 8));
      expect(result.lines[2].endTime, const Duration(seconds: 10));
      expect(result.lines[2].text, '<特別な時間> & ひととき'); // decoded entities
    });
  });

  group('LyricsResolver Safe Decoding Tests', () {
    test('decodes UTF-8 with BOM', () {
      final utf8BomBytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF,
        ...utf8.encode('[00:01.00]おはようございます'),
      ]);
      final text = LyricsResolver.decodeBytesSafely(utf8BomBytes);
      expect(text, contains('おはようございます'));
    });

    test('decodes Shift-JIS encoded Japanese text without mojibake', () {
      const original = '[00:01.00]耳かき音声・右耳から優しく囁きます。';
      final sjisBytes = Uint8List.fromList(shiftJis.encode(original));
      final decoded = LyricsResolver.decodeBytesSafely(sjisBytes);
      expect(decoded, original);
    });

    test('decodes GBK encoded Simplified Chinese text without mojibake', () {
      const original = '[00:01.00]这是中文汉化字幕，测试编码自动识别';
      final gbkBytes = Uint8List.fromList(gbk.encode(original));
      final decoded = LyricsResolver.decodeBytesSafely(gbkBytes);
      expect(decoded, original);
    });
  });
}
