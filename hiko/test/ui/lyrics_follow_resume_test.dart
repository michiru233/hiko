import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/lyrics/lyrics_controller.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/lyrics/drawer_lyrics_view.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.99.63 回归：自动跟随「断了以后能不能接回来」。
///
/// 用户报障原话是「跟随断了」，不是「高亮慢半拍」。两处成因各锁一条：
/// ① 手动滚动把跟随关掉，3 秒后开关虽然自动翻回 true，但去重记账还停在原来
///    那一句，于是列表停在用户手指留下的位置再不回来（探针实测偏差 Infinity）；
/// ② 长句换行时粗定位估算落空后放弃，之后每句都失败，列表永久冻结。
///
/// ②由 lyrics_wrapped_line_center_test.dart 锁；这里锁 ① 和「持续播放不中断」。
const double _tolerancePx = 24;

void main() {
  Future<ProviderContainer> bootFullscreen(WidgetTester tester, Album album) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(playbackProvider.notifier).state = playingAt(album, 0);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FullscreenPlayerScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    return container;
  }

  /// 把播放位置推到 [seconds]，并让歌词控制器处理完这次推进。
  Future<void> advance(
    WidgetTester tester,
    ProviderContainer container,
    Album album,
    double seconds,
  ) async {
    for (var i = 0; i < 6; i++) {
      container.read(playbackProvider.notifier).state =
          playingAt(album, seconds + i * 0.02);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  double deviationOf(WidgetTester tester, int index) {
    final line = find.textContaining('第 $index 句');
    expect(line, findsOneWidget, reason: '第 $index 句没被构建 —— 浮在视口外');
    return (tester.getCenter(line).dy - tester.getRect(find.byType(ListView)).center.dy)
        .abs();
  }

  testWidgets('全屏播放页：手动滑走 3 秒后自动恢复跟随，当前句立刻回中', (tester) async {
    final Album album = wrappedLyricsAlbum();
    final container = await bootFullscreen(tester, album);

    await advance(tester, container, album, 10.5);
    expect(deviationOf(tester, 5), lessThan(_tolerancePx));

    // 用户手指滑一下（真机上瞄一眼后面的歌词）
    await tester.drag(find.byType(ListView), const Offset(0, 260));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      container.read(lyricsProvider).autoScrollEnabled,
      isFalse,
      reason: '手动滚动后应暂停自动跟随',
    );

    // 播放继续往前走一句，此时跟随还是关着的
    await advance(tester, container, album, 14.5);
    expect(container.read(lyricsProvider).autoScrollEnabled, isFalse);

    // 放开 3 秒后计时应把跟随接回来，并且列表要自己回到当前句
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(container.read(lyricsProvider).autoScrollEnabled, isTrue);
    await tester.pump(const Duration(milliseconds: 400));

    final active = container.read(lyricsProvider).activeIndex;
    expect(
      deviationOf(tester, active),
      lessThan(_tolerancePx),
      reason: '跟随恢复后当前句没有回到正中（第 $active 句）',
    );
  });

  testWidgets('全屏播放页：连续播放 20 秒，每一句都跟着居中', (tester) async {
    final Album album = wrappedLyricsAlbum();
    final container = await bootFullscreen(tester, album);

    // 逐句推进，模拟真实播放（每句 2 秒）
    for (var index = 2; index <= 12; index++) {
      await advance(tester, container, album, index * 2 + 0.5);
      expect(
        container.read(lyricsProvider).activeIndex,
        index,
        reason: '播放到 ${index * 2 + 0.5}s 时高亮应停在第 $index 句',
      );
      expect(
        deviationOf(tester, index),
        lessThan(_tolerancePx),
        reason: '播到第 $index 句时没跟上（偏离中心过大）',
      );
    }
  });

  testWidgets('抽屉歌词视图：手动滑走 3 秒后同样回中', (tester) async {
    final Album album = wrappedLyricsAlbum();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(playbackProvider.notifier).state = playingAt(album, 10.5);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(height: 380, child: DrawerLyricsView())),
        ),
      ),
    ));
    await advance(tester, container, album, 10.5);
    expect(deviationOf(tester, 5), lessThan(_tolerancePx));

    // 往上滑很远：让当前句彻底离开构建窗口，才能锁住「恢复后要自己找回来」
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(lyricsProvider).autoScrollEnabled, isFalse);

    await advance(tester, container, album, 14.5);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(container.read(lyricsProvider).autoScrollEnabled, isTrue);
    await tester.pump(const Duration(milliseconds: 400));

    final active = container.read(lyricsProvider).activeIndex;
    expect(
      deviationOf(tester, active),
      lessThan(_tolerancePx),
      reason: '抽屉视图跟随恢复后没有回到第 $active 句',
    );
  });
}
