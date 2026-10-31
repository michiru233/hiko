import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/lyrics/drawer_lyrics_view.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.99.63 回归：长句歌词（会换行）下，跨行远跳必须把当前句居中。
///
/// 旧实现粗定位按固定估算行高硬乘（`index × 45 × lyricsFontScale`）：
/// 长句折行后真实行高 70–130px，第 30 句的估算落点只有真实位置的四分之一，
/// 目标行仍在 ListView 构建窗口外；重试又重算同一个偏移，三次后放弃。
/// 实测（修复前）：第 20 句根本没被构建，列表停在 offset=900 一动不动——
/// 用户看到的正是「点开歌词后当前句不在中间、也不跟着唱」。
///
/// 修复后粗定位改用「最近已构建行 + 实测平均行高」推算，每轮重估、几轮内收敛。
const double _tolerancePx = 16;

void main() {
  Future<void> bootFullscreen(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FullscreenPlayerScreen()),
    ));
    await tester.pump();
  }

  testWidgets('全屏播放页：歌播到第 30 句才点开歌词，当前句仍居中', (tester) async {
    final Album album = wrappedLyricsAlbum();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(playbackProvider.notifier).state = playingAt(album, 0);
    await bootFullscreen(tester, container);

    // 播到第 30 句（每句 2 秒）才切到歌词层：目标行离首屏 30 行 × 约 130px
    container.read(playbackProvider.notifier).state = playingAt(album, 60.5);
    await tester.pump();
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();

    // 歌词控制器是懒创建的：进歌词层之后还要喂几次播放推进，它才会解析歌词
    // 并把 activeIndex 落到第 30 句。粗定位是「跳」不是「长动画」，所以这里
    // 只给 6 × 20ms（共 120ms，远小于 300ms 的平滑滚动时长）就该已经落位。
    for (var i = 0; i < 6; i++) {
      container.read(playbackProvider.notifier).state = playingAt(album, 60.5 + i * 0.02);
      await tester.pump(const Duration(milliseconds: 20));
    }
    final activeLine = find.textContaining('第 30 句');
    expect(
      activeLine,
      findsOneWidget,
      reason: '第 30 句还没被构建 —— 粗定位没把目标行带进构建窗口',
    );

    // 稳定后再量偏差
    await tester.pump(const Duration(milliseconds: 400));
    final lyricsList = find.byType(ListView);
    final deviation =
        (tester.getCenter(activeLine).dy - tester.getRect(lyricsList).center.dy).abs();
    expect(
      deviation,
      lessThan(_tolerancePx),
      reason: '第 30 句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
    );
  });

  testWidgets('全屏播放页：播放中跳到长句区（第 25 句）不靠长动画也能落位', (tester) async {
    final Album album = wrappedLyricsAlbum();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(playbackProvider.notifier).state = playingAt(album, 0);
    await bootFullscreen(tester, container);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();

    // 播到第 2 句后直接拖进度条式远跳（真机常见：往回/往前翻）
    container.read(playbackProvider.notifier).state = playingAt(album, 4.5);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    container.read(playbackProvider.notifier).state = playingAt(album, 50.5);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));

    final activeLine = find.textContaining('第 25 句');
    expect(activeLine, findsOneWidget, reason: '第 25 句没被构建');
    final lyricsList = find.byType(ListView);
    final deviation =
        (tester.getCenter(activeLine).dy - tester.getRect(lyricsList).center.dy).abs();
    expect(deviation, lessThan(_tolerancePx),
        reason: '第 25 句偏离中心 ${deviation.toStringAsFixed(1)}px');
  });

  testWidgets('专辑详情歌词 tab：长句远跳同样居中', (tester) async {
    final Album album = wrappedLyricsAlbum();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 详情页歌词 tab 高度 380（外层 SizedBox），可视区比全屏页小得多
    container.read(playbackProvider.notifier).state = playingAt(album, 60.5);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(height: 380, child: DrawerLyricsView())),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      container.read(playbackProvider.notifier).state = playingAt(album, 60.5 + i * 0.02);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 400));

    final activeLine = find.textContaining('第 30 句');
    expect(activeLine, findsOneWidget, reason: '第 30 句没被构建');
    final lyricsList = find.byType(ListView);
    final deviation =
        (tester.getCenter(activeLine).dy - tester.getRect(lyricsList).center.dy).abs();
    expect(deviation, lessThan(_tolerancePx),
        reason: '第 30 句偏离抽屉歌词中心 ${deviation.toStringAsFixed(1)}px');
  });
}
