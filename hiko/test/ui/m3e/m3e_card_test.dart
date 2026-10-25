import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

Decoration _cardDecoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(of: find.byType(M3ECard), matching: find.byType(DecoratedBox))
        .first,
  );
  return box.decoration;
}

void main() {
  testWidgets('filled 用 surfaceContainerHighest', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(const M3ECard(child: Text('内容')), theme: theme),
    );
    final decoration = _cardDecoration(tester) as BoxDecoration;
    expect(decoration.color, theme.colors.surfaceContainerHighest);
  });

  testWidgets('elevated 带 1dp 阴影', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const M3ECard(variant: M3ECardVariant.elevated, child: Text('内容')),
      ),
    );
    final decoration = _cardDecoration(tester) as BoxDecoration;
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('outlined 画 1dp 描边且不投影', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        const M3ECard(variant: M3ECardVariant.outlined, child: Text('内容')),
        theme: theme,
      ),
    );
    final boxes = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(M3ECard),
            matching: find.byType(DecoratedBox),
          ),
        )
        .toList();
    final bordered = boxes
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null)
        .toList();
    expect(bordered, hasLength(1));
    expect(bordered.single.border!.top.color, theme.colors.outlineVariant);
    final filled = boxes
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color != null);
    expect(filled.boxShadow, isEmpty);
  });

  testWidgets('默认圆角 16（Hiko 内容面基准，不是 M3 的 12）', (tester) async {
    await tester.pumpWidget(wrapM3E(const M3ECard(child: Text('内容'))));
    final decoration = _cardDecoration(tester) as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(M3EShape.lg));
  });

  testWidgets('自定义底色优先于变体', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3ECard(color: theme.colors.primaryContainer, child: const Text('内容')),
        theme: theme,
      ),
    );
    final decoration = _cardDecoration(tester) as BoxDecoration;
    expect(decoration.color, theme.colors.primaryContainer);
  });

  testWidgets('可点卡片触发回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrapM3E(M3ECard(onTap: () => tapped++, child: const Text('内容'))),
    );
    await tester.tap(find.byType(M3ECard));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('不可点卡片不包交互层（少一层 Stack）', (tester) async {
    await tester.pumpWidget(wrapM3E(const M3ECard(child: Text('内容'))));
    expect(
      find.descendant(
        of: find.byType(M3ECard),
        matching: find.byType(M3EPressable),
      ),
      findsNothing,
    );
  });
}
