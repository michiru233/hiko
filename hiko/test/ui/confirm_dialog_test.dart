import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/confirm_dialog.dart';

import 'm3e/m3e_test_harness.dart';

/// 确认框的端到端锁（1.99.42）。
///
/// `showConfirmDialog` 有 7 个调用点（删专辑 / 删歌单 / 清空黑名单 / 删分类…），
/// 是这一批里最承重的一个。组件测试只锁 `M3EDialog` 自己，这里锁
/// 「壳换掉之后返回值语义没变」：取消 = false、确认 = true、点遮罩 = false。
void main() {
  Future<void> pumpTrigger(
    WidgetTester tester,
    void Function(bool?) onResult,
  ) async {
    await tester.pumpWidget(
      wrapM3E(
        Builder(
          builder: (context) => M3EButton(
            label: '打开',
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: '删除专辑',
                message: '删除后不可恢复。',
                okLabel: '删除',
              );
              onResult(ok);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('取消返回 false；确认返回 true', (tester) async {
    bool? result;
    await pumpTrigger(tester, (v) => result = v);

    expect(find.byType(M3EDialog), findsOneWidget);
    expect(find.text('删除专辑'), findsOneWidget);
    expect(find.text('删除后不可恢复。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await pumpTrigger(tester, (v) => result = v);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('点遮罩关掉：按取消处理（false）', (tester) async {
    bool? result;
    await pumpTrigger(tester, (v) => result = v);

    // 遮罩在对话框外侧，点左上角
    await tester.tapAt(const Offset(6, 6));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('确认键是 destructive（error 底），不是旧的写死红', (tester) async {
    final data = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        theme: data,
        Builder(
          builder: (context) => M3EButton(
            label: '打开',
            onPressed: () =>
                showConfirmDialog(context, title: '删除', message: '确认？'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final confirm = find.descendant(
      of: find.byType(M3EDialog),
      matching: find.widgetWithText(M3EButton, '删除'),
    );
    final container = tester.widget<Container>(
      find.descendant(of: confirm, matching: find.byType(Container)).first,
    );
    expect((container.decoration! as BoxDecoration).color, data.colors.error);
  });
}
