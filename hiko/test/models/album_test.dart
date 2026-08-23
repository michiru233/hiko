import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';

void main() {
  group('Album JSON 往返', () {
    test('完整字段 round-trip', () {
      final album = Album(
        id: 'local-abcdef1234567890',
        sourcePath: '/tmp/音声/RJ123456_雨夜耳语',
        title: '雨夜耳语',
        artist: '某社团',
        albumArtist: '',
        rjCode: 'RJ123456',
        dlsiteTitle: '雨夜の耳語',
        tags: ['ASMR', 'バイノーラル'],
        genre: 'ASMR',
        duration: 2,
        totalDuration: 3723.5,
        played: 100,
        favorite: true,
        date: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        tracks: [
          Track(index: 0, name: '01_プロローグ', url: 'file:///tmp/音声/01.mp3', duration: 1800, cover: 'data:image/jpeg;base64,xxx'),
          Track(index: 1, name: '02_本編', url: 'file:///tmp/音声/02.mp3', duration: 1923.5),
        ],
        localCover: 'data:image/jpeg;base64,cover',
        color: ['#c4b8e8', '#4b416c'],
        shape: 'moon',
      );

      final restored = Album.fromJson(album.toJson());
      expect(restored.id, album.id);
      expect(restored.title, album.title);
      expect(restored.artist, album.artist);
      expect(restored.rjCode, 'RJ123456');
      expect(restored.tags, ['ASMR', 'バイノーラル']);
      expect(restored.tracks.length, 2);
      expect(restored.tracks[0].cover, 'data:image/jpeg;base64,xxx');
      expect(restored.tracks[1].duration, 1923.5);
      expect(restored.totalDuration, 3723.5);
      expect(restored.favorite, isTrue);
      expect(restored.date.millisecondsSinceEpoch, 1700000000000);
      expect(restored.color, ['#c4b8e8', '#4b416c']);
      expect(restored.shape, 'moon');
    });

    test('缺失字段回退默认值', () {
      final album = Album.fromJson(const {'id': 'x', 'sourcePath': '', 'title': 'T', 'date': 0});
      expect(album.artist, '本地导入');
      expect(album.genre, '未分类');
      expect(album.tags, isEmpty);
      expect(album.tracks, isEmpty);
      expect(album.color, ['#c4b8e8', '#4b416c']);
      expect(album.shape, 'radio');
      expect(album.hasLocalFiles, isFalse);
    });

    test('copyWith 重算曲目数与总时长', () {
      final album = Album(
        id: 'a',
        sourcePath: '/x',
        title: 'T',
        date: DateTime.now(),
        tracks: [
          Track(index: 0, name: 't1', url: 'file:///1.mp3', duration: 10),
          Track(index: 1, name: 't2', url: 'file:///2.mp3', duration: 20),
        ],
      );
      final updated = album.copyWith(played: 5, favorite: true, rjCode: 'RJ1');
      expect(updated.played, 5);
      expect(updated.favorite, isTrue);
      expect(updated.rjCode, 'RJ1');
      expect(updated.duration, 2);
      expect(updated.totalDuration, 30);
    });
  });

  group('MethodChannel 类型（Map<Object?, Object?>）解析', () {
    test('通道 Map 泛型不匹配也能解析', () {
      final raw = <Object?, Object?>{
        'id': 'local-x',
        'sourcePath': '',
        'title': '通道专辑',
        'date': 0,
        'tracks': <Object?>[
          <Object?, Object?>{'index': 0, 'name': '曲目一', 'url': 'content://x/1.mp3'},
        ],
      };
      final album = Album.fromJson(Map<String, dynamic>.from(raw));
      expect(album.title, '通道专辑');
      expect(album.tracks.single.name, '曲目一');
    });
  });

  group('mergeWith 标题自愈（1.32：纯 RJ 号/乱码旧标题允许被替换）', () {
    Album freshAlbum(String title) => Album(
          id: 'a',
          sourcePath: '/x',
          title: title,
          artist: '新社团',
          albumArtist: '新社团',
          date: DateTime.now(),
        );

    test('纯 RJ 号旧标题被新标签标题替换', () {
      final merged = freshAlbum('雨夜の耳語').mergeWith(
        Album(id: 'a', sourcePath: '/x', title: 'RJ123456', date: DateTime.now()),
      );
      expect(merged.title, '雨夜の耳語');
    });

    test('乱码旧标题被替换', () {
      final merged = freshAlbum('正常标题').mergeWith(
        Album(id: 'a', sourcePath: '/x', title: 'ãƒã‚¯ãƒˆã®è³', date: DateTime.now()),
      );
      expect(merged.title, '正常标题');
    });

    test('正常旧标题保留（用户数据粘滞保护仍有效）', () {
      final merged = freshAlbum('新扫描标题').mergeWith(
        Album(id: 'a', sourcePath: '/x', title: '用户认可的旧标题', date: DateTime.now()),
      );
      expect(merged.title, '用户认可的旧标题');
    });

    test('已刮削（hasDlsite）旧标题保留', () {
      final merged = freshAlbum('新扫描标题').mergeWith(
        Album(
          id: 'a',
          sourcePath: '/x',
          title: 'DLsite 标题',
          dlsiteTitle: 'DLsite 标题',
          date: DateTime.now(),
        ),
      );
      expect(merged.title, 'DLsite 标题');
    });
  });

  group('metaFromFolder 标志（1.32：标记标题来自文件夹回退，供 DLsite 兜底）', () {
    test('JSON 往返保留 true', () {
      final album = Album(
        id: 'a',
        sourcePath: '/x',
        title: 'RJ123456',
        metaFromFolder: true,
        date: DateTime.now(),
      );
      expect(Album.fromJson(album.toJson()).metaFromFolder, isTrue);
    });

    test('缺省 false 且不出现在 JSON', () {
      final album = Album(id: 'a', sourcePath: '/x', title: 'T', date: DateTime.now());
      expect(album.metaFromFolder, isFalse);
      expect(album.toJson().containsKey('metaFromFolder'), isFalse);
    });

    test('copyWith 可清除', () {
      final album = Album(
        id: 'a',
        sourcePath: '/x',
        title: 'T',
        metaFromFolder: true,
        date: DateTime.now(),
      );
      expect(album.copyWith(metaFromFolder: false).metaFromFolder, isFalse);
    });
  });
}
