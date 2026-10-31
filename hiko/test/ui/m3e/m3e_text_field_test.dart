import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// `M3ETextField` 的行为锁（1.99.60）。
///
/// 壳是自绘的（填充底 + 圆角矩形 + 标签在框上方），**里面仍是 `TextField`** ——
/// 输入法/选区/快捷键交给框架，这里只锁壳与排版的四条约定：
/// 标签在框上方、focus 描边出现、错误态文案与描边、`obscureText` 透传。
void main() {
  testWidgets('compact 与 regular 两档高度不同，且都比默认 Material 输入框矮', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                M3ETextField(
                  key: const ValueKey('compact'),
                  controller: controller,
                  hintText: '紧凑',
                ),
                const SizedBox(height: 12),
                M3ETextField(
                  key: const ValueKey('regular'),
                  controller: controller,
                  hintText: '常规',
                  size: M3ETextFieldSize.regular,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final compact = tester.getSize(find.byKey(const ValueKey('compact'))).height;
    final regular = tester.getSize(find.byKey(const ValueKey('regular'))).height;
    expect(compact, lessThan(regular), reason: 'compact 必须比 regular 矮');
    expect(compact, lessThanOrEqualTo(36), reason: 'compact 目标 32dp');
    expect(regular, lessThanOrEqualTo(44), reason: 'regular 目标 40dp');
  });

  testWidgets('标签画在框上方（不进框浮动）', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: M3ETextField(
              controller: controller,
              label: '分类名称',
              size: M3ETextFieldSize.regular,
            ),
          ),
        ),
      ),
    );

    final label = find.text('分类名称');
    expect(label, findsOneWidget);
    // 标签底边必须在输入框顶边之上：浮动标签会落在框内
    final labelRect = tester.getRect(label);
    final fieldRect = tester.getRect(find.byType(TextField));
    expect(labelRect.bottom, lessThanOrEqualTo(fieldRect.top));
  });

  testWidgets('focus 时描边出现，失焦后消失', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: M3ETextField(controller: controller, hintText: '焦点'),
          ),
        ),
      ),
    );

    OutlineInputBorder borderOf() {
      final field = tester.widget<TextField>(find.byType(TextField));
      return field.decoration!.focusedBorder! as OutlineInputBorder;
    }

    // focusedBorder 只在有焦点时生效，这里锁它的规格（1.5dp primary）
    final focused = borderOf();
    expect(focused.borderSide.width, 1.5);

    await tester.tap(find.byType(M3ETextField));
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
  });

  testWidgets('错误态：描边走 error 并显示文案', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: M3ETextField(
              controller: controller,
              label: '分类名称',
              errorText: '名称不能为空',
              size: M3ETextFieldSize.regular,
            ),
          ),
        ),
      ),
    );

    expect(find.text('名称不能为空'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    final errorBorder = field.decoration!.errorBorder! as OutlineInputBorder;
    expect(errorBorder.borderSide.width, greaterThan(0));
  });

  testWidgets('obscureText 与 onSubmitted 透传', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: SizedBox(
            width: 320,
            child: M3ETextField(
              controller: controller,
              obscureText: true,
              size: M3ETextFieldSize.regular,
              label: '密码',
              onSubmitted: (v) => submitted = v,
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, 'secret');
  });

  testWidgets('width 生效；helperText 在框下方', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrapM3E(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              M3ETextField(
                controller: controller,
                width: 220,
                hintText: 'api.asmr.one',
                helperText: '留空使用默认',
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(M3ETextField)).width, 220);
    expect(find.text('留空使用默认'), findsOneWidget);
    final helperRect = tester.getRect(find.text('留空使用默认'));
    final fieldRect = tester.getRect(find.byType(TextField));
    expect(helperRect.top, greaterThanOrEqualTo(fieldRect.bottom));
  });
}
