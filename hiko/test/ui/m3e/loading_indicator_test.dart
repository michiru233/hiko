import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

/// M3ELoadingIndicator 契约（1.99.31，用户裁决引入 material_new_shapes）：
/// 动效三档门控——off 不建控制器（树里无 Repeat）且画静态形状；
/// 动画态逐帧换 morph 路径；默认 38dp。
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('默认：38dp、CustomPaint 渲染、无异常', (tester) async {
    await tester.pumpWidget(host(const M3ELoadingIndicator()));
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    final box = tester.renderObject<RenderBox>(
      find.descendant(
        of: find.byType(M3ELoadingIndicator),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(box.size.width, 38);
  });

  testWidgets('尺寸可调（24dp 内联场景）', (tester) async {
    await tester.pumpWidget(host(const M3ELoadingIndicator(size: 24)));
    final box = tester.renderObject<RenderBox>(
      find.descendant(
        of: find.byType(M3ELoadingIndicator),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(box.size.width, 24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('推进若干帧不抛异常（morph 路径逐帧重建）', (tester) async {
    await tester.pumpWidget(host(const M3ELoadingIndicator()));
    // 900ms/段 × 3 段：推过一个完整循环覆盖三段 morph
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
  });
}
