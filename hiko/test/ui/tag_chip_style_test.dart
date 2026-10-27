import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/detail_kit.dart';

/// 标签胶囊的材质锁（1.99.56 裁决 B）。
///
/// 来龙去脉：在线详情一屏里有声优蓝、社团琥珀、作品号实底、下载量玫红，
/// 再加十个青绿标签 —— 标签数量最多，"绿字"直接把整页的情绪基调带跑了，
/// 而且在中文语境里容易被读成「成功 / 在线」。
///
/// 裁决是把标签退回中性，用**常驻 1px 描边**保住「可以点」的手感
/// （悬停时描边加深）。这条锁防的就是有人日后又把颜色加回来。
void main() {
  const seed = Color(0xFF6750A4);

  Future<M3EThemeData> pump(
    WidgetTester tester, {
    bool dark = true,
    bool muted = false,
    bool blocked = false,
    String tag = 'ASMR',
  }) async {
    final data = M3EThemeData.fromSeed(
      seed: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: data,
          child: Scaffold(
            body: Center(
              child: HikoTagChip(tag: tag, muted: muted, blocked: blocked),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return data;
  }

  BoxDecoration? boxOf(WidgetTester tester, Color color) {
    final finder = find.descendant(
      of: find.byType(HikoTagChip),
      matching: find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            (w.decoration as BoxDecoration?)?.color == color,
      ),
    );
    if (finder.evaluate().isEmpty) return null;
    final widget = tester.widget<AnimatedContainer>(finder.first);
    return widget.decoration as BoxDecoration;
  }

  Border? restingBorder(WidgetTester tester) {
    final containers = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(HikoTagChip),
        matching: find.byType(AnimatedContainer),
      ),
    );
    for (final c in containers) {
      final fg = c.foregroundDecoration;
      if (fg is BoxDecoration && fg.border != null) return fg.border as Border;
    }
    return null;
  }

  testWidgets('普通标签：surfaceContainerHighest 底 + onSurfaceVariant 字', (tester) async {
    final data = await pump(tester);
    final colors = data.colors;

    expect(
      boxOf(tester, colors.surfaceContainerHighest),
      isNotNull,
      reason: '标签底色必须回到中性容器，不能再有专属色相',
    );
    final text = tester.widget<Text>(find.text('ASMR'));
    expect(text.style?.color, colors.onSurfaceVariant);
  });

  testWidgets('普通标签：静息就有 1px outlineVariant 描边（可点感靠它）', (tester) async {
    final data = await pump(tester);

    final border = restingBorder(tester);
    expect(border, isNotNull, reason: '标签可点，静息态必须有一条描边');
    expect(border!.top.color, data.colors.outlineVariant);
    expect(border.top.width, 1);
  });

  testWidgets('弱化标签（+N / 已屏蔽）：低一档的容器 + 更淡的字', (tester) async {
    final data = await pump(tester, muted: true);
    final colors = data.colors;

    expect(boxOf(tester, colors.surfaceContainerHigh), isNotNull);
    final text = tester.widget<Text>(find.text('ASMR'));
    expect(text.style?.color?.a, lessThan(1.0), reason: '弱化态的字要更淡');
  });
}
