import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

/// 1.71.0 回归：全屏播放页歌词自动滚动必须把当前句落在**歌词区**的垂直中心。
///
/// 旧实现按「索引 × 估算行高 − 屏幕高度/2」硬算，用的是整个屏幕高度而非歌词
/// ListView 自身的 viewport 高度（歌词区被曲目信息/进度条/控制栏挤压后只剩屏幕
/// 一半多），于是每行少滚约半个屏幕，高亮句落在可视区下方，用户得再手动滑两三句
/// 才看得到。本测试直接量几何：当前句中心与歌词区中心的偏差必须很小。
///
/// 旧公式在该场景下偏差约 (屏幕高 − 歌词区高)/2 ≒ 4 行，远超下面 16px 的容差。

/// 60 行歌词、每行 2 秒 → position=40s 时高亮第 20 句（远离首屏，必须真实滚动）。
String _buildLyrics({int lines = 60}) {
  final buffer = StringBuffer('WEBVTT\n\n');
  for (var i = 0; i < lines; i++) {
    final start = i * 2;
    String ts(int s) =>
        '00:${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.000';
    buffer.writeln('${ts(start)} --> ${ts(start + 2)}');
    buffer.writeln('第 $i 句');
    buffer.writeln();
  }
  return buffer.toString();
}

Album _album() => Album(
      id: 'rj-test',
      sourcePath: '/tmp/rj-test',
      title: '测试专辑',
      date: DateTime(2026),
      tracks: [
        Track(
          index: 0,
          name: 'track01',
          url: 'file:///tmp/track01.mp3',
          duration: 200,
          lyricsText: _buildLyrics(),
        ),
      ],
    );

void main() {
  Future<double> measureDeviation(WidgetTester tester, double fontScale) async {
    // 手机竖屏（对齐安卓实机比例）：歌词区被上下控件挤压到明显小于屏幕
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final album = _album();
    final track = album.tracks.first;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    PlaybackState playingAt(double seconds) => PlaybackState(
          album: album,
          queue: [track],
          queueIndex: 0,
          playing: true,
          position: seconds,
          duration: 200,
        );

    container.read(playbackProvider.notifier).state = playingAt(40);
    if (fontScale != 1.0) {
      // 直接置 state：走 notifier setter 会触发 SharedPreferences 异步落盘，测试环境挂起
      final settings = container.read(settingsProvider.notifier);
      settings.state = settings.state.copyWith(lyricsFontScale: fontScale);
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FullscreenPlayerScreen()),
    ));
    await tester.pump();

    // 切到歌词层（这才会实例化歌词 Provider 并挂上播放监听）
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();

    // 推一次播放状态触发解析（第 20 句 = 40s）
    container.read(playbackProvider.notifier).state = playingAt(40.5);
    await tester.pump();
    await tester.pump();
    // 首次滚动：先 jumpTo 粗定位，再 animateTo 精确居中
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final lyricsList = find.byType(ListView);
    final activeLine = find.text('第 20 句');
    expect(lyricsList, findsOneWidget, reason: '应已切到歌词层');
    expect(activeLine, findsOneWidget, reason: '第 20 句应已滚入视口并被构建');

    final viewportCenter = tester.getRect(lyricsList).center.dy;
    final lineCenter = tester.getCenter(activeLine).dy;
    return (lineCenter - viewportCenter).abs();
  }

  testWidgets('当前句落在歌词区垂直中心（默认字号）', (tester) async {
    final deviation = await measureDeviation(tester, 1.0);
    expect(
      deviation,
      lessThan(16),
      reason: '当前句中心偏离歌词区中心 ${deviation.toStringAsFixed(1)}px'
          '（旧公式用整屏高度硬算，此处偏差约 4 行）',
    );
  });

  testWidgets('当前句落在歌词区垂直中心（超大字号 1.5x）', (tester) async {
    final deviation = await measureDeviation(tester, 1.5);
    expect(
      deviation,
      lessThan(16),
      reason: '超大字号下偏离 ${deviation.toStringAsFixed(1)}px'
          '（写死的 45×scale 行高估算在这里最不准）',
    );
  });
}
