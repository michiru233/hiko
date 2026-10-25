import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(M3EIconButton),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('默认尺寸：视觉 40 / 热区 48 / 图标 24', (tester) async {
    await tester.pumpWidget(
      wrapM3E(M3EIconButton(icon: Icons.close, onPressed: () {})),
    );
    expect(tester.getSize(find.byType(M3EIconButton)), const Size(48, 48));
    expect(
      tester.getSize(
        find
            .descendant(
              of: find.byType(M3EIconButton),
              matching: find.byType(Container),
            )
            .first,
      ),
      const Size(40, 40),
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.close)).size, 24);
  });

  testWidgets('三档尺寸：32/40/48 视觉，热区 40/48/56', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            M3EIconButton(
              icon: Icons.add,
              size: M3EIconButtonSize.small,
              onPressed: () {},
            ),
            M3EIconButton(
              icon: Icons.add,
              size: M3EIconButtonSize.medium,
              onPressed: () {},
            ),
            M3EIconButton(
              icon: Icons.add,
              size: M3EIconButtonSize.large,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    final sizes = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(M3EIconButton),
            matching: find.byType(SizedBox),
          ),
        )
        .where((s) => s.width == s.height && s.width != null)
        .map((s) => s.width)
        .toList();
    expect(sizes, containsAll(<double>[40, 48, 56]));
  });

  testWidgets('standard：无底、onSurfaceVariant 图标', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EIconButton(icon: Icons.more_horiz, onPressed: () {}),
        theme: theme,
      ),
    );
    expect(_decoration(tester).color, isNull);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.more_horiz)).color,
      theme.colors.onSurfaceVariant,
    );
  });

  testWidgets('filled / tonal / outlined 的容器色与描边', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            M3EIconButton(
              icon: Icons.play_arrow,
              variant: M3EIconButtonVariant.filled,
              onPressed: () {},
            ),
            M3EIconButton(
              icon: Icons.pause,
              variant: M3EIconButtonVariant.tonal,
              onPressed: () {},
            ),
            M3EIconButton(
              icon: Icons.stop,
              variant: M3EIconButtonVariant.outlined,
              onPressed: () {},
            ),
          ],
        ),
        theme: theme,
      ),
    );

    BoxDecoration decorationOf(IconData icon) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    expect(decorationOf(Icons.play_arrow).color, theme.colors.primary);
    expect(decorationOf(Icons.pause).color, theme.colors.secondaryContainer);
    expect(decorationOf(Icons.stop).color, isNull);
    expect(
      decorationOf(Icons.stop).border!.top.color,
      theme.colors.outlineVariant,
    );
  });

  testWidgets('selected：standard 自动换 secondaryContainer 底', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EIconButton(icon: Icons.favorite, selected: true, onPressed: () {}),
        theme: theme,
      ),
    );
    expect(_decoration(tester).color, theme.colors.secondaryContainer);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.favorite)).color,
      theme.colors.onSecondaryContainer,
    );
  });

  testWidgets('禁用：图标 38%、filled 底 12%、点击无回调', (tester) async {
    final theme = testTheme();
    var tapped = 0;
    await tester.pumpWidget(
      wrapM3E(
        M3EIconButton(
          icon: Icons.delete,
          variant: M3EIconButtonVariant.filled,
          onPressed: null,
        ),
        theme: theme,
      ),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.delete)).color,
      theme.colors.onSurface.withValues(alpha: 0.38),
    );
    expect(
      _decoration(tester).color,
      theme.colors.onSurface.withValues(alpha: 0.12),
    );
    await tester.tap(find.byType(M3EIconButton));
    await tester.pumpAndSettle();
    expect(tapped, 0);
  });

  testWidgets('tooltip 可点击并触发回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrapM3E(
        M3EIconButton(
          icon: Icons.arrow_back,
          tooltip: '返回',
          onPressed: () => tapped++,
        ),
      ),
    );
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('foregroundColor 覆盖图标色（收藏态）', (tester) async {
    const favorite = Color(0xFFE04C6A);
    await tester.pumpWidget(
      wrapM3E(
        M3EIconButton(
          icon: Icons.bookmark,
          foregroundColor: favorite,
          onPressed: () {},
        ),
      ),
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.bookmark)).color, favorite);
  });

  testWidgets('长按回调可用', (tester) async {
    var longPressed = 0;
    await tester.pumpWidget(
      wrapM3E(
        M3EIconButton(
          icon: Icons.menu,
          onPressed: () {},
          onLongPress: () => longPressed++,
        ),
      ),
    );
    await tester.longPress(find.byType(M3EIconButton));
    await tester.pumpAndSettle();
    expect(longPressed, 1);
  });
}
