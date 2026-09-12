import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/models/album.dart';

void main() {
  // 1.77 详情页胶囊回传筛选：社团按 albumArtist、声优按 artist，contains 容忍尾随空格
  final a1 = Album(
    id: '1',
    sourcePath: '/tmp/1',
    title: '作品一',
    artist: 'えもこ、大山チロル',
    albumArtist: 'えもこ本舗 ',
    date: DateTime(2026),
    tracks: const [],
  );
  final a2 = Album(
    id: '2',
    sourcePath: '/tmp/2',
    title: '作品二',
    artist: 'えもこ',
    albumArtist: '',
    date: DateTime(2026),
    tracks: const [],
  );
  final a3 = Album(
    id: '3',
    sourcePath: '/tmp/3',
    title: '作品三',
    artist: '別人',
    albumArtist: '其他社团',
    date: DateTime(2026),
    tracks: const [],
  );

  List<Album> run({
    List<Album> albums = const [],
    String? circle,
    String? voice,
  }) {
    return filterAlbums(
      albums: albums,
      view: '全部音声',
      filter: 'all',
      query: '',
      sort: 'recent',
      circleFilter: circle,
      voiceFilter: voice,
    );
  }

  test('circleFilter 按 albumArtist contains 匹配（含尾随空格数据）', () {
    final res = run(albums: [a1, a2, a3], circle: 'えもこ本舗');
    expect(res.map((a) => a.id), ['1']);
  });

  test('voiceFilter 按 artist contains 匹配多声优串', () {
    final res = run(albums: [a1, a2, a3], voice: '大山チロル');
    expect(res.map((a) => a.id), ['1']);
    expect(run(albums: [a1, a2, a3], voice: 'えもこ').map((a) => a.id), ['1', '2']);
  });

  test('两参均为空 = 原行为（返回全部）', () {
    expect(run(albums: [a1, a2, a3]).length, 3);
  });

  test('FilterAlbumsMemo 缓存键包含新参数（换筛选即失效重算）', () {
    final memo = FilterAlbumsMemo();
    final albums = [a1, a2, a3];
    expect(memo.get(albums: albums, view: '全部音声', filter: 'all', query: '', sort: 'recent').length, 3);
    final hit1 = memo.hits;
    final circleRes = memo.get(
      albums: albums,
      view: '全部音声',
      filter: 'all',
      query: '',
      sort: 'recent',
      circleFilter: 'えもこ本舗',
    );
    expect(circleRes.map((a) => a.id), ['1']);
    expect(memo.hits, hit1); // 参数变化不得命中缓存
    expect(memo.get(albums: albums, view: '全部音声', filter: 'all', query: '', sort: 'recent', circleFilter: 'えもこ本舗').length, 1);
    expect(memo.hits, hit1 + 1); // 同参数再取命中缓存
  });
}
