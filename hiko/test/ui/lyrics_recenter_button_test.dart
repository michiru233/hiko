import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/lyrics/lyrics_controller.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.72.0 回归：全屏播放页歌词层的「回到当前句」按钮。
///
/// 显示条件是「自动跟随已被关闭」（`autoScrollEnabled == false`）——沿用详情页歌词
/// tab 那个按钮的既有语义，而不是每帧量几何判断当前句是否在正中（那会引入重绘抖动，
/// 且已实测自动跟随标志本身可信、不会被程序化滚动误关）。
/// 按下去必须真的归位：修复前它和自动滚动共用同一段静默放弃的逻辑，按了也没反应。
void main() {
  testWidgets('未滑走时不显示按钮，滑走后显示且点按能归位', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Album album = lyricsAlbum();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(playbackProvider.notifier).state = playingAt(album, 120);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FullscreenPlayerScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      container.read(playbackProvider.notifier).state = playingAt(album, 120);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));

    const recenterTooltip = '回到当前句';
    expect(
      find.byTooltip(recenterTooltip),
      findsNothing,
      reason: '自动跟随正常时歌词已经居中，不该有归位按钮',
    );

    // 手动滑走歌词
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pump();
    expect(
      find.byTooltip(recenterTooltip),
      findsOneWidget,
      reason: '手动滑走歌词后应出现「回到当前句」按钮',
    );

    await tester.tap(find.byTooltip(recenterTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final lyricsList = find.byType(ListView);
    final index = container.read(lyricsProvider).activeIndex;
    final activeLine = find.text('第 $index 句');
    expect(activeLine, findsOneWidget, reason: '点按后第 $index 句应被滚回视口');

    final deviation =
        (tester.getCenter(activeLine).dy - tester.getRect(lyricsList).center.dy).abs();
    expect(
      deviation,
      lessThan(16),
      reason: '点按后第 $index 句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
    );
    expect(
      find.byTooltip(recenterTooltip),
      findsNothing,
      reason: '已恢复自动跟随，按钮应收起',
    );
  });
}
