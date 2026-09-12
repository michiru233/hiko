import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.75.0 回归：歌词行间空隙可点回唱片层，文字本身仍不翻页。
///
/// 缺陷背景：1.73.0 的实现里每行歌词**整行**（含 vertical:8 间距）都有一层
/// 吸收点击的手势，密歌词时几乎不存在可点的空白，用户实测「点空白回唱片
/// 不流畅」。收窄为只吸收文字渲染框后，行间空隙必须落回外层翻页手势。
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

  /// 把 crossfade / 定位动画推完。歌词解析依赖播放状态更新事件，
  /// 每帧都要像真实播放那样刷新一次 playbackProvider（对齐旧 toggle 测试）。
  Future<void> settle(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    for (var i = 0; i < 6; i++) {
      container.read(playbackProvider.notifier).state = playingAt(
        container.read(playbackProvider).album!,
        0.5,
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool onLyricsPage() => find.byTooltip('显示封面').evaluate().isNotEmpty;
  bool onVinylPage() => find.byTooltip('显示歌词').evaluate().isNotEmpty;

  /// 相邻两行歌词文字框之间的空隙中点（行间 vertical 8+8=16px）。
  Offset gapBetween(Rect a, Rect b) =>
      Offset((a.center.dx + b.center.dx) / 2, (a.bottom + b.top) / 2);

  testWidgets('点两行歌词之间的空隙回唱片层', (tester) async {
    final container = await pumpPlayer(tester, 0.5);
    expect(onVinylPage(), isTrue);

    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container);
    expect(onLyricsPage(), isTrue);

    final first = tester.getRect(find.text('第 0 句'));
    final second = tester.getRect(find.text('第 1 句'));
    await tester.tapAt(gapBetween(first, second));
    await tester.pump();
    await settle(tester, container);

    expect(onVinylPage(), isTrue, reason: '行间空隙属于外层翻页手势');
  });

  testWidgets('点歌词文字仍不翻页（收窄没过头）', (tester) async {
    final container = await pumpPlayer(tester, 0.5);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester, container);
    expect(onLyricsPage(), isTrue);

    await tester.tap(find.text('第 0 句'), warnIfMissed: false);
    await tester.pump();
    await settle(tester, container);

    expect(onLyricsPage(), isTrue, reason: '文字渲染框仍被吸收，不应切回唱片层');
  });
}
