import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/platform/platform_service.dart';

void main() {
  late Directory root;
  late DesktopPlatformService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hiko-platform-test');
    service = DesktopPlatformService();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Album albumWithFiles({int trackCount = 2, bool withCover = true, String name = '专辑'}) {
    final dir = Directory('${root.path}/$name');
    dir.createSync();
    final tracks = <Track>[];
    for (var i = 0; i < trackCount; i++) {
      final file = File('${dir.path}/0${i + 1}.wav');
      file.writeAsBytesSync(List.filled(100, i));
      tracks.add(Track(
        index: i,
        name: 'track$i',
        url: Uri.file(file.path).toString(),
        duration: 1,
      ));
    }
    String? cover;
    if (withCover) {
      final coverFile = File('${dir.path}/cover.jpg');
      coverFile.writeAsBytesSync(List.filled(50, 1));
      cover = Uri.file(coverFile.path).toString();
    }
    return Album(
      id: 'local-test',
      sourcePath: dir.path,
      title: '测试专辑',
      date: DateTime.now(),
      tracks: tracks,
      localCover: cover,
    );
  }

  group('removeAlbumFiles', () {
    test('删除音轨 + 封面 + 空目录', () async {
      final album = albumWithFiles();
      final dir = Directory(album.sourcePath);
      expect(dir.existsSync(), isTrue);
      expect(dir.listSync().length, 3); // 2 wav + cover

      final deleted = await service.removeAlbumFiles(album);

      expect(deleted, 3);
      expect(dir.existsSync(), isFalse); // 空目录被删除
    });

    test('目录非空时保留目录', () async {
      final album = albumWithFiles(trackCount: 1);
      // 额外放一个非音频文件占位
      File('${album.sourcePath}/说明.txt').writeAsStringSync('保留');
      final deleted = await service.removeAlbumFiles(album);
      expect(deleted, 2); // wav + cover
      expect(Directory(album.sourcePath).existsSync(), isTrue); // 目录仍在
      expect(File('${album.sourcePath}/说明.txt').existsSync(), isTrue);
    });

    test('文件已不存在时容错', () async {
      final album = albumWithFiles();
      Directory(album.sourcePath).deleteSync(recursive: true);
      final deleted = await service.removeAlbumFiles(album);
      expect(deleted, 0);
    });
  });

  group('cleanMissing', () {
    test('剔除整张失效专辑、修剪部分失效曲目', () async {
      final a1 = albumWithFiles(name: 'a1'); // 完整存活
      final a2 = albumWithFiles(name: 'a2', trackCount: 2);
      // a2 第一首删除 → 应保留 1 首
      File(Uri.parse(a2.tracks[0].url).toFilePath()).deleteSync();
      // a3 全部失效 → 整张移除
      final a3 = albumWithFiles(name: 'a3');
      Directory(a3.sourcePath).deleteSync(recursive: true);

      final kept = await service.cleanMissing([a1, a2, a3]);

      expect(kept.length, 2);
      expect(kept[0].id, a1.id);
      expect(kept[0].tracks.length, 2);
      expect(kept[1].id, a2.id);
      expect(kept[1].tracks.length, 1);
      expect(kept[1].tracks[0].name, 'track1');
    });

    test('非 file:// 音轨（如 Android content://）视为存活', () async {
      final album = Album(
        id: 'local-android',
        sourcePath: 'content://tree/123',
        title: 'Android 专辑',
        date: DateTime.now(),
        tracks: [
          Track(index: 0, name: 't', url: 'content://tree/123/01.mp3', duration: 1),
        ],
      );
      final kept = await service.cleanMissing([album]);
      expect(kept.length, 1);
      expect(kept[0].tracks.length, 1);
    });
  });
}
