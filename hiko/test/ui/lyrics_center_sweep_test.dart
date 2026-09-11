import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.72.0 回归：全屏播放页歌词，**从歌曲最开头到最末尾**当前句都要落在歌词区正中。
///
/// 1.71.1 修好了中段（第 5–135 句精确居中），但列表上下内边距固定 40px，滚动位置
/// 被 `clamp` 夹在 `0` 与 `maxScrollExtent` 上，首句与末句物理上没有空间可滚：
/// 实测第 0 句偏 145.0px、第 2 句 59.0px、第 138 句 102.0px、第 139 句 145.0px。
/// 真实歌词的最后一句往往覆盖很长的尾奏，所以「把进度条拖到歌的后段」高亮的正是
/// 这几句——这就是用户报的「拖到后方位置就不能正确居中」。
///
/// 修法是给列表上下各留半个可视高度（`lyricsCenterSlack`），首末句因此也能滚到正中。

const double _tolerancePx = 16;

void main() {
  // 0 / 139 是首末句（修复前 145.0px），2 / 138 是次首末句（修复前 59.0 / 102.0px），
  // 其余是 1.71.1 已修好的中段，列在这里防回退。
  for (final index in [0, 2, 5, 10, 20, 60, 100, 120, 130, 135, 138, 139]) {
    testWidgets('冷启动跳到第 $index 句，当前句落在歌词区垂直中心', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final Album album = lyricsAlbum();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // +0.5s 让二分查找稳稳落在第 index 句内
      final seconds = index * 2.0 + 0.5;
      container.read(playbackProvider.notifier).state = playingAt(album, seconds);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FullscreenPlayerScreen()),
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('显示歌词'));
      await tester.pump();
      // 歌词解析是异步的，多推几帧让它落地并完成粗跳 + 精确对齐
      for (var i = 0; i < 6; i++) {
        container.read(playbackProvider.notifier).state = playingAt(album, seconds);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final lyricsList = find.byType(ListView);
      final activeLine = find.text('第 $index 句');
      expect(lyricsList, findsOneWidget, reason: '应已切到歌词层');
      expect(
        activeLine,
        findsOneWidget,
        reason: '第 $index 句应已被滚入视口并构建（未构建＝自动滚动没生效）',
      );

      final deviation =
          (tester.getCenter(activeLine).dy - tester.getRect(lyricsList).center.dy).abs();
      expect(
        deviation,
        lessThan(_tolerancePx),
        reason: '第 $index 句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
      );
    });
  }
}
