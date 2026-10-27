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

/// 1.99.51 在线详情文件浏览的回归锁。
///
/// 这一版把「整棵树 + 展开集合」换成了**逐层进入**：
///
/// - 一次只渲染当前层，目录行点击 = 进入；
/// - 顶部路径条可点回跳，非根层左侧有「上一级」；
/// - 正在播放的曲目不在当前层时，路径条右侧出现胶囊，点它才跳过去；
/// - 「展开全部 / 折叠全部」连同 `_expanded` 一起下线。
///
/// 旧的三条锁（Q9 默认全折叠 / Q1 只展开一个 / Q2 自动展开链）随模型一起
/// 作废 —— 这里按新语义重写，不保留「为了旧实现而成立」的断言。
void main() {
  List<OnlineNode> treeFrom(List<Map<String, dynamic>> nodes) =>
      KikoeruClient.parseTrackNodes(nodes, KikoeruClient.parseTrackTree(nodes));

  // 两个顶层目录：第一个 1 首、第二个 2 首，用来验证「进入只影响自己」
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

  OnlineDetail detailFrom(List<Map<String, dynamic>> source) => OnlineDetail(
    work: OnlineWork.fromJson(<String, dynamic>{
      'id': 1,
      'title': '作品',
      'source_id': 'RJ01657200',
    }),
    tracks: KikoeruClient.parseTrackTree(source),
    tree: treeFrom(source),
  );

  /// 2026-09-25 实测：`CoverCache.instance` 的磁盘层未初始化时降级为纯内存，
  /// 测试环境下 HttpClient 被替换成一律 400，封面走占位图，不会抛异常。
  Future<void> pumpPanel(
    WidgetTester tester, {
    Size surface = const Size(720, 1800),
    List<Map<String, dynamic>>? source,
    bool interceptBack = false,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final detail = detailFrom(source ?? nodes);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineClientProvider.overrideWith(
            (ref) => KikoeruClient(baseUrl: 'https://api.asmr.one'),
          ),
          onlineDetailProvider(1).overrideWith((ref) async => detail),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OnlineDetailBody(workId: 1, interceptBack: interceptBack),
          ),
        ),
      ),
    );
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

  testWidgets('根层只渲染第一层：子文件不可见，路径停在「全部文件」', (tester) async {
    await pumpPanel(tester);

    expect(find.text('01：mp3'), findsOneWidget);
    expect(find.text('02：wav'), findsOneWidget);
    expect(find.text('全部文件'), findsOneWidget);

    // 子层文件一条都不该出现 —— 逐层进入的核心约束
    expect(find.text('アルファ'), findsNothing);
    expect(find.text('ベータ'), findsNothing);
    expect(find.text('ガンマ'), findsNothing);

    // 根层没有「上一级」
    expect(find.byTooltip('上一级'), findsNothing);

    // 展开/折叠按钮已随模型下线
    expect(find.text('展开全部'), findsNothing);
    expect(find.text('折叠全部'), findsNothing);
  });

  testWidgets('点目录进入该层：只有它的子项可见，路径条跟着走', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('01：mp3'));
    await tester.pumpAndSettle();

    expect(find.text('アルファ'), findsOneWidget);
    // 兄弟目录与它的内容都不可见
    expect(find.text('02：wav'), findsNothing);
    expect(find.text('ベータ'), findsNothing);

    // 路径条：全部文件 › 01：mp3
    expect(find.text('全部文件'), findsOneWidget);
    expect(find.text('01：mp3'), findsOneWidget, reason: '目录行已不在，这一处应是路径段');
    expect(find.byTooltip('上一级'), findsOneWidget);
  });

  testWidgets('点路径里的「全部文件」直接回根层', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('01：mp3'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部文件'));
    await tester.pumpAndSettle();

    expect(find.text('01：mp3'), findsOneWidget);
    expect(find.text('02：wav'), findsOneWidget);
    expect(find.text('アルファ'), findsNothing);
    expect(find.byTooltip('上一级'), findsNothing);
  });

  testWidgets('「上一级」回到上一层；两层时一路退到根', (tester) async {
    final deep = <Map<String, dynamic>>[
      {
        'type': 'folder',
        'title': 'L1',
        'children': [
          {
            'type': 'folder',
            'title': 'L2',
            'children': [
              {
                'type': 'audio',
                'title': 'deep.mp3',
                'hash': '1/9',
                'duration': 5,
              },
            ],
          },
        ],
      },
    ];
    await pumpPanel(tester, source: deep);

    await tester.tap(find.text('L1'));
    await tester.pumpAndSettle();
    expect(find.text('L2'), findsOneWidget);
    expect(find.text('deep'), findsNothing);

    await tester.tap(find.byTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(find.text('L1'), findsOneWidget);
    expect(find.text('L2'), findsNothing);
    expect(find.byTooltip('上一级'), findsNothing);
  });

  testWidgets('系统返回键在非根层先退一层，不退详情页', (tester) async {
    await pumpPanel(tester, interceptBack: true);

    await tester.tap(find.text('02：wav'));
    await tester.pumpAndSettle();
    expect(find.text('ベータ'), findsOneWidget);

    final context = tester.element(find.byType(OnlineDetailBody));
    // `maybePop` 在「被 PopScope 拦下」时也返回 true（表示已处理），
    // 所以这里只断言 UI 结果：退了一层，而没有把详情页关掉
    await Navigator.of(context).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('02：wav'), findsOneWidget);
    expect(find.text('ベータ'), findsNothing);
  });

  testWidgets('正在播放不在当前层 → 顶部胶囊；点它跳到父目录并定位', (tester) async {
    await pumpPanel(tester, surface: const Size(720, 1800));

    seedPlaying(tester, '1/2'); // 属于 02：wav
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('正在播放 · ベータ'), findsOneWidget);

    await tester.tap(find.textContaining('正在播放 · ベータ'));
    await tester.pumpAndSettle();

    expect(find.text('ベータ'), findsOneWidget);
    expect(find.text('ガンマ'), findsOneWidget);
    expect(find.text('アルファ'), findsNothing);
    // 已经在目标层，胶囊功成身退
    expect(find.textContaining('正在播放 · '), findsNothing);
  });

  testWidgets('360dp 窄屏：混排层不溢出（含播放键 + 进入箭头 + 胶囊）', (tester) async {
    final mixed = <Map<String, dynamic>>[
      {
        'type': 'folder',
        'title': '1.音声ファイル（本編とおまけ）',
        'children': [
          {'type': 'audio', 'title': 'a.mp3', 'hash': 'n/1', 'duration': 5},
        ],
      },
      {'type': 'audio', 'title': '01 プロローグ.mp3', 'hash': 'n/2', 'duration': 60},
      {'type': 'image', 'title': '表紙.jpg', 'hash': 'n/3', 'size': 250000},
      {'type': 'text', 'title': 'トラックリスト.txt', 'hash': 'n/4', 'size': 2048},
    ];
    await pumpPanel(tester, surface: const Size(360, 800), source: mixed);
    seedPlaying(tester, 'n/1'); // 歌在子目录里 → 胶囊出现
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('正在播放 · '), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '360dp 下混排层出现溢出/布局异常');
  });

  testWidgets('同层排序：目录 → 音频 → 图片 → 文本', (tester) async {
    final mixed = <Map<String, dynamic>>[
      {'type': 'text', 'title': 'readme.txt', 'hash': 'm/1', 'size': 100},
      {'type': 'image', 'title': 'cover.jpg', 'hash': 'm/2', 'size': 200},
      {'type': 'audio', 'title': '01 song.mp3', 'hash': 'm/3', 'duration': 10},
      {
        'type': 'folder',
        'title': 'Disc',
        'children': [
          {'type': 'audio', 'title': 'a.mp3', 'hash': 'm/4', 'duration': 5},
        ],
      },
    ];
    await pumpPanel(tester, source: mixed);

    double topOf(String text) => tester.getTopLeft(find.text(text)).dy;

    expect(topOf('Disc'), lessThan(topOf('01 song')));
    expect(topOf('01 song'), lessThan(topOf('cover')));
    expect(topOf('cover'), lessThan(topOf('readme')));
  });
}
