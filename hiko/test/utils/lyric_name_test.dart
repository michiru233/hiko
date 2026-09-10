import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/utils/lyric_name.dart';

void main() {
  group('isLyricFor', () {
    test('同名换扩展名', () {
      expect(isLyricFor('01.mp3', '01.lrc'), isTrue);
      expect(isLyricFor('01.mp3', '01.vtt'), isTrue);
      expect(isLyricFor('01.mp3', '01.srt'), isTrue);
    });

    test('大小写不敏感', () {
      expect(isLyricFor('01.MP3', '01.LRC'), isTrue);
      expect(isLyricFor('01.mp3', '01.VTT'), isTrue);
    });

    test('完整音频名加后缀（DLsite 常见，安卓端曾整片丢失）', () {
      // RJ01414585 实测命名：track01 柊莉花.mp3 + track01 柊莉花.mp3.vtt
      expect(isLyricFor('track01 柊莉花.mp3', 'track01 柊莉花.mp3.vtt'), isTrue);
      expect(isLyricFor('01.mp3', '01.mp3.vtt'), isTrue);
      expect(isLyricFor('01.mp3', '01.MP3.VTT'), isTrue);
    });

    test('不同曲目不串号', () {
      expect(isLyricFor('01.mp3', '02.lrc'), isFalse);
      expect(isLyricFor('track01.mp3', 'track02.mp3.vtt'), isFalse);
      // 前缀相同但不是同一首
      expect(isLyricFor('track1.mp3', 'track10.mp3.vtt'), isFalse);
    });

    test('非歌词扩展名与畸形名不匹配', () {
      expect(isLyricFor('01.mp3', '01.txt'), isFalse);
      expect(isLyricFor('01.mp3', '01.mp3'), isFalse);
      expect(isLyricFor('01.mp3', '.vtt'), isFalse);
      expect(isLyricFor('01.mp3', ''), isFalse);
    });

    test('无扩展名的音频也能匹配', () {
      expect(isLyricFor('track01', 'track01.lrc'), isTrue);
    });
  });
}
