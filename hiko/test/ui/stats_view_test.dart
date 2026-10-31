import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/stats.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/stats_view.dart';

import 'm3e/m3e_test_harness.dart';

/// 统计页自适应（1.99.61）。
///
/// 改之前：横向 padding 写死 48、三张卡与三颗 chip 都是固定 `Row`
/// —— 360dp 手机上内容区只剩 264dp，「累计收听」的「12小时34分钟」
/// 在 titleMedium 下直接挤爆。这里锁住三件事：
/// 窄屏竖排 / 宽屏横排 / 长文本不溢出。
void main() {
  LibraryStats stats({double listenSeconds = 12 * 3600 + 34 * 60}) =>
      LibraryStats(
        albumCount: 77,
        totalListenSeconds: listenSeconds,
        finishedCount: 12,
        startedCount: 30,
        unplayedCount: 35,
        ratedCount: 21,
        recentlyPlayed: const <Album>[],
      );

  Future<void> pumpStats(
    WidgetTester tester,
    Size size, {
    LibraryStats? data,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: M3ETheme(
          data: testTheme(),
          child: Scaffold(
            body: StatsView(
              stats: data ?? stats(),
              onOpenAlbum: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('360dp：三张卡竖排、三颗 chip 都在、不溢出', (tester) async {
    await pumpStats(tester, const Size(360, 800));

    expect(tester.takeException(), isNull);
    expect(find.text('累计收听'), findsOneWidget);
    expect(find.text('专辑总数'), findsOneWidget);
    expect(find.text('已评分'), findsOneWidget);
    expect(find.text('听完 12'), findsOneWidget);
    expect(find.text('听过 30'), findsOneWidget);
    expect(find.text('未听 35'), findsOneWidget);

    // 竖排：后一张卡在上/下关系里，且水平起点相同
    final first = tester.getTopLeft(find.text('累计收听'));
    final second = tester.getTopLeft(find.text('专辑总数'));
    final third = tester.getTopLeft(find.text('已评分'));
    expect(second.dy, greaterThan(first.dy));
    expect(third.dy, greaterThan(second.dy));
    expect(second.dx, closeTo(first.dx, 0.5));
  });

  testWidgets('720dp：三张卡横排、同一行', (tester) async {
    await pumpStats(tester, const Size(720, 800));

    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.text('累计收听'));
    final second = tester.getTopLeft(find.text('专辑总数'));
    final third = tester.getTopLeft(find.text('已评分'));
    expect(second.dy, closeTo(first.dy, 0.5));
    expect(third.dy, closeTo(first.dy, 0.5));
    expect(second.dx, greaterThan(first.dx));
    expect(third.dx, greaterThan(second.dx));
  });

  testWidgets('360dp + 超长时长：不溢出（值单行省略）', (tester) async {
    await pumpStats(
      tester,
      const Size(360, 800),
      data: stats(listenSeconds: 999 * 3600 + 59 * 60),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('999小时59分钟'), findsOneWidget);
  });

  testWidgets('360dp 横向边距收窄到 16（内容从 x=16 起）', (tester) async {
    await pumpStats(tester, const Size(360, 800));

    final title = tester.getTopLeft(find.text('统计'));
    expect(title.dx, closeTo(16, 0.5));
  });
}
