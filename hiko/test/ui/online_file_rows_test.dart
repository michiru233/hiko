import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/ui/widgets/online_detail_panel.dart';

/// 1.99.18 在线详情树对齐 asmr.one 的文件全貌：
/// - 图片 / 文本 / 视频行不再被过滤，图片行带缩略图与体积
/// - 纯图片目录不再整支隐藏（fileCount 口径）
/// - 图片行点击开应用内预览；文本行点击拉取内容（测试环境 HTTP 全 400 → 报错提示）
void main() {
  final nodes = <Map<String, dynamic>>[
    {'type': 'audio', 'title': '音声A.mp3', 'hash': '1/1', 'duration': 10},
    {
      'type': 'image',
      'title': 'イメージ1.jpg',
      'hash': '1/2',
      'size': 250000,
    },
    {'type': 'text', 'title': '説明書.txt', 'hash': '1/3', 'size': 1200},
    {
      'type': 'folder',
      'title': 'イラスト',
      'children': [
        {'type': 'image', 'title': 'イメージ2.jpg', 'hash': '1/4', 'size': 300},
      ],
    },
  ];

  OnlineDetail buildDetail() => OnlineDetail(
        work: OnlineWork.fromJson({'id': 1, 'title': '作品'}),
        tracks: KikoeruClient.parseTrackTree(nodes),
        tree: KikoeruClient.parseTrackNodes(
          nodes,
          KikoeruClient.parseTrackTree(nodes),
        ),
      );

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1800);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  test('模型：isImage/isVideo 判别与目录 fileCount 聚合', () {
    final tree = KikoeruClient.parseTrackNodes(
      nodes,
      KikoeruClient.parseTrackTree(nodes),
    );
    final image = tree
        .whereType<OnlineFileNode>()
        .map((n) => n.track)
        .firstWhere((t) => t.hash == '1/2');
    expect(image.isImage, isTrue);
    expect(image.playable, isFalse);

    final folder = tree.whereType<OnlineFolderNode>().first;
    expect(folder.audioCount, 0, reason: '无音频，播放队列口径不变');
    expect(folder.fileCount, 1, reason: '纯图片目录按文件数计入，不再整支隐藏');
  });

  testWidgets('非音频行直接显示：图片行带体积，纯图片目录可见且计数', (tester) async {
    await pumpPanel(tester);

    expect(find.text('イメージ1'), findsOneWidget);
    expect(find.text('244 KB'), findsOneWidget);
    expect(find.text('説明書'), findsOneWidget);
    expect(find.text('イラスト'), findsOneWidget, reason: '纯图片目录不再隐藏');
    expect(find.text('1 个项目'), findsOneWidget, reason: '目录计数=全部文件数');
    // 折叠状态下子文件不出现
    expect(find.text('イメージ2'), findsNothing);
  });

  testWidgets('图片行点击 → 应用内全屏预览', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('イメージ1'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('文本行点击 → 内容拉取失败时给提示（测试环境 HTTP 全 400）',
      (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('説明書'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('无法加载文件内容'), findsOneWidget);
  });
}
