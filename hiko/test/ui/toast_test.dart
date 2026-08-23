import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/widgets/toast.dart';

/// 1.32 全局 toast 验收：对话框打开时触发 toast，提示必须可见且置顶（根 Overlay）。
void main() {
  testWidgets('对话框打开时 toast 浮于对话框之上', (tester) async {
    await tester.pumpWidget(MaterialApp(
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
    ));

    await tester.tap(find.text('打开对话框'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget, reason: '对话框已打开');

    // 对话框打开状态下触发 toast：旧 ScaffoldMessenger 实现会被对话框盖住
    await tester.tap(find.text('触发提示'));
    await tester.pump();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('置顶提示文案'), findsOneWidget,
        reason: 'toast 走根 Overlay，必须浮于对话框之上且可见');

    // 自动消失
    await tester.pump(const Duration(milliseconds: 3400));
    expect(find.text('置顶提示文案'), findsNothing);
  });

  testWidgets('新 toast 顶替旧 toast（同一时刻只有一条）', (tester) async {
    await tester.pumpWidget(MaterialApp(
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
    ));

    await tester.tap(find.text('触发'));
    await tester.pump();
    expect(find.text('第一条'), findsNothing, reason: '被第二条顶替移除');
    expect(find.text('第二条'), findsOneWidget);

    // 等 toast 自动消失（不留 pending timer）
    await tester.pump(const Duration(milliseconds: 3400));
    expect(find.text('第二条'), findsNothing);
  });
}
