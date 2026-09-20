import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/lyrics/drawer_lyrics_view.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

/// 1.89.0 回归：旧库里的乱码歌词必须显示成正常中文（LRC 与 VTT 同源）。
///
/// 症状（用户上报）：全屏播放页 LRC 显示 `å­¦é¿ï¼è¿éçåï¼`，VTT 同样乱码。
/// 根因：旧扫描器 `String.fromCharCodes(bytes)` 把 UTF-8 歌词字节逐字节当 Latin-1
/// 存进 library.json；`repairText` 原来只试 GBK/Shift-JIS/EUC-JP，缺「UTF-8 被按
/// Latin-1 读取」这一条，两类都还原不了，乱码经解析器一路透传到 UI。
///
/// 修复后不需要重扫库：解析入口对嵌入文本先 `repairText` 抢救一次，老库原样即可恢复。

/// 旧扫描器产物：UTF-8 字节被按 Latin-1 逐字节读取，原样躺在 library.json 里。
String legacyGarbled(String clean) => latin1.decode(utf8.encode(clean));

Album _album(String lyricsText) => Album(
      id: 'rj-test',
      sourcePath: '/tmp/rj-test',
      title: '测试专辑',
      date: DateTime(2026),
      tracks: [
        Track(
          index: 0,
          name: 'track01',
          url: 'file:///tmp/track01.mp3',
          duration: 60,
          lyricsText: lyricsText,
        ),
      ],
    );

void main() {
  testWidgets('详情页歌词 tab：乱码 LRC 渲染为正常中文', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 带 BOM 的 .lrc（真实样本 05 的开头形态）
    final album = _album(legacyGarbled(
        '\uFEFF[00:11.54]学长，还醒着吗？\r\n[00:14.98]啊！原来你醒着啊\r\n'));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(height: 380, child: DrawerLyricsView())),
        ),
      ),
    ));
    await tester.pump();

    // 歌词控制器由播放状态变更驱动，曲目须在挂载后推入
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: album,
      queue: [album.tracks.first],
      queueIndex: 0,
      playing: true,
      position: 12,
      duration: 60,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('学长，还醒着吗？'), findsOneWidget,
        reason: '乱码没被还原 —— 屏幕上会是 å­¦é¿ï¼è¿éçåï¼');
    expect(find.text('啊！原来你醒着啊'), findsOneWidget);
    // 乱码特征不得残留（BOM 变来的 ï»¿ 也算）
    expect(find.textContaining('ï»¿'), findsNothing);
    expect(find.textContaining('å'), findsNothing);
  });

  testWidgets('全屏播放页歌词层：乱码 VTT 渲染为正常中文', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // 无 BOM 的 .vtt（用户复现视频里那一类）
    final album = _album(legacyGarbled(
        'WEBVTT\n\n1\n00:00:05.750 --> 00:00:11.720\n我…我喜欢你，请…请和我交往吧\n'));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: album,
      queue: [album.tracks.first],
      queueIndex: 0,
      playing: true,
      position: 6,
      duration: 60,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FullscreenPlayerScreen()),
    ));
    await tester.pump();

    // 切到歌词层才会实例化歌词 Provider 并挂上播放监听
    await tester.tap(find.byTooltip('显示歌词'));
    await tester.pump();
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: album,
      queue: [album.tracks.first],
      queueIndex: 0,
      playing: true,
      position: 6.5,
      duration: 60,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('我…我喜欢你，请…请和我交往吧'), findsOneWidget,
        reason: '乱码没被还原 —— 屏幕上会是 æ\x88\x91â\x80¦æ\x88\x91å\x96\x9cæ¬¢ä½ ');
    expect(find.textContaining('â'), findsNothing);
  });
}
