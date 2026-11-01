import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/online_work_grid.dart';

/// 在线分页条回归锁。
///
/// 演进：1.98.x 移动端与桌面共用一整条（首页/末页 + 页码 + 省略号 + 共 N 页 +
/// 跳页），窄屏塞不下；1.99.0 改成「上一页/下一页钉两端 + 当前页 ±1」；
/// **1.99.65 再收一档**（用户裁决 m03166）——页码格子与常驻输入框都撤掉，
/// 只留 `‹  当前页 / 总页数  ›` + 「跳转」对话框，一行 52dp。
///
/// 溢出在 widget test 里会以 FlutterError 抛出，「不抛异常」本身就是断言。
void main() {
  group('OnlinePager（移动端极简形态）', () {
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

    testWidgets('360px 窄屏：只留页码文本与箭头，不溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final log = await pumpPager(tester, page: 2, total: 3123);
      expect(tester.takeException(), isNull, reason: '窄屏分页条不允许溢出');

      // 页码格子、首末页图标、常驻输入框都不再出现
      expect(find.byTooltip('首页'), findsNothing);
      expect(find.byTooltip('末页'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('3'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      // 取而代之的是「当前页 / 总页数」与跳转入口
      expect(find.text('2 / 3123'), findsOneWidget);
      expect(find.text('跳转'), findsOneWidget);

      await tester.tap(find.byTooltip('下一页'));
      expect(log, [3]);
      await tester.tap(find.byTooltip('上一页'));
      expect(log, [3, 1]);
    });

    testWidgets('第 1 页：上一页禁用', (tester) async {
      await pumpPager(tester, page: 1, total: 100);
      expect(tester.takeException(), isNull);
      expect(find.text('1 / 100'), findsOneWidget);
      final btn = tester.widget<M3EIconButton>(
        find.ancestor(
          of: find.byTooltip('上一页'),
          matching: find.byType(M3EIconButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('末页：下一页禁用', (tester) async {
      await pumpPager(tester, page: 100, total: 100);
      expect(tester.takeException(), isNull);
      expect(find.text('100 / 100'), findsOneWidget);
      final btn = tester.widget<M3EIconButton>(
        find.ancestor(
          of: find.byTooltip('下一页'),
          matching: find.byType(M3EIconButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('跳转对话框：输入越界夹到末页', (tester) async {
      final log = await pumpPager(tester, page: 2, total: 3123);

      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      expect(find.text('跳转到第几页'), findsOneWidget);
      expect(find.text('共 3123 页，当前第 2 页'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('前往'));
      await tester.pumpAndSettle();

      expect(log, [3123]);
      expect(find.text('跳转到第几页'), findsNothing);
    });

    testWidgets('跳转对话框：0 夹到第 1 页；取消不发请求', (tester) async {
      final log = await pumpPager(tester, page: 50, total: 100);

      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('前往'));
      await tester.pumpAndSettle();
      expect(log, [1]);

      await tester.tap(find.text('跳转'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '7');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(log, [1], reason: '取消不该翻页');
    });
  });

  group('OnlinePager（桌面端不回归）', () {
    testWidgets('维持完整形态：每页条数 + 首末页图标 + 省略号 + 内联跳页', (tester) async {
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
      expect(find.text('每页 20 条'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('跳转'), findsNothing);
    });
  });
}
