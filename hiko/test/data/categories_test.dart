import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/categories_provider.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/category.dart';
import 'package:hiko/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CategoryItem 数据模型', () {
    test('JSON 序列化与反序列化', () {
      const item = CategoryItem(name: '测试分类', colorValue: 0xFFEA8C79);
      final json = item.toJson();
      final restored = CategoryItem.fromJson(json);
      expect(restored.name, '测试分类');
      expect(restored.colorValue, 0xFFEA8C79);
      expect(restored, item);
    });

    test('缺失字段使用默认值', () {
      final restored = CategoryItem.fromJson(const {});
      expect(restored.name, '未命名分类');
      expect(restored.colorValue, 0xFF8E83E7);
    });
  });

  group('CategoriesNotifier 状态变更与专辑联动', () {
    test('添加分类、重命名同步更新专辑 genre、删除分类重置为未分类', () async {
      final tmp = Directory.systemTemp.createTempSync('hiko-cat-test');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final store = LibraryStore(overrideDir: Directory('${tmp.path}/data'));
      final container = ProviderContainer(
        overrides: [
          libraryStoreProvider.overrideWithValue(store),
        ],
      );
      final catNotifier = container.read(categoriesProvider.notifier);
      final libNotifier = container.read(libraryProvider.notifier);

      await catNotifier.load();
      expect(container.read(categoriesProvider).length, 4);

      // 添加自定义分类
      final added = await catNotifier.addCategory(
        const CategoryItem(name: '耳骚体验', colorValue: 0xFFED7D95),
      );
      expect(added, isTrue);
      expect(container.read(categoriesProvider).any((c) => c.name == '耳骚体验'), isTrue);

      // 创建归入该分类的专辑
      final album = Album(
        id: 'test-1',
        sourcePath: '/tmp/test',
        title: '测试耳骚',
        genre: '耳骚体验',
        date: DateTime.now(),
        tracks: const [],
      );
      await libNotifier.mergeNew([album]);
      expect(container.read(libraryProvider).single.genre, '耳骚体验');

      // 重命名分类为「极致耳骚」，验证专辑自动级联更新
      await catNotifier.updateCategory(
        '耳骚体验',
        const CategoryItem(name: '极致耳骚', colorValue: 0xFFED7D95),
      );
      expect(container.read(libraryProvider).single.genre, '极致耳骚');

      // 删除分类，验证专辑 genre 安全回退到「未分类」
      await catNotifier.removeCategory('极致耳骚');
      expect(container.read(categoriesProvider).any((c) => c.name == '极致耳骚'), isFalse);
      expect(container.read(libraryProvider).single.genre, '未分类');
    });

    test('mergeNew 扫描新专辑时保留已有专辑的分类、收藏、播放进度与刮削元数据', () async {
      final tmp = Directory.systemTemp.createTempSync('hiko-merge-test');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final store = LibraryStore(overrideDir: Directory('${tmp.path}/data'));
      final container = ProviderContainer(
        overrides: [
          libraryStoreProvider.overrideWithValue(store),
        ],
      );
      final libNotifier = container.read(libraryProvider.notifier);

      final originalDate = DateTime(2025, 1, 1);
      final oldAlbum = Album(
        id: 'local-123456',
        sourcePath: '/path/to/RJ123456',
        title: '已刮削中文译名',
        artist: '知名社团',
        albumArtist: '知名社团',
        rjCode: 'RJ123456',
        dlsiteTitle: '【原版日文】タイトル',
        tags: ['治愈', '催眠', '耳骚'],
        genre: 'ASMR',
        favorite: true,
        played: 450.0,
        date: originalDate,
        tracks: [
          Track(index: 1, name: '01.mp3', url: 'file:///path/to/RJ123456/01.mp3', duration: 300),
          Track(index: 2, name: '02.mp3', url: 'file:///path/to/RJ123456/02.mp3', duration: 300),
        ],
      );

      await libNotifier.mergeNew([oldAlbum]);
      expect(container.read(libraryProvider).single.genre, 'ASMR');
      expect(container.read(libraryProvider).single.favorite, isTrue);

      // 模拟重新扫描该目录（或扫描包含此专辑的父目录），扫描器生成初始状态的 fresh 专辑（genre 默认为未分类）
      final scannedFreshAlbum = Album(
        id: 'local-123456',
        sourcePath: '/path/to/RJ123456',
        title: 'RJ123456',
        artist: '本地导入',
        genre: '未分类',
        favorite: false,
        played: 0,
        date: DateTime.now(),
        tracks: [
          Track(index: 1, name: '01.mp3', url: 'file:///path/to/RJ123456/01.mp3', duration: 300),
          Track(index: 2, name: '02.mp3', url: 'file:///path/to/RJ123456/02.mp3', duration: 300),
          Track(index: 3, name: '03.mp3', url: 'file:///path/to/RJ123456/03.mp3', duration: 300),
        ],
      );

      // 另外有一张纯新专辑
      final brandNewAlbum = Album(
        id: 'local-999999',
        sourcePath: '/path/to/RJ999999',
        title: '新导入专辑',
        genre: '未分类',
        date: DateTime.now(),
        tracks: [
          Track(index: 1, name: 'track.mp3', url: 'file:///path/to/RJ999999/track.mp3', duration: 200),
        ],
      );

      await libNotifier.mergeNew([scannedFreshAlbum, brandNewAlbum]);

      final albums = container.read(libraryProvider);
      expect(albums.length, 2);

      final merged = albums.firstWhere((a) => a.id == 'local-123456');
      // 验证分类完全保留，没有丢失变为「未分类」
      expect(merged.genre, 'ASMR');
      // 验证收藏、播放进度、刮削标题与标签、添加时间保留
      expect(merged.favorite, isTrue);
      expect(merged.played, 450.0);
      expect(merged.title, '已刮削中文译名');
      expect(merged.dlsiteTitle, '【原版日文】タイトル');
      expect(merged.tags, ['治愈', '催眠', '耳骚']);
      expect(merged.date, originalDate);
      // 验证新音轨已正常加入
      expect(merged.tracks.length, 3);

      final brandNew = albums.firstWhere((a) => a.id == 'local-999999');
      expect(brandNew.genre, '未分类');
    });
  });

  group('filterAlbums 通用分类与视图过滤', () {
    final a1 = Album(
      id: '1',
      sourcePath: '/tmp/1',
      title: 'ASMR 睡眠音声',
      artist: '社团 A',
      genre: 'ASMR',
      date: DateTime.now(),
      played: 100,
      tracks: const [],
    );

    final a2 = Album(
      id: '2',
      sourcePath: '/tmp/2',
      title: '催眠治愈小品',
      artist: '社团 B',
      genre: '治愈系',
      favorite: true,
      date: DateTime.now(),
      tracks: const [],
    );

    final a3 = Album(
      id: '3',
      sourcePath: '/tmp/3',
      title: '同人日常剧情',
      artist: '社团 C',
      genre: '同人剧情', // 用户自定义的新分类
      date: DateTime.now(),
      tracks: const [],
    );

    final allAlbums = [a1, a2, a3];

    test('全部音声 视图返回全部', () {
      final res = filterAlbums(
        albums: allAlbums,
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'recent',
      );
      expect(res.length, 3);
    });

    test('收藏夹 视图仅返回收藏', () {
      final res = filterAlbums(
        albums: allAlbums,
        view: '收藏夹',
        filter: 'all',
        query: '',
        sort: 'recent',
      );
      expect(res.length, 1);
      expect(res.single.id, '2');
    });

    test('自定义分类 视图精准匹配 genre', () {
      final res = filterAlbums(
        albums: allAlbums,
        view: '同人剧情',
        filter: 'all',
        query: '',
        sort: 'recent',
      );
      expect(res.length, 1);
      expect(res.single.title, '同人日常剧情');
    });

    test('搜索关键词匹配自定义分类名', () {
      final res = filterAlbums(
        albums: allAlbums,
        view: '全部音声',
        filter: 'all',
        query: '同人剧情',
        sort: 'recent',
      );
      expect(res.length, 1);
      expect(res.single.id, '3');
    });

    test('按 duration 排序时基于真实 totalDuration（秒）降序排列', () {
      final albShortManyTracks = Album(
        id: 'short',
        sourcePath: '/tmp/short',
        title: '短音声多音轨',
        artist: '社团 1',
        genre: '未分类',
        duration: 20, // 20 首
        totalDuration: 1800, // 30 分钟 (1800 秒)
        date: DateTime.now(),
        tracks: const [],
      );

      final albLongFewTracks = Album(
        id: 'long',
        sourcePath: '/tmp/long',
        title: '长音声单音轨',
        artist: '社团 2',
        genre: '未分类',
        duration: 1, // 1 首
        totalDuration: 36000, // 10 小时 (36000 秒)
        date: DateTime.now(),
        tracks: const [],
      );

      final albMedium = Album(
        id: 'medium',
        sourcePath: '/tmp/medium',
        title: '中等时长',
        artist: '社团 3',
        genre: '未分类',
        duration: 5,
        totalDuration: 7200, // 2 小时 (7200 秒)
        date: DateTime.now(),
        tracks: const [],
      );

      final res = filterAlbums(
        albums: [albShortManyTracks, albLongFewTracks, albMedium],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'duration_desc',
      );

      expect(res.map((a) => a.id).toList(), ['long', 'medium', 'short']);

      final resAsc = filterAlbums(
        albums: [albShortManyTracks, albLongFewTracks, albMedium],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'duration_asc',
      );

      expect(resAsc.map((a) => a.id).toList(), ['short', 'medium', 'long']);
    });

    test('标题 A-Z 正序与 Z-A 倒序排序测试', () {
      final a = Album(
        id: 'a',
        sourcePath: '/tmp/a',
        title: 'A 音声',
        artist: '社团',
        genre: '未分类',
        date: DateTime.now(),
        tracks: const [],
      );
      final b = Album(
        id: 'b',
        sourcePath: '/tmp/b',
        title: 'B 音声',
        artist: '社团',
        genre: '未分类',
        date: DateTime.now(),
        tracks: const [],
      );

      final resAsc = filterAlbums(
        albums: [b, a],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'title_asc',
      );
      expect(resAsc.map((x) => x.id).toList(), ['a', 'b']);

      final resDesc = filterAlbums(
        albums: [a, b],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'title_desc',
      );
      expect(resDesc.map((x) => x.id).toList(), ['b', 'a']);
    });

    test('最近添加（新到旧）与最早添加（旧到新）排序测试', () {
      final a1 = Album(
        id: 'first',
        sourcePath: '/tmp/1',
        title: '第1张',
        date: DateTime.now(),
        tracks: const [],
      );
      final a2 = Album(
        id: 'second',
        sourcePath: '/tmp/2',
        title: '第2张',
        date: DateTime.now(),
        tracks: const [],
      );

      final resRecent = filterAlbums(
        albums: [a1, a2],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'recent_desc',
      );
      expect(resRecent.map((x) => x.id).toList(), ['first', 'second']);

      final resOldest = filterAlbums(
        albums: [a1, a2],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'recent_asc',
      );
      expect(resOldest.map((x) => x.id).toList(), ['second', 'first']);
    });

    test('按专辑艺术家 artist_asc 排序：专辑数多的艺术家整组排前（2 张排在 1 张前），同数按艺术家名自然升序，组内按标题自然排序升序', () {
      // Alpha 只有 1 张但名字最先；Beta/Gamma 各 2 张 → Beta、Gamma 组须排在 Alpha 前，Beta 组又排在 Gamma 组前
      final a1 = Album(
        id: 'a1',
        sourcePath: '/tmp/1',
        title: 'A 作品',
        albumArtist: 'Alpha',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final b1 = Album(
        id: 'b1',
        sourcePath: '/tmp/b1',
        title: 'Z 作品',
        albumArtist: 'Beta',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final b2 = Album(
        id: 'b2',
        sourcePath: '/tmp/b2',
        title: 'M 作品',
        albumArtist: 'Beta',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final g1 = Album(
        id: 'g1',
        sourcePath: '/tmp/g1',
        title: 'B 作品',
        albumArtist: 'Gamma',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final g2 = Album(
        id: 'g2',
        sourcePath: '/tmp/g2',
        title: 'C 作品',
        albumArtist: 'Gamma',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );

      final res = filterAlbums(
        albums: [a1, g2, b1, g1, b2],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'artist_asc',
      );

      expect(res.map((x) => x.id).toList(), ['b2', 'b1', 'g1', 'g2', 'a1']);
    });

    test('按专辑艺术家 artist_asc 升序排序：albumArtist 为空时回退至 artist 字段', () {
      final a1 = Album(
        id: '1',
        sourcePath: '/tmp/1',
        title: '作品 1',
        albumArtist: 'Alpha',
        artist: 'Other',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final a2 = Album(
        id: '2',
        sourcePath: '/tmp/2',
        title: '作品 2',
        albumArtist: '',
        artist: 'Beta',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final a3 = Album(
        id: '3',
        sourcePath: '/tmp/3',
        title: '作品 3',
        albumArtist: 'Gamma',
        artist: '',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );

      final res = filterAlbums(
        albums: [a3, a2, a1],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'artist_asc',
      );

      expect(res.map((x) => x.id).toList(), ['1', '2', '3']);
    });

    test('按专辑艺术家 artist_asc 升序排序：albumArtist 和 artist 皆空时排在最后且按标题自然排序', () {
      final a1 = Album(
        id: '1',
        sourcePath: '/tmp/1',
        title: '作品 1',
        albumArtist: 'Alpha',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final aEmpty1 = Album(
        id: 'e1',
        sourcePath: '/tmp/e1',
        title: 'Z 无艺术家',
        albumArtist: '',
        artist: '',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final aEmpty2 = Album(
        id: 'e2',
        sourcePath: '/tmp/e2',
        title: 'A 无艺术家',
        albumArtist: '',
        artist: '',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );

      final res = filterAlbums(
        albums: [aEmpty1, a1, aEmpty2],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'artist_asc',
      );

      expect(res.map((x) => x.id).toList(), ['1', 'e2', 'e1']);
    });

    test('按专辑艺术家 artist_asc 排序：同名艺术家带/不带尾随空格视为同一人归为一组（旧库标签脏数据）', () {
      // 3 张「バイコーンの森」+ 2 张「バイコーンの森 」（尾随空格）→ trim 后同组共 5 张，
      // 整组排最前；组内按标题自然排序；另一艺术家独立成组排后
      final a1 = Album(
        id: '1',
        sourcePath: '/tmp/1',
        title: 'A 作品',
        albumArtist: 'バイコーンの森',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final a2 = Album(
        id: '2',
        sourcePath: '/tmp/2',
        title: 'M 作品',
        albumArtist: 'バイコーンの森 ',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final a3 = Album(
        id: '3',
        sourcePath: '/tmp/3',
        title: 'Z 作品',
        albumArtist: 'バイコーンの森 ',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final b1 = Album(
        id: 'b1',
        sourcePath: '/tmp/b1',
        title: 'B 作品',
        albumArtist: 'Beta',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );
      final b2 = Album(
        id: 'b2',
        sourcePath: '/tmp/b2',
        title: 'C 作品',
        albumArtist: 'Beta',
        genre: 'ASMR',
        date: DateTime.now(),
        tracks: const [],
      );

      final res = filterAlbums(
        albums: [a2, b1, a1, b2, a3],
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'artist_asc',
      );

      expect(res.map((x) => x.id).toList(), ['1', '2', '3', 'b1', 'b2']);
    });
  });
}
