import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/detail_jump_requests.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

/// 1.99.17 播放页「跳详情 / 收藏」回归锁。
///
/// 跳详情按钮在线/本地通用：在线把 workId 写进指令通道（桌面路径），
/// 本地把 album.id 写进本地通道；收藏按钮只在线专辑出现。
/// 测试跑在 macOS 宿主（Platform.isAndroid == false）→ 恒走桌面指令通道。
void main() {
  Album album({required String id, required String sourcePath}) => Album(
        id: id,
        sourcePath: sourcePath,
        title: '测试专辑',
        date: DateTime(2026),
        tracks: [
          Track(
            index: 0,
            name: 'track01',
            url: 'file:///tmp/track01.mp3',
            duration: 300,
          ),
        ],
      );

  Future<ProviderContainer> pumpPlayer(WidgetTester tester, Album a) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: a,
      queue: [a.tracks.first],
      queueIndex: 0,
      playing: true,
      position: 1,
      duration: 300,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FullscreenPlayerScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('在线专辑：出现收藏与「作品详情」，点详情把 workId 写进指令通道',
      (tester) async {
    final container = await pumpPlayer(
      tester,
      album(id: 'online-4567', sourcePath: 'online://4567'),
    );
    expect(find.byTooltip('收藏'), findsOneWidget);
    await tester.tap(find.byTooltip('作品详情'));
    await tester.pump();
    expect(container.read(onlineDetailRequestProvider), 4567);
  });

  testWidgets('本地专辑：无收藏按钮，点「专辑详情」写本地通道', (tester) async {
    final container = await pumpPlayer(
      tester,
      album(id: 'local-abc', sourcePath: '/tmp/local-abc'),
    );
    expect(find.byTooltip('收藏'), findsNothing);
    await tester.tap(find.byTooltip('专辑详情'));
    await tester.pump();
    expect(container.read(localDetailRequestProvider), 'local-abc');
  });

  test('workId 反解：roundtrip 与非法形态', () {
    expect(OnlineWork.workIdFromAlbumId(OnlineWork.albumIdFor(42)), 42);
    expect(OnlineWork.workIdFromAlbumId('local-abc'), isNull);
    expect(OnlineWork.workIdFromAlbumId('online-'), isNull);
  });
}
