import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/online_search_overlay.dart';

import 'm3e/m3e_test_harness.dart';

/// 「点开 → 放大 → 输入 → 提交」浮层的行为锁（1.99.70）。
void main() {
  late TextEditingController controller;
  late FocusNode node;

  setUp(() {
    controller = TextEditingController();
    node = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    node.dispose();
  });

  Widget host({
    List<String> history = const <String>[],
    M3EThemeData? theme,
    ValueChanged<String>? onSubmit,
    Future<void> Function()? onClearHistory,
  }) => wrapM3E(
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showOnlineSearchOverlay(
          context,
          controller: controller,
          focusNode: node,
          history: history,
          onSubmit: onSubmit ?? (_) {},
          onClearHistory: onClearHistory ?? () async {},
        ),
        child: const Text('open'),
      ),
    ),
    theme: theme,
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('打开后输入框在场、自动聚焦', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    expect(find.byType(OnlineSearchOverlay), findsOneWidget);
    expect(find.byKey(const ValueKey('online-search-field')), findsOneWidget);
    expect(node.hasFocus, isTrue, reason: '打开就该能直接打字');
  });

  testWidgets('面板贴顶部而不是垂直居中', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    final dy = tester
        .getTopLeft(find.byKey(const ValueKey('online-search-field')))
        .dy;
    expect(dy, lessThan(200), reason: '顶部居中：输入框应贴近窗口上方');
  });

  testWidgets('输入 + 搜索键：回调 trim 后的词并自动收起', (tester) async {
    final submits = <String>[];
    await tester.pumpWidget(host(onSubmit: submits.add));
    await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('online-search-field')),
      '  アリス  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(submits, <String>['アリス']);
    expect(find.byType(OnlineSearchOverlay), findsNothing);
  });

  testWidgets('空词回车：只关闭、不回调', (tester) async {
    final submits = <String>[];
    await tester.pumpWidget(host(onSubmit: submits.add));
    await open(tester);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(submits, isEmpty);
    expect(find.byType(OnlineSearchOverlay), findsNothing);
  });

  testWidgets('点历史：回填 + 提交 + 收起', (tester) async {
    final submits = <String>[];
    await tester.pumpWidget(
      host(history: const <String>['大山チロル', '柚木つばめ'], onSubmit: submits.add),
    );
    await open(tester);

    await tester.tap(find.text('大山チロル'));
    await tester.pumpAndSettle();

    expect(controller.text, '大山チロル');
    expect(submits, <String>['大山チロル']);
    expect(find.byType(OnlineSearchOverlay), findsNothing);
  });

  testWidgets('✕ 只清输入：面板不关、不提交', (tester) async {
    final submits = <String>[];
    await tester.pumpWidget(host(onSubmit: submits.add));
    await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('online-search-field')),
      'アリス',
    );
    await tester.pump(); // 让 ValueListenableBuilder 把 ✕ 画出来
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(submits, isEmpty);
    expect(find.byType(OnlineSearchOverlay), findsOneWidget);

    // 收尾：面板开着时销毁 FocusNode 会撞到已 dispose 的 FocusManager
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('点遮罩：关闭但草稿保留', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('online-search-field')),
      '下書き',
    );
    await tester.pump();
    // 面板在顶部，点屏幕底部一点必然落在遮罩上
    await tester.tapAt(const Offset(10, 560));
    await tester.pumpAndSettle();

    expect(find.byType(OnlineSearchOverlay), findsNothing);
    expect(controller.text, '下書き');
  });

  testWidgets('取消按钮关闭', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineSearchOverlay), findsNothing);
  });

  testWidgets('动效关闭时也能正常开关', (tester) async {
    await tester.pumpWidget(
      host(theme: testTheme(motionLevel: M3EMotionLevel.off)),
    );
    await open(tester);
    expect(find.byType(OnlineSearchOverlay), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineSearchOverlay), findsNothing);
  });

  testWidgets('清空历史：列表消失、面板仍在', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(
      host(
        history: const <String>['大山チロル'],
        onClearHistory: () async => cleared++,
      ),
    );
    await open(tester);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(cleared, 1);
    expect(find.text('大山チロル'), findsNothing);
    expect(find.byType(OnlineSearchOverlay), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('打开时已有草稿会被全选', (tester) async {
    controller.text = '大山チロル';
    await tester.pumpWidget(host());
    await open(tester);

    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });
}
