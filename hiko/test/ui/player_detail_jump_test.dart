import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/detail_jump_requests.dart';
import 'package:hiko/ui/screens/album_detail_screen.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';
import 'package:hiko/ui/screens/home_screen.dart';
import 'package:hiko/ui/transitions/fullscreen_player_route.dart';
import 'package:hiko/ui/widgets/album_card.dart';
import 'package:hiko/ui/widgets/mobile_bottom_nav.dart';
import 'package:hiko/ui/widgets/online_detail_panel.dart';
import 'package:hiko/ui/screens/online_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // ────────────── 1.99.19：跳详情的**落栈**（裁决 Q2=A） ──────────────
  //
  // 实机反馈：从播放页点「!」跳到详情页之后，边缘手势退一次**退不到列表** ——
  // 栈里还压着旧详情页，用户描述成「退一次回详情页、再退一次才回列表」
  // （甚至把交叉淡入里那一瞬播放页也算作一层）。
  //
  // 修法 = 那一次 push 改成「列表以上不留历史」（`pushDetailAboveList`）。
  // 两个用例都**必须先让栈里存在【旧详情页 + 播放页】**，否则测不出旧 bug：
  // 栈里只有列表时，旧实现也能一次退回列表。
  //
  // 跑在 macOS 宿主上，所以用 `HomeScreen(debugMobileLayout: true)` 打开移动布局
  // （延续 `mobile_player_bar_flow_test` 的做法），画布给到 900 宽避免桌面播放栏溢出。

  testWidgets('移动端本地路径：跳详情后一次返回回到列表，而不是旧详情页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final album = Album(
      id: 'rj000001',
      sourcePath: '/x/rj000001',
      title: 'rj000001',
      date: DateTime(2026),
      tracks: [Track(index: 0, name: 'track01', url: 'file:///x/01.mp3')],
    );
    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary([album])),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen(debugMobileLayout: true)),
      ),
    );
    // initState 的静默扫描要先走完（空目录即返，无 IO）
    await tester.pump(const Duration(milliseconds: 600));

    // 列表 → 详情页（真实路径：点卡片）
    await tester.tap(find.byType(AlbumCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    // 详情页上点曲目会自动压播放页；这里直接压路由（点曲目会去碰真音频引擎）
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: album,
      queue: album.tracks,
      queueIndex: 0,
      playing: false,
      position: 1,
      duration: 100,
    );
    final nav = Navigator.of(tester.element(find.byType(AlbumDetailScreen)));
    nav.push(FullscreenPlayerRoute());
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPlayerScreen), findsOneWidget);

    // 点「!」跳详情
    await tester.tap(find.byTooltip('专辑详情'));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPlayerScreen), findsNothing, reason: '播放页要让位');
    expect(find.byType(AlbumDetailScreen), findsOneWidget, reason: '落在详情页');

    // 一次返回 → 必须是列表（用系统返回，贴近安卓边缘手势/返回键）
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailScreen), findsNothing,
        reason: '栈里不该还留着旧详情页（旧实现退一次还在详情页）');
    expect(find.byType(AlbumCard), findsWidgets, reason: '回到列表');
  });

  testWidgets('移动端在线路径：跳详情后一次返回回到列表，而不是旧详情页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(const [])),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
        // 详情页要拉网络（测试环境所有 HTTP 都是 400 → 未捕获异常会让用例失败），
        // 所以只把「详情数据」这一层换掉，路由/指令通道/落栈仍是真货
        onlineDetailProvider(4567).overrideWith(
          (ref) async => OnlineDetail(
            work: const OnlineWork(id: 4567, title: '在线作品'),
            tracks: const [],
            tree: const [],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen(debugMobileLayout: true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // 切到「在线」视图（OnlineScreen 在场 = 指令通道的消费方已注册）
    await tester.tap(
      find.descendant(
        of: find.byType(MobileBottomNav),
        matching: find.text('在线'),
      ),
    );
    await _pumpFrames(tester);
    expect(find.byType(OnlineScreen), findsOneWidget);

    // 旧详情页（用户上一层的页）+ 播放页压上来
    final onlineAlbum = Album(
      id: OnlineWork.albumIdFor(4567),
      sourcePath: 'online://4567',
      title: '在线作品',
      date: DateTime(2026),
      tracks: [
        Track(index: 0, name: 'track01', url: 'https://example.invalid/01.mp3'),
      ],
    );
    final nav = Navigator.of(tester.element(find.byType(OnlineScreen)));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const OnlineDetailScreen(workId: 4567),
      ),
    );
    await _pumpFrames(tester);
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: onlineAlbum,
      queue: onlineAlbum.tracks,
      queueIndex: 0,
      playing: false,
      position: 1,
      duration: 100,
    );
    nav.push(FullscreenPlayerRoute());
    await _pumpFrames(tester);

    await tester.tap(find.byTooltip('作品详情'));
    await _pumpFrames(tester);
    expect(find.byType(FullscreenPlayerScreen), findsNothing, reason: '播放页要让位');
    expect(find.byType(OnlineDetailScreen), findsOneWidget, reason: '落在详情页');

    await tester.binding.handlePopRoute();
    await _pumpFrames(tester);
    expect(find.byType(OnlineDetailScreen), findsNothing,
        reason: '栈里不该还留着旧详情页（旧实现退一次还在详情页）');
    expect(find.byType(OnlineScreen), findsOneWidget, reason: '回到在线列表');
  });
}

/// 有界 pump（不追求「全部动画停下」）。
///
/// 在线详情页在测试环境永远拉不到数据（flutter_test 里所有 HTTP 都返回 400），
/// 页面上那个加载圈是无限动画 —— 碰它会超时的是 `pumpAndSettle`。
/// 需要断言的只是路由栈，给足 ~1s 的有界帧数就够转场跑完。
Future<void> _pumpFrames(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

class _SeededLibrary extends LibraryNotifier {
  _SeededLibrary(List<Album> albums) : super(LibraryStore()) {
    state = albums;
  }
}
