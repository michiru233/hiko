import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/screens/home_screen.dart';

/// 1.41 快捷键焦点守卫：输入框有焦点时空格/方向键不触发播放快捷键。
/// 与 home_screen 相同的接线方式（Shortcuts→Actions→守卫），
/// 守卫函数直接引用被测实现 isFocusInsideEditable。
void main() {
  testWidgets('搜索框聚焦时按 Space 走打字不触发播放；失焦后触发', (tester) async {
    var toggled = 0;
    final canvasNode = FocusNode(debugLabel: 'canvas');
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space): _Toggle(),
          },
          child: Actions(
            actions: {
              _Toggle: CallbackAction<_Toggle>(
                onInvoke: (_) {
                  if (isFocusInsideEditable(
                      FocusManager.instance.primaryFocus?.context)) {
                    return null;
                  }
                  toggled++;
                  return null;
                },
              ),
            },
            child: Scaffold(
              body: ListView(
                children: [
                  const TextField(key: Key('search')),
                  Focus(focusNode: canvasNode, child: const SizedBox(height: 10)),
                  Text('toggled=$toggled', key: const Key('label')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 聚焦搜索框后按 Space：守卫生效，动作不触发
    await tester.tap(find.byKey(const Key('search')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(isFocusInsideEditable(FocusManager.instance.primaryFocus?.context),
        isTrue);
    expect(toggled, 0);

    // 焦点移到非输入节点（画布）后按 Space：动作触发（播放/暂停）
    canvasNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(toggled, 1);
  });

  testWidgets('焦点不在任何输入框内时守卫返回 false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              expect(isFocusInsideEditable(context), isFalse);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });
}

class _Toggle extends Intent {
  const _Toggle();
}
