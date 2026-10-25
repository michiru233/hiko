import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

AnimatedContainer _itemContainer(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(M3EListItem),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

void main() {
  testWidgets('单行 56dp、双行 72dp', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            M3EListItem(title: '单行'),
            M3EListItem(title: '双行', subtitle: '副标题'),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.widgetWithText(M3EListItem, '单行')).height,
      56,
    );
    expect(
      tester.getSize(find.widgetWithText(M3EListItem, '双行')).height,
      72,
    );
  });

  testWidgets('静息态圆角 4dp、透明底', (tester) async {
    await tester.pumpWidget(wrapM3E(const M3EListItem(title: '曲目')));
    final decoration = _itemContainer(tester).decoration! as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.borderRadius, BorderRadius.circular(M3EShape.xs));
  });

  testWidgets('选中态：secondaryContainer 底 + 圆角 16 + 标题升到 emphasized 字重', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(const M3EListItem(title: '曲目', selected: true), theme: theme),
    );
    final decoration = _itemContainer(tester).decoration! as BoxDecoration;
    expect(decoration.color, theme.colors.secondaryContainer);
    expect(decoration.borderRadius, BorderRadius.circular(M3EShape.lg));
    // body 的 emphasized 是 400→500（只有 title 中/小与 label 才到 700），
    // 这里断言的是「比静息态重」，不是「等于 700」。
    expect(
      tester.widget<Text>(find.text('曲目')).style!.fontWeight,
      FontWeight.w500,
    );
  });

  testWidgets('选中色可覆盖（正在播放用 primaryContainer）', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EListItem(
          title: '曲目',
          selected: true,
          selectedColor: theme.colors.primaryContainer,
        ),
        theme: theme,
      ),
    );
    expect(
      (_itemContainer(tester).decoration! as BoxDecoration).color,
      theme.colors.primaryContainer,
    );
  });

  testWidgets('点击触发回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrapM3E(M3EListItem(title: '曲目', onTap: () => tapped++)),
    );
    await tester.tap(find.byType(M3EListItem));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('禁用态不触发、文字降透明度', (tester) async {
    var tapped = 0;
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        M3EListItem(
          title: '曲目',
          enabled: false,
          onTap: () => tapped++,
        ),
        theme: theme,
      ),
    );
    await tester.tap(find.byType(M3EListItem), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tapped, 0);
    expect(
      tester.widget<Text>(find.text('曲目')).style!.color,
      theme.colors.onSurface.withValues(alpha: 0.38),
    );
  });

  testWidgets('前后缀图标按 24dp 渲染', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const M3EListItem(
          title: '曲目',
          leading: Icon(Icons.music_note),
          trailing: Icon(Icons.chevron_right),
        ),
      ),
    );
    expect(IconTheme.of(tester.element(find.byIcon(Icons.music_note))).size, 24);
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.chevron_right))).size,
      24,
    );
  });

  testWidgets('列表容器按 gap 插入间距', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const M3EList(
          gap: 12,
          children: <Widget>[
            M3EListItem(title: 'A'),
            M3EListItem(title: 'B'),
          ],
        ),
      ),
    );
    final box = tester.getSize(find.byType(M3EList));
    // 56 + 12 + 56
    expect(box.height, 124);
  });
}
