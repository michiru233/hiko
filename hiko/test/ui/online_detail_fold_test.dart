import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/widgets/online_detail_panel.dart';

/// 1.92.0 在线详情页的目录折叠回归锁：
/// - 裁决 Q9（改判）：默认**全部折叠**，展开交给用户
/// - 裁决 Q1=A：点某个目录只展开它自己，其余不受影响
/// - 裁决 Q2：正在播放的那一行自动展开所在目录链，并滚到可见
///
/// 这两条互为前提 —— 全折叠之后若不自动展开，切歌切进别的目录时当前行会
/// 彻底隐形，用户根本不知道播的是哪一首。
void main() {
  // 两个顶层目录：第一个 1 首、第二个 2 首，用来区分「只展开它自己」
  List<OnlineNode> treeFrom(List<Map<String, dynamic>> nodes) =>
      KikoeruClient.parseTrackNodes(nodes, KikoeruClient.parseTrackTree(nodes));

  final nodes = <Map<String, dynamic>>[
    {
      'type': 'folder',
      'title': '01：mp3',
      'children': [
        {'type': 'audio', 'title': 'アルファ.mp3', 'hash': '1/1', 'duration': 10},
      ],
    },
    {
      'type': 'folder',
      'title': '02：wav',
      'children': [
        {'type': 'audio', 'title': 'ベータ.mp3', 'hash': '1/2', 'duration': 20},
        {'type': 'audio', 'title': 'ガンマ.mp3', 'hash': '1/3', 'duration': 30},
      ],
    },
  ];

  OnlineDetail buildDetail() {
    final tracks = KikoeruClient.parseTrackTree(nodes);
    return OnlineDetail(
      work: OnlineWork.fromJson({
        'id': 1,
        'title': '作品',
        'source_id': 'RJ01657200',
      }),
      tracks: tracks,
      tree: treeFrom(nodes),
    );
  }

  /// 2026-09-25 实测：`CoverCache.instance` 的磁盘层未初始化时降级为纯内存，
  /// 测试环境下 HttpClient 被替换成一律 400，封面走占位图，不会抛异常。
  Future<void> pumpPanel(
    WidgetTester tester, {
    Size surface = const Size(720, 1800),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineClientProvider.overrideWith(
            (ref) => KikoeruClient(baseUrl: 'https://api.asmr.one'),
          ),
          onlineDetailProvider(1).overrideWith((ref) async => buildDetail()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OnlineDetailBody(workId: 1)),
        ),
      ),
    );
    // FutureProvider 解析那一帧
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 把当前正在播放的曲目设成在线作品的某一条（用真实控制器直接置 state）
  void seedPlaying(WidgetTester tester, String hash) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnlineDetailBody)),
    );
    final track = Track(
      index: 0,
      name: 'playing',
      url: 'https://api.asmr.one/api/media/stream/$hash',
    );
    final album = Album(
      id: 'online-1',
      sourcePath: OnlineWork.sourcePathFor(1),
      title: '作品',
      date: DateTime(2026),
      tracks: [track],
    );
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: album,
      queue: [track],
      queueIndex: 0,
      playing: true,
      position: 5,
      duration: 20,
    );
  }

  double maxScrollOffset(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((s) => s.position.pixels)
      .fold<double>(0, (a, b) => a > b ? a : b);

  testWidgets('默认全部折叠：目录行在、底下的音轨一行都不在', (tester) async {
    await pumpPanel(tester);

    // 目录行本身必须可见，否则用户连展开的入口都找不到
    expect(find.text('01：mp3'), findsOneWidget);
    expect(find.text('02：wav'), findsOneWidget);

    // 三条音轨全部藏在折叠的目录里
    expect(find.text('アルファ'), findsNothing);
    expect(find.text('ベータ'), findsNothing);
    expect(find.text('ガンマ'), findsNothing);

    // 全折叠状态下按钮应当是「展开全部」
    expect(find.text('展开全部'), findsOneWidget);
    expect(find.text('折叠全部'), findsNothing);
  });

  testWidgets('点目录行只展开它自己，兄弟目录不受影响', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('01：mp3'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('アルファ'), findsOneWidget);
    // 02：wav 里的两条依然折叠着 —— 裁决 Q1=A 的「只展开一个」语义
    expect(find.text('ベータ'), findsNothing);
    expect(find.text('ガンマ'), findsNothing);

    // 再点一次折回去
    await tester.tap(find.text('01：mp3'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('アルファ'), findsNothing);
  });

  testWidgets('「展开全部」↔「折叠全部」按钮来回切', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('展开全部'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('アルファ'), findsOneWidget);
    expect(find.text('ベータ'), findsOneWidget);
    expect(find.text('ガンマ'), findsOneWidget);
    expect(find.text('折叠全部'), findsOneWidget);

    await tester.tap(find.text('折叠全部'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('アルファ'), findsNothing);
    expect(find.text('ベータ'), findsNothing);
    expect(find.text('展开全部'), findsOneWidget);
  });

  testWidgets('正在播放的曲目自动展开所在目录，并把该行滚进视野', (tester) async {
    // 视口刻意压矮：内容明显溢出，才能验证「滚到可见」这一步真的跑了
    await pumpPanel(tester, surface: const Size(720, 700));
    expect(maxScrollOffset(tester), 0);

    seedPlaying(tester, '1/2'); // 属于 02：wav
    await tester.pump(); // 播放状态生效 → build 里排下 postFrame
    await tester.pump(); // postFrame 里的 setState 生效 → 目录展开
    // 展开那帧的 postFrame 才发起 ensureVisible 动画；而 AnimationController 的
    // ticker 首帧只是打点（elapsed=0），要再走一帧才真正位移，所以这里两帧起步。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ベータ'), findsOneWidget);
    expect(find.text('ガンマ'), findsOneWidget);
    // 只开「正在播放所在的那条链」，其余目录保持折叠
    expect(find.text('アルファ'), findsNothing);
    expect(maxScrollOffset(tester), greaterThan(0));
  });

  testWidgets('用户手动折回正在播放的目录后，不会下一帧被强行再打开', (tester) async {
    await pumpPanel(tester);
    seedPlaying(tester, '1/2');
    await tester.pump();
    await tester.pump();
    expect(find.text('ベータ'), findsOneWidget);

    // 手动折回去：`_revealedHash` 记住这首已经处理过，不该再触发自动展开
    await tester.tap(find.text('02：wav'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('ベータ'), findsNothing);

    // 再走几帧，确认没有被强行拉开
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ベータ'), findsNothing);
  });
}
