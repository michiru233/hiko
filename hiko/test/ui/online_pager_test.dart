import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/ui/widgets/online_work_grid.dart';

/// 在线分页条的移动端回归锁（1.99.0）。
///
/// 1.98.x 及之前移动端与桌面共用一整条（首页/末页 + 页码 + 省略号 +
/// 共 N 页 + 跳页），窄屏塞不下，「下一页」被挤出可视区 ——
/// 用户翻到下一页得先把分页条往右滑。修复后移动端：上一页/下一页
/// 钉在两端不参与横滑，页码只留当前页 ±1。
///
/// 溢出在 widget test 里会以 FlutterError 抛出，「不抛异常」本身就是断言。
void main() {
  group('mobilePageItems', () {
    test('中间页：±1 三颗', () {
      expect(mobilePageItems(2, 3123), [1, 2, 3]);
    });

    test('第 1 页：不出现 0', () {
      expect(mobilePageItems(1, 3123), [1, 2]);
    });

    test('末页：不出现 N+1', () {
      expect(mobilePageItems(3123, 3123), [3122, 3123]);
    });

    test('两页库：去重后 [1, 2]', () {
      expect(mobilePageItems(1, 2), [1, 2]);
    });

    test('单页库：[1]', () {
      expect(mobilePageItems(1, 1), [1]);
    });
  });

  group('OnlinePager（移动端布局不变量）', () {
    Future<List<int>> pumpPager(
      WidgetTester tester, {
      required int page,
      required int total,
    }) async {
      final log = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnlinePager(
              page: page,
              pageSize: 20,
              totalCount: total * 20,
              isMobile: true,
              onPage: log.add,
              onPageSize: (_) {},
            ),
          ),
        ),
      );
      return log;
    }

    testWidgets('360px 窄屏：不溢出，下一页在屏内可点', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final log = await pumpPager(tester, page: 2, total: 3123);
      expect(tester.takeException(), isNull, reason: '窄屏分页条不允许溢出');

      // 移动端不放首末页图标，页码只有 ±1
      expect(find.byTooltip('首页'), findsNothing);
      expect(find.byTooltip('末页'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byTooltip('下一页'));
      expect(log, [3]);
    });

    testWidgets('第 1 页：上一页禁用', (tester) async {
      await pumpPager(tester, page: 1, total: 100);
      expect(tester.takeException(), isNull);
      final btn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('上一页'),
          matching: find.byType(IconButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('末页：下一页禁用，页码夹到 N', (tester) async {
      await pumpPager(tester, page: 100, total: 100);
      expect(tester.takeException(), isNull);
      expect(find.text('99'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      final btn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('下一页'),
          matching: find.byType(IconButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });
  });

  group('OnlinePager（桌面端不回归）', () {
    testWidgets('维持完整形态：首末页图标 + 省略号', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnlinePager(
              page: 2,
              pageSize: 20,
              totalCount: 62453,
              isMobile: false,
              onPage: (_) {},
              onPageSize: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('首页'), findsOneWidget);
      expect(find.byTooltip('末页'), findsOneWidget);
      expect(find.text('…'), findsWidgets);
    });
  });
}
