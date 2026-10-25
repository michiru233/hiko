import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

BoxDecoration _buttonDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byType(M3EButton), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('filled：primary 底 + onPrimary 字 + emphasized 字重', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(M3EButton(label: '确定', onPressed: () {}), theme: theme),
    );
    expect(_buttonDecoration(tester).color, theme.colors.primary);
    final text = tester.widget<Text>(find.text('确定'));
    expect(text.style!.color, theme.colors.onPrimary);
    expect(text.style!.fontWeight, FontWeight.w700);
  });

  testWidgets('tonal：secondaryContainer 底 + 基础字重', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EButton(
          label: '稍后',
          onPressed: () {},
          variant: M3EButtonVariant.tonal,
        ),
        theme: theme,
      ),
    );
    expect(_buttonDecoration(tester).color, theme.colors.secondaryContainer);
    expect(
      tester.widget<Text>(find.text('稍后')).style!.fontWeight,
      FontWeight.w500,
    );
  });

  testWidgets('outlined：无底色 + 1dp 描边', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EButton(
          label: '取消',
          onPressed: () {},
          variant: M3EButtonVariant.outlined,
        ),
        theme: theme,
      ),
    );
    final decoration = _buttonDecoration(tester);
    expect(decoration.color, isNull);
    expect(decoration.border!.top.color, theme.colors.outline);
  });

  testWidgets('text：无底无描边', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        M3EButton(
          label: '了解更多',
          onPressed: () {},
          variant: M3EButtonVariant.text,
        ),
      ),
    );
    final decoration = _buttonDecoration(tester);
    expect(decoration.color, isNull);
    expect(decoration.border, isNull);
  });

  testWidgets('禁用：容器 12% onSurface、文字 38%、点了没反应', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(const M3EButton(label: '提交', onPressed: null), theme: theme),
    );
    expect(
      _buttonDecoration(tester).color,
      theme.colors.onSurface.withValues(alpha: 0.12),
    );
    expect(
      tester.widget<Text>(find.text('提交')).style!.color,
      theme.colors.onSurface.withValues(alpha: 0.38),
    );
    await tester.tap(find.byType(M3EButton));
    await tester.pumpAndSettle();
  });

  testWidgets('点击触发 onPressed', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      wrapM3E(M3EButton(label: '播放', onPressed: () => pressed++)),
    );
    await tester.tap(find.byType(M3EButton));
    await tester.pumpAndSettle();
    expect(pressed, 1);
  });

  testWidgets('三档高度 32 / 40 / 56', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            M3EButton(label: '小', onPressed: () {}, size: M3EButtonSize.small),
            M3EButton(label: '中', onPressed: () {}),
            M3EButton(label: '大', onPressed: () {}, size: M3EButtonSize.large),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.widgetWithText(Container, '小').first).height,
      32,
    );
    expect(
      tester.getSize(find.widgetWithText(Container, '中').first).height,
      40,
    );
    expect(
      tester.getSize(find.widgetWithText(Container, '大').first).height,
      56,
    );
  });

  testWidgets('圆角恒为全圆', (tester) async {
    await tester.pumpWidget(
      wrapM3E(M3EButton(label: '圆', onPressed: () {})),
    );
    expect(
      _buttonDecoration(tester).borderRadius,
      BorderRadius.circular(M3EShape.full),
    );
  });

  testWidgets('带图标时图标颜色跟随前景色', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EButton(
          label: '导入',
          onPressed: () {},
          icon: const Icon(Icons.add),
        ),
        theme: theme,
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.add));
    expect(icon.color, isNull); // 颜色由 IconTheme 提供
    final iconTheme = IconTheme.of(
      tester.element(find.byIcon(Icons.add)),
    );
    expect(iconTheme.color, theme.colors.onPrimary);
  });
}
