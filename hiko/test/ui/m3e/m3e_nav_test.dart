import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

List<M3ENavigationDestination> _destinations(int count) =>
    <M3ENavigationDestination>[
      for (var i = 0; i < count; i++)
        M3ENavigationDestination(
          label: '项$i',
          icon: Icons.circle_outlined,
          selectedIcon: Icons.circle,
        ),
    ];

void main() {
  group('foldDestinations（导航折叠规则）', () {
    test('不超容量时全部可见、无溢出', () {
      final result = foldDestinations(_destinations(2), reservedSlots: 1);
      expect(result.visible, hasLength(2));
      expect(result.overflow, isEmpty);
    });

    test('7 项 + 1 个常驻格 → 3 可见 + 4 溢出', () {
      final result = foldDestinations(_destinations(7), reservedSlots: 1);
      expect(result.visible.map((d) => d.label), <String>['项0', '项1', '项2']);
      expect(result.overflow, hasLength(4));
      expect(result.overflow.first.label, '项3');
    });

    test('常驻格越多，可见导航项越少', () {
      expect(
        foldDestinations(_destinations(7), reservedSlots: 0).visible,
        hasLength(4),
      );
      expect(
        foldDestinations(_destinations(7), reservedSlots: 2).visible,
        hasLength(2),
      );
    });

    test('再多常驻格也至少留一格可见', () {
      expect(
        foldDestinations(_destinations(7), reservedSlots: 9).visible,
        hasLength(1),
      );
    });
  });

  group('M3ENavBar', () {
    testWidgets('渲染全部目的地，选中项换成实心图标', (tester) async {
      await tester.pumpWidget(
        wrapM3E(
          M3ENavBar(
            destinations: _destinations(4),
            selectedIndex: 1,
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.text('项0'), findsOneWidget);
      expect(find.text('项3'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget);
      expect(find.byIcon(Icons.circle_outlined), findsNWidgets(3));
    });

    testWidgets('点击第 i 格回调 i', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(
        wrapM3E(
          M3ENavBar(
            destinations: _destinations(3),
            selectedIndex: 0,
            onSelected: (i) => tapped = i,
          ),
        ),
      );
      await tester.tap(find.text('项2'));
      await tester.pumpAndSettle();
      expect(tapped, 2);
    });

    testWidgets('禁用项置灰、不回调，但仍占一格', (tester) async {
      var tapped = -1;
      final destinations = <M3ENavigationDestination>[
        ..._destinations(2),
        const M3ENavigationDestination(
          label: '正在播放',
          icon: Icons.play_circle_outline,
          selectedIcon: Icons.play_circle,
          enabled: false,
        ),
      ];
      await tester.pumpWidget(
        wrapM3E(
          M3ENavBar(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: (i) => tapped = i,
          ),
        ),
      );
      await tester.tap(find.text('正在播放'));
      await tester.pumpAndSettle();
      expect(tapped, -1);
      expect(find.text('正在播放'), findsOneWidget);
    });
  });

  group('M3ENavRail', () {
    testWidgets('收起态显示标签，选中项实心', (tester) async {
      await tester.pumpWidget(
        wrapM3E(
          SizedBox(
            width: HikoShell.collapsedWidth,
            child: M3ENavRail(
              destinations: _destinations(3),
              selectedIndex: 0,
              expanded: false,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('项0'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget);
    });

    testWidgets('点击回调下标', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(
        wrapM3E(
          SizedBox(
            width: HikoShell.expandedWidth,
            child: M3ENavRail(
              destinations: _destinations(3),
              selectedIndex: 0,
              expanded: true,
              onSelected: (i) => tapped = i,
            ),
          ),
        ),
      );
      await tester.tap(find.text('项1'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('底部动作项（设置）可点', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        wrapM3E(
          SizedBox(
            width: HikoShell.expandedWidth,
            child: M3ENavRail(
              destinations: _destinations(2),
              selectedIndex: -1,
              expanded: true,
              onSelected: (_) {},
              trailing: M3ENavRailAction(
                icon: Icons.settings_outlined,
                label: '设置',
                expanded: true,
                onTap: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });

  group('HikoShell', () {
    testWidgets('没有 rail 时只渲染内容（compact）', (tester) async {
      await tester.pumpWidget(
        wrapM3E(const HikoShell(child: Text('内容'))),
      );
      expect(find.text('内容'), findsOneWidget);
      expect(find.byType(M3ENavRail), findsNothing);
    });

    testWidgets('expanded 宽度 220，medium 收起 96', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrapM3E(
          HikoShell(
            rail: const SizedBox(key: Key('rail')),
            child: const Text('内容'),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('rail'))).width, 220);

      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('rail'))).width, 96);
    });
  });

  group('M3EChip', () {
    testWidgets('未选中带描边、无勾', (tester) async {
      await tester.pumpWidget(
        wrapM3E(M3EChip(label: '分类', onTap: () {})),
      );
      final container = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(M3EChip),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.color, Colors.transparent);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('选中态：secondaryContainer 底 + 勾 + 去描边', (tester) async {
      final theme = testTheme();
      await tester.pumpWidget(
        wrapM3E(
          M3EChip(label: '分类', selected: true, onTap: () {}),
          theme: theme,
        ),
      );
      final container = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(M3EChip),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, theme.colors.secondaryContainer);
      expect(decoration.border, isNull);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('点击回调', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        wrapM3E(M3EChip(label: '分类', onTap: () => tapped++)),
      );
      await tester.tap(find.text('分类'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });
  });

  group('断点', () {
    test('600 / 840 两个阈值', () {
      expect(hikoWindowSize(599), HikoWindowSize.compact);
      expect(hikoWindowSize(600), HikoWindowSize.medium);
      expect(hikoWindowSize(839), HikoWindowSize.medium);
      expect(hikoWindowSize(840), HikoWindowSize.expanded);
    });
  });
}
