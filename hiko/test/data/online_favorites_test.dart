import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/online/online_favorites.dart';
import 'package:hiko/data/online/online_models.dart';

/// 1.93.0 收藏索引：角标、收藏页列表、多选菜单预勾选都读这一份结构，
/// 所以它的四个查询（并集 / 归属 / 计数 / 去重排序）值得单独钉住。
void main() {
  OnlineWork work(int id) => OnlineWork(id: id, title: '作品 $id');

  OnlinePlaylist playlist(String id, String name, {int count = 0}) =>
      OnlinePlaylist(id: id, name: name, worksCount: count);

  /// liked={1,2}，听完={2,3}：1 只在一个歌单，2 在两个
  OnlineFavorites sample() => OnlineFavorites(
        playlists: [
          playlist('liked', OnlinePlaylist.sysLiked),
          playlist('done', '听完'),
        ],
        worksById: {
          'liked': [work(1), work(2)],
          'done': [work(3), work(2)],
        },
      );

  group('查询', () {
    test('allWorkIds 是并集（重复的作品只算一次）', () {
      expect(sample().allWorkIds, {1, 2, 3});
    });

    test('playlistsOf 给出作品所处的歌单集合；不在任何歌单里返回空集', () {
      final index = sample();
      expect(index.playlistsOf(1), {'liked'});
      expect(index.playlistsOf(2), {'liked', 'done'});
      expect(index.playlistsOf(99), isEmpty);
      expect(index.contains(2), isTrue);
      expect(index.contains(99), isFalse);
    });

    test('countOf(null) 是并集大小，其余按歌单算', () {
      final index = sample();
      expect(index.countOf(null), 3);
      expect(index.countOf('liked'), 2);
      expect(index.countOf('done'), 2);
      expect(index.countOf('不存在'), 0);
    });

    test('worksOf(null) 按歌单顺序拼接并去重；指定歌单则原样返回', () {
      final index = sample();
      expect(index.worksOf(null).map((w) => w.id), [1, 2, 3],
          reason: 'liked 先出 1、2，done 里 2 已出现过只留 3');
      expect(index.worksOf('done').map((w) => w.id), [3, 2]);
      expect(index.worksOf('不存在'), isEmpty);
    });

    test('空索引：任何查询都安全返回空', () {
      final empty = OnlineFavorites.empty;
      expect(empty.playlists, isEmpty);
      expect(empty.allWorkIds, isEmpty);
      expect(empty.worksOf(null), isEmpty);
      expect(empty.playlistsOf(1), isEmpty);
      expect(empty.countOf(null), 0);
    });
  });

  group('appliedLocally（收藏菜单确认后的即时反馈）', () {
    test('加入一个歌单：作品出现在该歌单最前（服务端也是最近加入在前）', () {
      final index = sample().appliedLocally(
        work: work(9),
        diff: const PlaylistDiff(addTo: ['done'], removeFrom: []),
      );
      expect(index.worksOf('done').map((w) => w.id), [9, 3, 2]);
      expect(index.worksOf('liked').map((w) => w.id), [1, 2],
          reason: '没点到的歌单不受影响');
      expect(index.playlistsOf(9), {'done'});
    });

    test('移出一个歌单：只从该歌单摘掉，其他歌单的归属还在', () {
      final index = sample().appliedLocally(
        work: work(2),
        diff: const PlaylistDiff(addTo: [], removeFrom: ['liked']),
      );
      expect(index.worksOf('liked').map((w) => w.id), [1]);
      expect(index.worksOf('done').map((w) => w.id), [3, 2]);
      expect(index.playlistsOf(2), {'done'});
    });

    test('一次既加又减：两边都生效', () {
      final index = sample().appliedLocally(
        work: work(2),
        diff: const PlaylistDiff(addTo: ['extra'], removeFrom: ['liked']),
      );
      expect(index.playlistsOf(2), {'done'},
          reason: 'extra 不在索引里，加不进去也不该报错');
      expect(index.worksOf('liked').map((w) => w.id), [1]);
    });

    test('重复加入不产生副本', () {
      final index = sample().appliedLocally(
        work: work(1),
        diff: const PlaylistDiff(addTo: ['liked'], removeFrom: []),
      );
      expect(index.worksOf('liked').map((w) => w.id), [1, 2]);
    });

    test('移出本来就不在的歌单是 no-op', () {
      final index = sample().appliedLocally(
        work: work(1),
        diff: const PlaylistDiff(addTo: [], removeFrom: ['done']),
      );
      expect(index.worksOf('done').map((w) => w.id), [3, 2]);
    });

    test('空差分原样返回，不白白重建结构', () {
      final before = sample();
      expect(
        identical(
          before.appliedLocally(work: work(1), diff: PlaylistDiff.empty),
          before,
        ),
        isTrue,
      );
    });

    test('改动后歌单列表与顺序保持不变', () {
      final index = sample().appliedLocally(
        work: work(9),
        diff: const PlaylistDiff(addTo: ['liked'], removeFrom: []),
      );
      expect(index.playlists.map((p) => p.id), ['liked', 'done']);
    });
  });

  group('OnlineFavoritesState', () {
    test('加载完成后 loaded 为 true，出错时为 false', () {
      expect(
        OnlineFavoritesState(index: OnlineFavorites.empty).loaded,
        isTrue,
      );
      expect(
        OnlineFavoritesState(index: OnlineFavorites.empty, loading: true).loaded,
        isFalse,
      );
      expect(
        OnlineFavoritesState(index: OnlineFavorites.empty, error: 'x').loaded,
        isFalse,
      );
    });

    test('copyWith(clearError) 能清掉错误', () {
      final failed = OnlineFavoritesState(
        index: OnlineFavorites.empty,
        error: '连不上',
      );
      expect(failed.copyWith(loading: true, clearError: true).error, isNull);
    });
  });
}
