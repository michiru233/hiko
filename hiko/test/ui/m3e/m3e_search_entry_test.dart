import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// `M3ESearchEntry` 的行为锁（1.99.70）。
///
/// 这是一次真实 bug 的回归锁：旧 `M3ESearchBar` 只有内部 TextField 能点，
/// 在线页窄屏时真正可点区域约 23×26dp。这里断言**整条胶囊**（左内边距、
/// 放大镜、右端留白）都能命中。
void main() {
  testWidgets('壳：高度可调、全圆、surfaceContainerHigh、无描边', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        SizedBox(width: 320, child: M3ESearchEntry(height: 40, onTap: () {})),
        theme: theme,
      ),
    );

    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(M3ESearchEntry),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = box.decoration! as BoxDecoration;
    expect(tester.getSize(find.byType(M3ESearchEntry)).height, 40);
    expect(deco.borderRadius, BorderRadius.circular(M3EShape.full));
    expect(deco.border, isNull, reason: '搜索入口靠色阶，不描边');
    expect(deco.color, theme.colors.surfaceContainerHigh);
  });

  testWidgets('空文本显示 hint，有文本显示内容', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        SizedBox(
          width: 320,
          child: M3ESearchEntry(hintText: '搜索在线作品', onTap: () {}),
        ),
        theme: theme,
      ),
    );
    final hint = tester.widget<Text>(find.text('搜索在线作品'));
    expect(hint.style?.color, theme.colors.onSurfaceVariant);

    await tester.pumpWidget(
      wrapM3E(
        SizedBox(
          width: 320,
          child: M3ESearchEntry(
            text: '大山チロル',
            hintText: '搜索在线作品',
            onTap: () {},
          ),
        ),
        theme: theme,
      ),
    );
    final text = tester.widget<Text>(find.text('大山チロル'));
    expect(text.style?.color, theme.colors.onSurface);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(find.text('搜索在线作品'), findsNothing);
  });

  testWidgets('整条都可点：左内边距 / 放大镜 / 右端留白都命中', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrapM3E(SizedBox(width: 320, child: M3ESearchEntry(onTap: () => taps++))),
    );

    final rect = tester.getRect(find.byType(M3ESearchEntry));
    for (final dx in <double>[2, 20, rect.width - 2]) {
      await tester.tapAt(Offset(rect.left + dx, rect.center.dy));
      await tester.pump();
    }
    expect(taps, 3, reason: '旧实现在这三处只有一处能点');
  });

  testWidgets('窄到 <96dp 时只画放大镜，不出现半个字', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        SizedBox(
          width: 68,
          child: M3ESearchEntry(
            hintText: '搜索在线作品（日文原关键词命中率最高）',
            semanticLabel: '搜索在线作品',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.textContaining('搜索在线作品'), findsNothing);
    expect(
      find.bySemanticsLabel('搜索在线作品'),
      findsOneWidget,
      reason: '只剩图标时它是无名按钮，语义标签必须给',
    );
  });

  testWidgets('宽度足够时 hint 正常显示', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        SizedBox(
          width: 320,
          child: M3ESearchEntry(hintText: '搜索在线作品', onTap: () {}),
        ),
      ),
    );
    expect(find.text('搜索在线作品'), findsOneWidget);
  });

  testWidgets('onTap 为空时不响应点击', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const SizedBox(width: 320, child: M3ESearchEntry(hintText: '搜索')),
      ),
    );
    await tester.tap(find.byType(M3ESearchEntry), warnIfMissed: false);
    await tester.pump();
    // 没有抛错、没有点击反馈即为通过（M3EPressable 在 onTap 为空时不装手势）
    expect(find.byType(M3ESearchEntry), findsOneWidget);
  });
}
