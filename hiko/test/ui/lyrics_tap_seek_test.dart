import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.76.0 回归：点某句歌词跳播到该句开头并立即居中（对齐详情页歌词 tab）。
///
/// 手势分层语义（1.73/1.75/1.76）：点歌词文字=跳播该句（仍不翻页），
/// 点行间空隙/留白=回唱片层，拖动滚动不误触。
void main() {
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

  /// 把 crossfade / 定位动画推完。歌词解析与跟随依赖播放状态更新事件，
  /// 每帧像真实播放那样刷新一次 playbackProvider（对齐旧 toggle 测试）。
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

  bool onLyricsPage() => find.byTooltip('显示封面').evaluate().isNotEmpty;

  testWidgets('点「第 53 句」跳播到该句起点（106s）且仍停在歌词页', (tester) async {
    final container = await pumpPlayer(tester, 100.5);
    expect(find.byTooltip('显示歌词').evaluate().isNotEmpty, isTrue);

    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 100.5);
    expect(onLyricsPage(), isTrue);

    // 当前句是第 50 句（100.5s / 2s），第 53 句在视口内下方
    final line = find.text('第 53 句');
    expect(line, findsOneWidget, reason: '前置条件：第 53 句在视口内');
    await tester.tap(line, warnIfMissed: false);
    await tester.pump();
    await settle(tester, container, 106.0);

    final position = container.read(playbackProvider).position;
    expect(
      (position - 106.0).abs(),
      lessThan(0.5),
      reason: '点句应跳播到该句起点（第 53 句 = 106s），实际 $position',
    );
    expect(onLyricsPage(), isTrue, reason: '跳播不应翻回唱片层');
  });

  testWidgets('跳播后被点句立即居中', (tester) async {
    final container = await pumpPlayer(tester, 100.5);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container, 100.5);

    await tester.tap(find.text('第 53 句'), warnIfMissed: false);
    await tester.pump();
    await settle(tester, container, 106.0);

    final list = find.byType(ListView);
    final line = find.text('第 53 句');
    expect(line, findsOneWidget);
    final deviation =
        (tester.getCenter(line).dy - tester.getRect(list).center.dy).abs();
    expect(
      deviation,
      lessThan(16),
      reason: '被点句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
    );
  });
}
