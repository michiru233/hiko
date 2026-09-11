import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/lyrics/lyrics_controller.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.73.0 回归：全屏播放页用点击手势在「黑胶唱片层 / 歌词层」之间切换。
///
/// 三个入口共用 `_setShowLyrics`：点中央区域进歌词、点歌词页留白回唱片、AppBar 图标按钮。
/// 两个容易被改坏的点各自用一条用例守住：
/// - 点**歌词文字**不能翻页（靠每行那层故意吸收点击的手势，外层手势才收不到）；
/// - 切到歌词页必须重新定位到当前句（歌词子树切走即销毁，重进从 offset 0 重建，
///   而滚动记账挂在 State 上跨切换存活，不重置就会看到歌曲开头）。
///
/// 交叉淡入 220ms + 定位动画 300ms，所以每次切换后都要把这几帧推完再断言。
void main() {
  /// 组装播放页并进入指定的播放位置；返回 container 供读取状态。
  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester,
    double seconds,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Album album = lyricsAlbum();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(playbackProvider.notifier).state = playingAt(album, seconds);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FullscreenPlayerScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  /// 把 crossfade / 定位动画推完。传 [seconds] 时同时推进播放位置。
  Future<void> settle(
    WidgetTester tester,
    ProviderContainer container,
    double seconds,
  ) async {
    for (var i = 0; i < 6; i++) {
      container.read(playbackProvider.notifier).state = playingAt(
        container.read(playbackProvider).album!,
        seconds,
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 中央区域（AnimatedSwitcher 撑满 Expanded）的矩形。
  Rect centerArea(WidgetTester tester) =>
      tester.getRect(find.byType(AnimatedSwitcher));

  bool onLyricsPage() => find.byTooltip('显示封面').evaluate().isNotEmpty;
  bool onVinylPage() => find.byTooltip('显示歌词').evaluate().isNotEmpty;

  testWidgets('①点中央区域（唱片圆盘之外）进入歌词页', (tester) async {
    final container = await pumpPlayer(tester, 0.5);
    expect(onVinylPage(), isTrue, reason: '初始应停在唱片层');

    final area = centerArea(tester);
    // 唱片直径 320px 居中于约 418px 高的中央区，圆盘上沿距顶约 49px；
    // 取距顶 40px 处——在中央区内、但在唱片圆盘之外，只有铺满整片的手势才收得到。
    await tester.tapAt(Offset(area.center.dx, area.top + 40));
    await tester.pump();
    await settle(tester, container, 0.5);

    expect(onLyricsPage(), isTrue, reason: '点中央区域后应切到歌词层');
    expect(find.byType(ListView), findsOneWidget, reason: '歌词列表应已出现');
  });

  testWidgets('②AppBar 图标按钮双向切换仍可用', (tester) async {
    final container = await pumpPlayer(tester, 0.5);

    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 0.5);
    expect(onLyricsPage(), isTrue, reason: '按钮应能切到歌词层');

    await tester.tap(find.byTooltip('显示封面'));
    await tester.pump();
    await settle(tester, container, 0.5);
    expect(onVinylPage(), isTrue, reason: '按钮应能切回唱片层');
  });

  testWidgets('③点歌词页留白（首句之上）回到唱片页', (tester) async {
    final container = await pumpPlayer(tester, 0.5);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 0.5);
    expect(onLyricsPage(), isTrue, reason: '前置条件：已在歌词页');

    // 列表上下各留半个可视高度，顶部这块留白里没有任何歌词
    final list = tester.getRect(find.byType(ListView));
    expect(list.height, 418, reason: '歌词区尺寸不应被 AnimatedSwitcher 改变');
    await tester.tapAt(Offset(list.center.dx, list.top + list.height * 0.15));
    await tester.pump();
    await settle(tester, container, 0.5);

    expect(onVinylPage(), isTrue, reason: '点留白后应切回唱片层');
    expect(find.byType(ListView), findsNothing, reason: '歌词列表应已移除');
  });

  testWidgets('④点歌词文字不翻页（仍停在歌词页）', (tester) async {
    final container = await pumpPlayer(tester, 0.5);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 0.5);

    final line = find.text('第 0 句');
    expect(line, findsOneWidget, reason: '前置条件：第 0 句在视口内');
    await tester.tap(line);
    await tester.pump();
    await settle(tester, container, 0.5);

    expect(onLyricsPage(), isTrue, reason: '点歌词文字不该翻回唱片层');
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('⑤在歌词页拖动列表不会触发切换', (tester) async {
    final container = await pumpPlayer(tester, 100.5);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 100.5);

    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pump();
    // 手动滑动会挂一个 3 秒的自动跟随恢复定时器，推过去免得它悬着
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));

    expect(onLyricsPage(), isTrue, reason: '拖动歌词列表不该被当成点击而翻页');
  });

  testWidgets('⑥进歌词页后当前句居中', (tester) async {
    final container = await pumpPlayer(tester, 100.5);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 100.5);

    final list = find.byType(ListView);
    final line = find.text('第 50 句');
    expect(line, findsOneWidget, reason: '前置条件：第 50 句在视口内');
    final deviation =
        (tester.getCenter(line).dy - tester.getRect(list).center.dy).abs();
    expect(
      deviation,
      lessThan(16),
      reason: '第 50 句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
    );
  });

  testWidgets('⑦切到唱片页再切回歌词页，当前句仍居中且在视口内', (tester) async {
    final container = await pumpPlayer(tester, 100.5);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 100.5);

    // 切走再切回：歌词列表被销毁重建，重进必须重新定位
    await tester.tap(find.byTooltip('显示封面'));
    await tester.pump();
    await settle(tester, container, 100.5);
    expect(onVinylPage(), isTrue, reason: '前置条件：已切到唱片层');

    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 100.5);

    final list = find.byType(ListView);
    final line = find.text('第 50 句');
    expect(line, findsOneWidget, reason: '切回歌词页后第 50 句不在视口里 —— 看到的是列表顶部而不是当前句');
    final deviation =
        (tester.getCenter(line).dy - tester.getRect(list).center.dy).abs();
    expect(
      deviation,
      lessThan(16),
      reason: '切回后第 50 句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
    );
  });
}
