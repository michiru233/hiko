import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/lyrics/lyrics_controller.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.72.0 回归：拖动进度条松手后必须**立刻**恢复自动跟随并重新居中。
///
/// 用户手动滑走歌词时 `autoScrollEnabled` 会被关掉并挂一个 3 秒的恢复定时器，而
/// `resumeAutoScroll()` 只翻转标志、不触发滚动。于是「手动滑走歌词 → 3 秒内拖进度条」
/// 这段窗口里落地不居中，要等下一句变化才自愈。
///
/// 拖动进度条本身就是「我要跳到那一刻」的明确意图，落地就该看见那一刻的歌词，
/// 所以 `onChangeEnd` 除了恢复跟随，还要把「已滚到第几句」的记账清零 ——
/// 否则拖回**同一句**内时索引没变，不会触发滚动（下面第二条用例专门守这一点）。
///
/// 夹具用 10 行 / 20 秒：每行 2 秒，第 5 句覆盖 10–12 秒，于是滑到 55% 恰好落在
/// 同一句内、滑到 85% 落在第 8 句，两个场景都能用一次真实手势精确命中。
void main() {
  /// 播放到 [followSeconds]、手动滑走歌词、再用手势把进度条拖到 [fraction] 松手，
  /// 返回「当前句中心 − 歌词区中心」的绝对偏差。
  Future<double> dragProgressAfterManualScroll(
    WidgetTester tester,
    double followSeconds,
    double fraction,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Album album = lyricsAlbum(lines: 10, durationSeconds: 20);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 先跟到第 5 句：每行 2 秒，10.0 秒 → 第 5 句
    container.read(playbackProvider.notifier).state = playingAt(album, followSeconds);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FullscreenPlayerScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      container.read(playbackProvider.notifier).state = playingAt(album, followSeconds);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final lyricsList = find.byType(ListView);
    final indexBefore = container.read(lyricsProvider).activeIndex;
    expect(indexBefore, 5, reason: '前置条件：跟到第 5 句');

    // 用户手动滑走歌词 —— 自动跟随被关掉，3 秒恢复定时器启动
    await tester.drag(lyricsList, const Offset(0, -220));
    await tester.pump();
    expect(
      container.read(lyricsProvider).autoScrollEnabled,
      isFalse,
      reason: '前置条件：手动滑动歌词后自动跟随应被暂停',
    );

    // 仍在 3 秒窗口内拖动进度条，松手
    final rect = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(rect.centerLeft + const Offset(8, 0));
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(
        Offset(rect.left + rect.width * fraction * i / 8.0, rect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pump();
    // 跨行远跳要跨三帧才走完「调度 → 粗定位 → 精确对齐 → 动画」：粗定位那一帧把
    // 目标行带进构建范围，下一帧才拿到真实几何并启动 300ms 动画。真机 16ms 连续
    // 出帧无感，测试里必须把这几帧推完。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final index = container.read(lyricsProvider).activeIndex;
    final activeLine = find.text('第 $index 句');
    expect(
      activeLine,
      findsOneWidget,
      reason: '松手后第 $index 句没被滚进视口 —— 没有恢复跟随（修复前就是这个症状）',
    );

    return (tester.getCenter(activeLine).dy - tester.getRect(lyricsList).center.dy).abs();
  }

  testWidgets('手动滑走后拖到较远处，当前句立即回到正中', (tester) async {
    // 20 秒的 85% ≈ 17s → 第 8 句（与拖动前的第 5 句不同句）
    final deviation = await dragProgressAfterManualScroll(tester, 10.0, 0.85);
    expect(
      deviation,
      lessThan(16),
      reason: '当前句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
    );
  });

  testWidgets('手动滑走后拖回同一句内，当前句也要立即回到正中', (tester) async {
    // 20 秒的 55% ≈ 11s → 仍是第 5 句：索引没变，全靠 onChangeEnd 清零记账才会重滚
    final deviation = await dragProgressAfterManualScroll(tester, 10.0, 0.55);
    expect(
      deviation,
      lessThan(16),
      reason: '同一句内拖动后当前句中心偏离歌词区中心 '
          '${deviation.toStringAsFixed(1)}px（记账没清零就不会重滚）',
    );
  });
}
