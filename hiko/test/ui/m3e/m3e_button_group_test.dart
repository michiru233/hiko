import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

void main() {
  testWidgets('渲染全部段，选中段用 secondaryContainer 底', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EButtonGroup(
          labels: const <String>['全部', '未听完', '已收藏'],
          selectedIndex: 1,
          onSelected: (_) {},
        ),
        theme: theme,
      ),
    );
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('未听完'), findsOneWidget);
    expect(find.text('已收藏'), findsOneWidget);

    final containers = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(M3EButtonGroup),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .toList();
    final selected = containers
        .map((c) => (c.decoration! as BoxDecoration).color)
        .where((c) => c == theme.colors.secondaryContainer)
        .toList();
    expect(selected, hasLength(1), reason: '只允许一段是选中态');
  });

  testWidgets('点击第 i 段回调 i', (tester) async {
    var picked = -1;
    await tester.pumpWidget(
      wrapM3E(
        M3EButtonGroup(
          labels: const <String>['全部', '未听完', '已收藏'],
          selectedIndex: 0,
          onSelected: (i) => picked = i,
        ),
      ),
    );
    await tester.tap(find.text('已收藏'));
    await tester.pumpAndSettle();
    expect(picked, 2);
  });

  testWidgets('选中段用 emphasized 字重，未选中用基础字重', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        M3EButtonGroup(
          labels: const <String>['全部', '未听完'],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('全部')).style!.fontWeight,
      FontWeight.w700,
    );
    expect(
      tester.widget<Text>(find.text('未听完')).style!.fontWeight,
      FontWeight.w500,
    );
  });
}
