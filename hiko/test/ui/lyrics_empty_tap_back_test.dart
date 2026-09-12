import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.74.0 回归：无歌词时歌词层显示「暂无歌词」，点中央任意处回唱片层。
///
/// 缺陷背景：「暂无歌词」是 `_buildLyricsView` 的提前 return，没包任何手势，
/// 而「点留白回唱片」的外层手势只包歌词 ListView——无歌词时中央区域点击完全
/// 落空，只能靠 AppBar 按钮切回。
void main() {
  Future<ProviderContainer> pumpPlayer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Album album = lyricsAlbum(lines: 0); // 无歌词
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(playbackProvider.notifier).state = playingAt(album, 0.5);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FullscreenPlayerScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  /// 把 crossfade / 定位动画推完。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool onLyricsPage() => find.byTooltip('显示封面').evaluate().isNotEmpty;
  bool onVinylPage() => find.byTooltip('显示歌词').evaluate().isNotEmpty;

  testWidgets('无歌词进入歌词页显示提示，点「暂无歌词」文字回唱片层', (tester) async {
    final container = await pumpPlayer(tester);
    expect(onVinylPage(), isTrue, reason: '初始应停在唱片层');

    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester);
    expect(onLyricsPage(), isTrue);
    expect(find.text('暂无歌词'), findsOneWidget);
    expect(find.text('点击返回唱片'), findsOneWidget);

    await tester.tap(find.text('暂无歌词'));
    await tester.pump();
    await settle(tester);
    expect(onVinylPage(), isTrue);
  });

  testWidgets('无歌词时点中央区非文字处也回唱片层（手势铺满）', (tester) async {
    final container = await pumpPlayer(tester);
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    await settle(tester);
    expect(onLyricsPage(), isTrue);

    final area = tester.getRect(find.byType(AnimatedSwitcher));
    // 距顶 40px 处：中央区内、不在「暂无歌词」文字上，只有铺满的手势收得到
    await tester.tapAt(Offset(area.center.dx, area.top + 40));
    await tester.pump();
    await settle(tester);
    expect(onVinylPage(), isTrue);
  });
}
