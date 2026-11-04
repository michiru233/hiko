import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/album_date_backfill.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/models/album.dart';

/// 老库缺失添加时间的补齐锁（1.99.69）。
///
/// 核心不变量：**补齐后按「最近添加」排序的结果 == 补齐前的数组顺序**。
/// 这条保证用户升级瞬间看到的列表不会整库翻转。
void main() {
  Album album(String id, int ms) => Album(
        id: id,
        sourcePath: '/tmp/$id',
        title: id,
        date: DateTime.fromMillisecondsSinceEpoch(ms),
        tracks: const [],
      );

  List<int> dates(List<Album> albums) =>
      [for (final a in albums) a.date.millisecondsSinceEpoch];

  List<String> ids(List<Album> albums) => [for (final a in albums) a.id];

  List<Album> recentDesc(List<Album> albums) => filterAlbums(
        albums: albums,
        view: '本地音声',
        filter: 'all',
        query: '',
        sort: 'recent_desc',
      );

  test('全都有时间：原实例返回（调用方据此不写盘）', () {
    final input = [album('a', 1000), album('b', 900)];
    expect(identical(backfillMissingDates(input), input), isTrue);
  });

  test('中间缺失段：紧跟上一条，逐条 -1ms', () {
    final out = backfillMissingDates([
      album('a', 1000),
      album('b', 0),
      album('c', 0),
      album('d', 900),
    ]);
    expect(dates(out), [1000, 999, 998, 900]);
  });

  test('前导缺失段：以第一个已知值为基准，下标越小越新', () {
    final out = backfillMissingDates([album('a', 0), album('b', 0), album('c', 900)]);
    expect(dates(out), [902, 901, 900]);
  });

  test('整库缺失：以注入的 now 为基准按下标递减', () {
    final out = backfillMissingDates(
      [album('a', 0), album('b', 0), album('c', 0)],
      now: DateTime.fromMillisecondsSinceEpoch(1000000),
    );
    expect(dates(out), [1000000, 999999, 999998]);
  });

  test('间隙为 0 时钳到已知值（允许相等），不出现倒序', () {
    final out = backfillMissingDates([
      album('a', 1000),
      album('b', 0),
      album('c', 0),
      album('d', 1000),
    ]);
    expect(dates(out), [1000, 1000, 1000, 1000]);
  });

  test('不补出 <=0 的时间（prev 已经是 1ms 时钳到 1）', () {
    final out = backfillMissingDates([album('a', 1), album('b', 0)]);
    expect(dates(out), [1, 1]);
  });

  test('幂等：补齐结果再喂回去，返回同一实例', () {
    final first = backfillMissingDates([album('a', 1000), album('b', 0)]);
    expect(identical(backfillMissingDates(first), first), isTrue);
  });

  test('补齐后 recent_desc == 补齐前数组顺序（升级不跳动）', () {
    final input = [
      album('newest', 5000),
      album('missing1', 0),
      album('missing2', 0),
      album('middle', 3000),
      album('missing3', 0),
      album('oldest', 1000),
    ];
    final out = backfillMissingDates(input);
    expect(ids(recentDesc(out)), ids(input));
  });

  test('补齐后 recent_asc == 数组逆序', () {
    final input = [
      album('newest', 5000),
      album('missing1', 0),
      album('middle', 3000),
      album('missing2', 0),
      album('oldest', 1000),
    ];
    final out = backfillMissingDates(input);
    final asc = filterAlbums(
      albums: out,
      view: '本地音声',
      filter: 'all',
      query: '',
      sort: 'recent_asc',
    );
    expect(ids(asc), ids(input).reversed.toList());
  });

  test('JSON 往返保留毫秒（迁移值重启后不漂移）', () {
    final out = backfillMissingDates([album('a', 1000), album('b', 0)]);
    final restored = Album.fromJson(out[1].toJson());
    expect(restored.date, out[1].date);
  });
}
