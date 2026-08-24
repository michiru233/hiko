import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/widgets/toast.dart';

/// 1.33 全局 toast 验收：根 Overlay、紧凑宽度、无下划线和自动消失。
void main() {
  testWidgets('对话框打开时 toast 浮于对话框之上', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('设置'),
                    actions: [
                      TextButton(
                        onPressed: () => showHikoToast(dialogContext, '置顶提示文案'),
                        child: const Text('触发提示'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('打开对话框'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开对话框'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget, reason: '对话框已打开');

    await tester.tap(find.text('触发提示'));
    await tester.pump();
    expect(find.text('设置'), findsOneWidget);
    expect(
      find.text('置顶提示文案'),
      findsOneWidget,
      reason: 'toast 走根 Overlay，必须浮于对话框之上且可见',
    );

    await tester.pump(const Duration(milliseconds: 3400));
    expect(find.text('置顶提示文案'), findsNothing);
  });

  testWidgets('新 toast 顶替旧 toast（同一时刻只有一条）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showHikoToast(context, '第一条');
                showHikoToast(context, '第二条');
              },
              child: const Text('触发'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pump();
    expect(find.text('第一条'), findsNothing, reason: '被第二条顶替移除');
    expect(find.text('第二条'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3400));
    expect(find.text('第二条'), findsNothing);
  });

  testWidgets('toast 无下划线且宽度由内容决定并限制在 520', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showHikoToast(context, '这是一段较长的提示文字，用于验证 Toast 不会横跨整个窗口'),
              child: const Text('触发'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pump();
    final text = tester.widget<Text>(find.textContaining('这是一段较长'));
    expect(text.style?.decoration, TextDecoration.none);
    final banner = tester.renderObject<RenderBox>(
      find.byType(ConstrainedBox).last,
    );
    expect(banner.size.width, lessThanOrEqualTo(520));
    expect(banner.size.width, lessThan(800));
    await tester.pump(const Duration(milliseconds: 3400));
  });
}
