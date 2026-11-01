import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/ui/m3e/m3e.dart';

/// M3E 导航抽屉的组件级回归锁（1.99.65）。
///
/// 抽屉只负责「外观 + 内容」：手势归 `Scaffold.drawerEnableOpenDragGesture`，
/// 所以这里不测拖拽，测的是「条目怎么画、点了回调什么下标、禁用项点不点得动、
/// 选中项是不是唯一」。
void main() {
  const destinations = <M3ENavigationDestination>[
    M3ENavigationDestination(
      label: '本地音声',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      badge: 51,
    ),
    M3ENavigationDestination(
      label: '在线',
      icon: Icons.cloud_outlined,
      selectedIcon: Icons.cloud_rounded,
    ),
    M3ENavigationDestination(
      label: '在线收藏',
      icon: Icons.favorite_outline,
      selectedIcon: Icons.favorite_rounded,
      badge: 120,
    ),
    M3ENavigationDestination(
      label: '正在播放',
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle,
      enabled: false,
    ),
  ];

  Future<List<int>> pumpDrawer(
    WidgetTester tester, {
    int selectedIndex = 1,
    String? hint,
  }) async {
    final log = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: M3ENavDrawer(
            destinations: destinations,
            selectedIndex: selectedIndex,
            hint: hint,
            onSelected: log.add,
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
    // 直接摆开抽屉（组件自身不负责打开）
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('四个条目都渲染，宽度 308，徽标按 count 显示', (tester) async {
    await pumpDrawer(tester);

    expect(find.text('本地音声'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('在线收藏'), findsOneWidget);
    expect(find.text('正在播放'), findsOneWidget);

    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    expect(drawer.width, M3ENavDrawer.width);

    // 51 / 120 → 超过 99 折成 99+
    expect(find.text('51'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('点条目回传下标；禁用项点不动', (tester) async {
    final log = await pumpDrawer(tester);

    await tester.tap(find.text('本地音声'));
    await tester.pumpAndSettle();
    expect(log, [0]);

    await tester.tap(find.text('在线收藏'));
    await tester.pumpAndSettle();
    expect(log, [0, 2]);

    await tester.tap(find.text('正在播放'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(log, [0, 2], reason: 'enabled: false 的条目不该回调');
  });

  testWidgets('选中项用实心图标，且只有一项是选中态', (tester) async {
    await pumpDrawer(tester, selectedIndex: 1);

    // 选中项画 selectedIcon（在线 → cloud_rounded）
    expect(find.byIcon(Icons.cloud_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsNothing);
    // 未选中项保持静息图标
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);

    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((w) => w.properties.selected ?? false)
        .length;
    expect(selected, 1, reason: '抽屉里只能有一项选中');
  });

  testWidgets('hint 文案在底部显示', (tester) async {
    await pumpDrawer(tester, hint: '从屏幕左缘往右拖可随时拉出');
    expect(find.text('从屏幕左缘往右拖可随时拉出'), findsOneWidget);
  });

  testWidgets('没有选中项时（分类视图）不崩', (tester) async {
    await pumpDrawer(tester, selectedIndex: -1);
    expect(tester.takeException(), isNull);
    expect(find.text('在线'), findsOneWidget);
  });
}
