import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/utils/rj.dart';

void main() {
  group('extractRjCode', () {
    test('从路径全层级提取 RJ 号（大小写不敏感）', () {
      expect(extractRjCode(['/tmp/audio/RJ123456_雨夜耳语/01.mp3']), 'RJ123456');
      expect(extractRjCode(['/deep/rj01000112_深层音声/inner/测试音声']), 'RJ01000112');
      expect(extractRjCode(['无RJ号路径']), isNull);
    });

    test('取第一个匹配并大写', () {
      expect(extractRjCode(['a/RJ00001.mp3', 'b/RJ99999.mp3']), 'RJ00001');
    });
  });

  group('albumRjCode', () {
    test('有 rjCode 直接用，缺失时从路径/标题/曲目名兜底', () {
      final withCode = Album(
        id: 'local-a',
        sourcePath: '/x/y',
        title: '雨夜耳语',
        rjCode: 'RJ11111',
        date: DateTime.now(),
      );
      expect(albumRjCode(withCode), 'RJ11111');

      final fromPath = Album(
        id: 'local-b',
        sourcePath: '/downloads/RJ22222_somework',
        title: 'somework',
        date: DateTime.now(),
      );
      expect(albumRjCode(fromPath), 'RJ22222');

      final fromTrack = Album(
        id: 'local-c',
        sourcePath: '/x',
        title: '标题',
        date: DateTime.now(),
        tracks: [
          Track(index: 0, name: 'RJ33333_トラック1', url: 'file:///x/1.mp3'),
        ],
      );
      expect(albumRjCode(fromTrack), 'RJ33333');

      final none = Album(
        id: 'local-d',
        sourcePath: '/x',
        title: '无号',
        date: DateTime.now(),
      );
      expect(albumRjCode(none), isNull);
    });
  });

  group('cleanFolderTitle', () {
    test('剥离 RJ 前缀', () {
      expect(cleanFolderTitle('RJ123456_雨夜耳语'), '雨夜耳语');
      expect(cleanFolderTitle('rj123456-雨夜耳语'), '雨夜耳语');
      expect(cleanFolderTitle('RJ123456 雨夜耳语'), '雨夜耳语');
    });

    test('无前缀原样返回', () {
      expect(cleanFolderTitle('雨夜耳语'), '雨夜耳语');
      expect(cleanFolderTitle(null), isNull);
      expect(cleanFolderTitle(''), '');
    });
  });
}
