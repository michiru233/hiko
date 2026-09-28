import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/ui/widgets/online_detail_panel.dart';

/// 1.99.2 在线详情页「其他语言版本」胶囊（汉化版 / 原版跳转）回归锁。
///
/// 数据源是详情响应的 `other_language_editions_in_db`（asmr.one 库内实际
/// 存在的条目）；宿主给 `onOpenWork` 时胶囊可点并回传该版本的数字 id
/// （桌面原地换面板 / 移动端压栈由宿主决定），不给时只展示不可点。
void main() {
  OnlineDetail buildDetail({
    List<Map<String, dynamic>>? editions,
  }) {
    const nodes = [
      {'type': 'audio', 'title': 'トラック1.mp3', 'hash': '1/1', 'duration': 10},
    ];
    final tracks = KikoeruClient.parseTrackTree(nodes);
    return OnlineDetail(
      work: OnlineWork.fromJson({
        'id': 1617295,
        'title': '原版作品',
        'source_id': 'RJ01617295',
        'other_language_editions_in_db': ?editions,
      }),
      tracks: tracks,
      tree: KikoeruClient.parseTrackNodes(nodes, tracks),
    );
  }

  Future<List<int>> pumpBody(
    WidgetTester tester, {
    required OnlineDetail detail,
    ValueChanged<int>? onOpenWork,
  }) async {
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final opened = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineClientProvider.overrideWith(
            (ref) => KikoeruClient(baseUrl: 'https://api.asmr.one'),
          ),
          onlineDetailProvider(1617295).overrideWith((ref) async => detail),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OnlineDetailBody(
              workId: 1617295,
              onOpenWork: onOpenWork,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return opened;
  }

  testWidgets('有汉化版：胶囊可见，点按回传该版本的 id', (tester) async {
    final opened = <int>[];
    await pumpBody(
      tester,
      detail: buildDetail(editions: [
        {'id': 1623920, 'lang': '简体中文', 'source_id': 'RJ01623920'},
      ]),
      onOpenWork: opened.add,
    );
    expect(find.text('简体中文'), findsOneWidget);
    await tester.tap(find.text('简体中文'));
    expect(opened, [1623920]);
  });

  testWidgets('原版条目标注「（原版）」', (tester) async {
    // 汉化版视角：作品是汉化版（1623920），原版是另一部作品（1617295）
    const nodes = [
      {'type': 'audio', 'title': 'トラック1.mp3', 'hash': '1/1', 'duration': 10},
    ];
    final tracks = KikoeruClient.parseTrackTree(nodes);
    await pumpBody(
      tester,
      detail: OnlineDetail(
        work: OnlineWork.fromJson({
          'id': 1623920,
          'title': '汉化版作品',
          'source_id': 'RJ01623920',
          'other_language_editions_in_db': [
            {
              'id': 1617295,
              'lang': '日本語',
              'source_id': 'RJ01617295',
              'is_original': true,
            },
          ],
        }),
        tracks: tracks,
        tree: KikoeruClient.parseTrackNodes(nodes, tracks),
      ),
      onOpenWork: (_) {},
    );
    expect(find.text('日本語（原版）'), findsOneWidget);
  });

  testWidgets('没有其他语言版本：不出胶囊行', (tester) async {
    await pumpBody(tester, detail: buildDetail());
    expect(find.byIcon(Icons.translate_rounded), findsNothing);
  });

  testWidgets('宿主没给 onOpenWork：胶囊只展示，点按无副作用', (tester) async {
    await pumpBody(
      tester,
      detail: buildDetail(editions: [
        {'id': 1623920, 'lang': '简体中文'},
      ]),
    );
    expect(find.text('简体中文'), findsOneWidget);
    await tester.tap(find.text('简体中文'));
    await tester.pump(const Duration(milliseconds: 100));
    // 没有路由被压栈（详情 body 仍在本页，没有新的 Scaffold）
    expect(find.byType(OnlineDetailBody), findsOneWidget);
  });
}
