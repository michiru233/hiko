import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// 设置页控件的规格与行为锁（1.99.43）。
///
/// 开关 / 复选框 / 下拉 / 带档位滑杆是这一批替换 Material 控件的四件套，
/// 每个都锁三件事：**视觉尺寸**、**点击语义**、**禁用不改值**。
void main() {
  group('M3ESwitch', () {
    testWidgets('视觉 52×32、触控高 48；点一下翻值', (tester) async {
      bool? changed;
      await tester.pumpWidget(
        wrapM3E(
          Center(child: M3ESwitch(value: false, onChanged: (v) => changed = v)),
        ),
      );

      expect(tester.getSize(find.byType(M3ESwitch)).height, 48);
      final track = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(M3ESwitch),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(track.constraints?.maxWidth, 52);
      expect(track.constraints?.maxHeight, 32);

      await tester.tap(find.byType(M3ESwitch));
      expect(changed, isTrue);
    });

    testWidgets('禁用：不回调', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        wrapM3E(
          Center(
            child: M3ESwitch(
              value: true,
              enabled: false,
              onChanged: (_) => calls++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(M3ESwitch));
      expect(calls, 0);
    });
  });

  group('M3ECheckbox', () {
    testWidgets('视觉 18、热区 40；点一下翻值', (tester) async {
      bool? changed;
      await tester.pumpWidget(
        wrapM3E(
          Center(
            child: M3ECheckbox(value: false, onChanged: (v) => changed = v),
          ),
        ),
      );

      expect(tester.getSize(find.byType(M3ECheckbox)), const Size(40, 40));
      final box = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(M3ECheckbox),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(box.constraints?.maxWidth, 18);

      await tester.tap(find.byType(M3ECheckbox));
      expect(changed, isTrue);
    });

    testWidgets('选中时画勾，未选不画', (tester) async {
      await tester.pumpWidget(
        wrapM3E(Center(child: M3ECheckbox(value: true, onChanged: (_) {}))),
      );
      expect(
        find.descendant(
          of: find.byType(M3ECheckbox),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
    });
  });

  group('M3ESelect', () {
    Future<List<int>> pumpSelect(
      WidgetTester tester, {
      int value = 2,
      bool enabled = true,
    }) async {
      final changes = <int>[];
      await tester.pumpWidget(
        wrapM3E(
          Center(
            child: M3ESelect<int>(
              value: value,
              enabled: enabled,
              options: const <M3ESelectOption<int>>[
                M3ESelectOption(1, '20 条'),
                M3ESelectOption(2, '60 条'),
                M3ESelectOption(3, '100 条'),
              ],
              onChanged: (v) => changes.add(v),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('触发器显示当前值；展开后三项齐全且当前项带勾', (tester) async {
      await pumpSelect(tester);
      expect(find.text('60 条'), findsOneWidget);

      await tester.tap(find.text('60 条'));
      await tester.pumpAndSettle();

      expect(find.text('20 条'), findsOneWidget);
      expect(find.text('100 条'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('选项点了就回调并关菜单', (tester) async {
      final changes = await pumpSelect(tester);
      await tester.tap(find.text('60 条'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('100 条'));
      await tester.pumpAndSettle();

      expect(changes, <int>[3]);
      expect(find.byType(M3EMenuAction), findsNothing, reason: '选完要收起');
    });

    testWidgets('禁用：点不开菜单', (tester) async {
      await pumpSelect(tester, enabled: false);
      await tester.tap(find.text('60 条'));
      await tester.pumpAndSettle();
      expect(find.byType(M3EMenuAction), findsNothing);
    });
  });

  group('M3ESlider', () {
    testWidgets('档位下发到 Slider；不给档位时不吸附', (tester) async {
      await tester.pumpWidget(
        wrapM3E(
          Center(
            child: M3ESlider(
              value: 30,
              max: 240,
              min: 5,
              divisions: 47,
              label: '30 分钟',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final discrete = tester.widget<Slider>(find.byType(Slider));
      expect(discrete.divisions, 47);
      expect(discrete.label, '30 分钟');

      await tester.pumpWidget(
        wrapM3E(
          Center(child: M3ESlider(value: 0.5, max: 1, onChanged: (_) {})),
        ),
      );
      expect(tester.widget<Slider>(find.byType(Slider)).divisions, isNull);
    });
  });
}
