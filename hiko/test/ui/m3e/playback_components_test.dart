import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

/// 1.99.29 播放面新组件的契约锁（plan §8.5 / §8.6）：
/// M3EToolbar 64dp 全圆 / M3ESlider 16dp 粗轨 + 4×44 把手 / M3EFab 96dp 角 28 /
/// M3ESheet 侧滑与底部两种材质。
Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('M3EToolbar：高 64、全圆、surfaceContainerHigh 底', (tester) async {
    await tester.pumpWidget(host(const M3EToolbar(child: SizedBox())));
    final box = tester.renderObject<RenderBox>(find.byType(M3EToolbar));
    expect(box.size.height, 64 + 32, reason: '64 内容高 + 16×2 外边距');

    final decor = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(M3EToolbar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final shape = decor.decoration as BoxDecoration;
    expect(shape.borderRadius!.resolve(TextDirection.ltr).topLeft.x, 999,
        reason: '全圆（M3EShape.full = 999）');
    expect(shape.color, M3ETheme.of(tester.element(find.byType(M3EToolbar))).colors.surfaceContainerHigh);
  });

  testWidgets('M3ESlider：内含 Material Slider，轨道 16、把手 4×44', (tester) async {
    await tester.pumpWidget(host(
      M3ESlider(
        value: 0.5,
        max: 1,
        onChanged: (_) {},
      ),
    ));
    expect(find.byType(Slider), findsOneWidget);
    // 轨道粗 16 —— M3E 与旧滑杆（3px）的最大观感差（plan §8.5）
    final theme = SliderTheme.of(tester.element(find.byType(Slider)));
    expect(theme.trackHeight, 16);
    // 把手 4×44 竖条
    expect(const M3ESliderThumb().getPreferredSize(true, false),
        const Size(4, 44));
  });

  testWidgets('M3EFab：96dp、角 28、点按回调', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(
      M3EFab(onPressed: () => taps++, child: const Icon(Icons.play_arrow)),
    ));
    expect(tester.getSize(find.byType(M3EFab)), const Size(96, 96));

    final decor = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(M3EFab),
            matching: find.byType(Container),
          )
          .first,
    );
    final shape = decor.decoration! as BoxDecoration;
    expect(shape.borderRadius!.resolve(TextDirection.ltr).topLeft.x, 28);

    await tester.tap(find.byType(M3EFab));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('M3ESheet：side 贴边实底；bottom 28dp 顶角', (tester) async {
    await tester.pumpWidget(host(
      Column(
        children: const [
          M3ESheet(variant: M3ESheetVariant.side, child: SizedBox(height: 40)),
          M3ESheet(
              variant: M3ESheetVariant.bottom, child: SizedBox(height: 40)),
        ],
      ),
    ));
    final sheets = find.byType(M3ESheet);
    expect(sheets, findsNWidgets(2));

    final side = tester.widget<M3ESheet>(sheets.at(0));
    final sideDecor = tester
        .widget<DecoratedBox>(
          find.descendant(
            of: sheets.at(0),
            matching: find.byType(DecoratedBox),
          ),
        )
        .decoration as BoxDecoration;
    expect(sideDecor.color,
        M3ETheme.of(tester.element(sheets.first)).colors.surfaceContainerLow);
    expect(sideDecor.borderRadius, isNull, reason: 'side 贴边不设圆角');
    expect(side.variant, M3ESheetVariant.side);

    final bottomDecor = tester
        .widget<DecoratedBox>(
          find.descendant(
            of: sheets.at(1),
            matching: find.byType(DecoratedBox),
          ),
        )
        .decoration as BoxDecoration;
    expect(
      bottomDecor.borderRadius!.resolve(TextDirection.ltr).topLeft.x,
      28,
      reason: 'bottom 变体 28dp 顶角（plan §8.4）',
    );
  });
}
