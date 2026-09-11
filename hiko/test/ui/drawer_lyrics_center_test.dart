import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/lyrics/drawer_lyrics_view.dart';

import 'lyrics_fixture.dart';

/// 1.72.0 回归：专辑详情页「歌词」tab 跨行远跳后当前句必须进视口并居中。
///
/// 该视图的 `_scrollToActiveLine` 曾在目标行未被 ListView 构建时静默 `return`
/// （`_lineKeys[index]` 只在 itemBuilder 里才建立，跨行远跳必然落这一支），
/// 既没有粗定位也没有重试：实测跳到第 83 句后列表 offset 停在 67、该行根本没被构建，
/// 偏差无穷大。全屏播放页在 1.71.1 引入的「粗跳 + 重试」没有同步过来。
/// 现在两个视图共用 `LyricsAutoScroll.revealLyricsLine`。
void main() {
  testWidgets('跳到第 83 句后当前句进视口且居中', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Album album = lyricsAlbum();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 详情页歌词 tab 的高度来自外层 SizedBox(380)
    container.read(playbackProvider.notifier).state = playingAt(album, 4);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(height: 380, child: DrawerLyricsView()),
          ),
        ),
      ),
    ));
    await tester.pump();

    // 先跟着播到第 5 句（开头这段用户反馈是好的）
    for (var i = 0; i < 4; i++) {
      container.read(playbackProvider.notifier).state = playingAt(album, 4.0 + i * 2.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    final lyricsList = find.byType(ListView);
    final offsetBefore = tester.widget<ListView>(lyricsList).controller!.offset;

    // 跨行远跳：166s -> 第 83 句
    container.read(playbackProvider.notifier).state = playingAt(album, 166.0);
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    final activeLine = find.text('第 83 句');
    expect(
      activeLine,
      findsOneWidget,
      reason: '第 83 句没被构建 —— 列表根本没滚动（修复前 offset 停在 '
          '${offsetBefore.toStringAsFixed(0)} 就是这个症状）',
    );

    final deviation =
        (tester.getCenter(activeLine).dy - tester.getRect(lyricsList).center.dy).abs();
    expect(
      deviation,
      lessThan(16),
      reason: '第 83 句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px',
    );
  });
}
