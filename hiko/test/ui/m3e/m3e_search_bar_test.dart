import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// `M3ESearchBar` 的行为锁（1.99.45）。
///
/// 壳是自绘的（56 全圆 + `surfaceContainerHigh`），**里面仍是 `TextField`** ——
/// 所以这里锁三件事：高度/圆角/无描边、输入回调透传、清除钮只在有字时出现。
void main() {
  testWidgets('壳：40 高（可调）、全圆、surfaceContainerHigh、无描边', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: M3ESearchBar(controller: controller, height: 40),
          ),
        ),
      ),
    );

    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(M3ESearchBar),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = box.decoration! as BoxDecoration;
    expect(
      box.constraints?.maxHeight ??
          tester.getSize(find.byType(M3ESearchBar)).height,
      40,
    );
    expect(deco.borderRadius, BorderRadius.circular(M3EShape.full));
    expect(deco.border, isNull, reason: 'M3 搜索栏靠色阶，不描边');
  });

  testWidgets('输入透传 onChanged / onSubmitted', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    final submits = <String>[];

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: M3ESearchBar(
              controller: controller,
              onChanged: changes.add,
              onSubmitted: submits.add,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'アリス');
    expect(changes, <String>['アリス']);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(submits, <String>['アリス']);
  });

  testWidgets('清除钮：无字不出现，有字出现且点了清空 + 回调', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var cleared = 0;

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: M3ESearchBar(
              controller: controller,
              onClear: () => cleared++,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(cleared, 1);
  });
}
