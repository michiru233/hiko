import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/global_shortcuts.dart';
import 'package:hiko/ui/screens/online_screen.dart';

/// 1.99.13：Cmd/Ctrl+F 全局快捷键聚焦在线页搜索框。
/// 搜索框 FocusNode 挂在 app 级 [onlineSearchFocusProvider] 上，
/// 快捷键侧靠 `node.context != null` 判断在线页是否在场。
void main() {
  testWidgets('Cmd+F（meta 组合）聚焦在线页搜索框', (tester) async {
    late FocusNode searchNode;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (_, child) => HikoGlobalShortcuts(
            navigatorKey: GlobalKey<NavigatorState>(),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) {
              searchNode = ref.watch(onlineSearchFocusProvider);
              return Scaffold(
                body: TextField(
                  focusNode: searchNode,
                  key: const Key('online-search'),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(searchNode.hasFocus, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(searchNode.hasFocus, isTrue);
  });

  testWidgets('节点不在树中（在线页未挂载）时 Cmd+F 安全 no-op', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (_, child) => HikoGlobalShortcuts(
            navigatorKey: GlobalKey<NavigatorState>(),
            child: child!,
          ),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    // 不抛异常即通过（requestFocus 前有 context != null 守卫）
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  });
}
