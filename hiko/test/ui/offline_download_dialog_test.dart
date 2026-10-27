import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/offline_download_dialog.dart';

/// 离线下载对话框（1.99.53 M3E 重排）的回归锁。
///
/// 这一版把它当**文件清单**来排：行标题保留原始文件名（含 `.mp3` 与 `TrackN`），
/// 分组靠目录组头，全选与组全选都是三态勾选，列表限高内部滚动。
void main() {
  final nodes = <Map<String, dynamic>>[
    {
      'type': 'folder',
      'title': '本編/MP3/SEなし',
      'children': [
        {
          'type': 'audio',
          'title': 'Track1 プロローグ SEなし.mp3',
          'hash': '1/1',
          'duration': 119,
          'size': 3774874,
        },
        {
          'type': 'audio',
          'title': 'Track2 美女将の逆夜這い♪ SEなし.mp3',
          'hash': '1/2',
          'duration': 1298,
          'size': 41523610,
        },
      ],
    },
    {
      'type': 'folder',
      'title': '本編/イラスト',
      'children': [
        {
          'type': 'audio',
          'title': 'Track3 おまけ SEなし.mp3',
          'hash': '1/3',
          'duration': 600,
          'size': 1048576,
        },
      ],
    },
  ];

  List<OnlineTrack> audioOf(List<Map<String, dynamic>> source) =>
      KikoeruClient.parseTrackTree(source).where((t) => t.playable).toList();

  final work = OnlineWork.fromJson(<String, dynamic>{
    'id': 1,
    'title': '【低音喘ぎ】孕み村のメスまんこ共にわからせ極太肉棒でオホ声',
    'source_id': 'RJ01657200',
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    Size surface = const Size(800, 700),
    List<Map<String, dynamic>>? source,
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
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OfflineDownloadDialog(
              work: work,
              audio: audioOf(source ?? nodes),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  M3EButton downloadButton(WidgetTester tester) =>
      tester.widget<M3EButton>(find.widgetWithText(M3EButton, '下载'));

  testWidgets('标题只写「离线下载」，作品名降为副行，行标题保留 .mp3', (tester) async {
    await pumpDialog(tester);

    expect(find.text('离线下载'), findsOneWidget);
    expect(find.textContaining('【低音喘ぎ】'), findsOneWidget);
    // 不清理：文件名连扩展名一起展示（用户裁决 1.99.53）
    expect(find.textContaining('.mp3'), findsNWidgets(3));
    expect(find.textContaining('Track1'), findsOneWidget);
  });

  testWidgets('未选时下载禁用；选一条后可用，全选变部分选中', (tester) async {
    await pumpDialog(tester);

    expect(downloadButton(tester).onPressed, isNull, reason: '一条没选不该能下载');
    expect(find.textContaining('已选 0 / 3 轨'), findsOneWidget);

    await tester.tap(find.textContaining('Track1'));
    await tester.pumpAndSettle();

    expect(downloadButton(tester).onPressed, isNotNull);
    expect(find.textContaining('已选 1 / 3 轨'), findsOneWidget);

    final selectAll = tester.widget<M3ECheckbox>(
      find.byType(M3ECheckbox).first,
    );
    expect(selectAll.value, isFalse);
    expect(selectAll.indeterminate, isTrue, reason: '部分选中要显示横杠');
  });

  testWidgets('点全选：全部勾上，三态回到选中', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已选 3 / 3 轨'), findsOneWidget);
    final selectAll = tester.widget<M3ECheckbox>(
      find.byType(M3ECheckbox).first,
    );
    expect(selectAll.value, isTrue);
    expect(selectAll.indeterminate, isFalse);

    // 再点一次 = 全不选
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 0 / 3 轨'), findsOneWidget);
  });

  testWidgets('点组头勾整组：只影响该目录', (tester) async {
    await pumpDialog(tester);

    // 组头显示目录末段，上级路径是小字
    await tester.tap(find.textContaining('SEなし').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('已选 2 / 3 轨'), findsOneWidget);
    expect(downloadButton(tester).onPressed, isNotNull);
  });

  testWidgets('360×640 小屏：列表限高、整体不溢出', (tester) async {
    await pumpDialog(tester, surface: const Size(360, 640));

    expect(tester.takeException(), isNull, reason: '窄屏下对话框不得溢出');
    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    expect(
      tester.getSize(list).height,
      lessThanOrEqualTo(320 + 1),
      reason: '列表高度应被 50% 屏高（此处 320）封顶',
    );
  });
}
