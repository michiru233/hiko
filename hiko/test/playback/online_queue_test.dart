import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_rules.dart';

/// 在线队列推进的基石假设：`PlaybackController._stepOnline` 对在线专辑调用
/// `QueueRules.step(albums: const [])`，依赖以下三点成立——
/// shuffle / list 分支不读专辑列表，album 分支越界时返回 null（再由
/// `onlineAdvance` 回调去在线列表里取相邻作品）。这里把这三点钉死。
void main() {
  Album onlineAlbum(String id, int trackCount) => Album(
        id: id,
        sourcePath: 'online://$id',
        title: id,
        date: DateTime(2026, 1, 1),
        tracks: [
          for (var i = 0; i < trackCount; i++)
            Track(index: i, name: 'track $i', url: 'http://x/stream/$id/$i'),
        ],
      );

  test('在线专辑标记 isOnline，本地专辑不标记', () {
    expect(onlineAlbum('online-1', 1).isOnline, isTrue);
    expect(onlineAlbum('local-abc', 1).isOnline, isFalse);
  });

  test('list 模式下专辑内前进/回绕，不依赖专辑列表', () {
    final album = onlineAlbum('online-1', 3);

    final next = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 0,
      mode: PlaybackMode.list,
      dir: 1,
    );
    expect(next, isNotNull);
    expect(next!.$1.id, 'online-1');
    expect(next.$2, 1);

    // 末曲前进 → 回绕到第 0 首（list 语义，不跨专辑）
    final wrap = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 2,
      mode: PlaybackMode.list,
      dir: 1,
    );
    expect(wrap!.$2, 0);

    // 首曲后退 → 回绕到末曲
    final back = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 0,
      mode: PlaybackMode.list,
      dir: -1,
    );
    expect(back!.$2, 2);
  });

  test('shuffle 模式下专辑内随机，不依赖专辑列表', () {
    final album = onlineAlbum('online-1', 5);
    final target = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 2,
      mode: PlaybackMode.shuffle,
      dir: 1,
    );
    expect(target, isNotNull);
    expect(target!.$1.id, 'online-1');
    expect(target.$2, isNot(2), reason: '随机不得连播同一首');
    expect(target.$2, inInclusiveRange(0, 4));
  });

  test('single 模式不在 step 内换曲（由 completed 路径重播）', () {
    final album = onlineAlbum('online-1', 2);
    final target = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 1,
      mode: PlaybackMode.single,
      dir: 1,
    );
    // single 不参与换曲：末曲前进时按 list 回绕（调用方在 completed 时另行重播）
    expect(target!.$2, 0);
  });

  test('album 模式越界返回 null——这正是交给 onlineAdvance 的信号', () {
    final album = onlineAlbum('online-1', 2);

    final forward = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 1,
      mode: PlaybackMode.album,
      dir: 1,
    );
    expect(forward, isNull, reason: '空专辑列表 → 无相邻作品可接续 → 交由在线层解析');

    final backward = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 0,
      mode: PlaybackMode.album,
      dir: -1,
    );
    expect(backward, isNull);
  });

  test('album 模式未越界时仍是专辑内推进', () {
    final album = onlineAlbum('online-1', 3);
    final target = QueueRules.step(
      albums: const [],
      current: album,
      queueIndex: 0,
      mode: PlaybackMode.album,
      dir: 1,
    );
    expect(target!.$1.id, 'online-1');
    expect(target.$2, 1);
  });

  test('无音轨的在线专辑不产生推进目标', () {
    final empty = onlineAlbum('online-1', 0);
    expect(
      QueueRules.step(
        albums: const [],
        current: empty,
        queueIndex: 0,
        mode: PlaybackMode.list,
        dir: 1,
      ),
      isNull,
    );
  });
}
