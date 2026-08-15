import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/categories_provider.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/category.dart';
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
        sort: 'duration',
      );

      expect(res.map((a) => a.id).toList(), ['long', 'medium', 'short']);
    });
  });
}
