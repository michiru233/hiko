import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// `M3EDialog` 的规格锁（1.99.42）。
///
/// 21 处 `AlertDialog` 收口到这一个组件，所以壳的五个值（底色 / 圆角 /
/// 海拔 / 去 tint / 标题字阶）只在这里断言一次；调用点不再各自写圆角
/// （`category_dialog` 曾把 28 覆写成 14）。
void main() {
  final panel = find
      .descendant(of: find.byType(Dialog), matching: find.byType(Material))
      .first;

  Future<void> openDialog(
    WidgetTester tester,
    Widget dialog, {
    Size size = const Size(900, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrapM3E(
        Builder(
          builder: (context) => M3EButton(
            label: '打开',
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('面板：surfaceContainerHigh / 圆角 28 / 海拔 3 / 去 tint', (
    tester,
  ) async {
    final data = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        theme: data,
        Builder(
          builder: (context) => M3EButton(
            label: '打开',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => M3EDialog(
                title: '删除专辑',
                content: const Text('删除后不可恢复'),
                actions: <Widget>[
                  M3EButton(label: '取消', variant: M3EButtonVariant.text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, data.colors.surfaceContainerHigh);
    expect(dialog.surfaceTintColor, Colors.transparent);
    expect(dialog.elevation, M3EElevation.level3);
    final shape = dialog.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(M3EShape.xl));
  });

  testWidgets('标题 headlineSmall 24；正文与按钮都在', (tester) async {
    await openDialog(
      tester,
      M3EDialog(
        title: '设置星级',
        content: const Text('正文'),
        actions: <Widget>[
          M3EButton(label: '取消', variant: M3EButtonVariant.text),
          M3EButton(label: '保存'),
        ],
      ),
    );

    final title = tester.widget<Text>(find.text('设置星级'));
    expect(title.style!.fontSize, 24);
    expect(find.text('正文'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(M3EButton),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('无 actions 时不画按钮区；有 actions 右对齐', (tester) async {
    await openDialog(
      tester,
      const M3EDialog(title: '只有标题和正文', content: Text('正文')),
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(M3EButton),
      ),
      findsNothing,
    );

    await tester.tapAt(const Offset(4, 4)); // 点遮罩关闭
    await tester.pumpAndSettle();

    await openDialog(
      tester,
      M3EDialog(
        title: '两个按钮',
        actions: <Widget>[
          M3EButton(label: '取消', variant: M3EButtonVariant.text),
          M3EButton(label: '确定'),
        ],
      ),
    );
    final inDialog = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(M3EButton),
    );
    final cancel = tester.getRect(inDialog.first);
    final confirm = tester.getRect(inDialog.last);
    expect(cancel.left, lessThan(confirm.left), reason: '按钮按传入顺序从左到右');
    final panelRect = tester.getRect(panel);
    expect(confirm.right, lessThanOrEqualTo(panelRect.right - 16));
  });

  testWidgets('长正文：限高后可滚动，不溢出', (tester) async {
    await openDialog(
      tester,
      M3EDialog(
        title: '很长的内容',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[for (var i = 0; i < 60; i++) Text('第 $i 行')],
        ),
        actions: <Widget>[
          M3EButton(label: '关闭', variant: M3EButtonVariant.text),
        ],
      ),
      size: const Size(900, 700),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // `Dialog` 自身的矩形是整屏（它只是 inset 的 Padding），面板是里面的 Material
    expect(tester.getSize(panel).height, lessThanOrEqualTo(700 - 48));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 59 行'), findsOneWidget);
  });

  testWidgets('危险按钮：error 底 + onError 文字', (tester) async {
    final data = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        theme: data,
        M3EButton(
          label: '删除',
          variant: M3EButtonVariant.destructive,
          onPressed: () {},
        ),
      ),
    );

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(M3EButton),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, data.colors.error);

    final text = tester.widget<Text>(find.text('删除'));
    expect(text.style!.color, data.colors.onError);
  });

  testWidgets('360dp × 1.3 字号：标题与按钮不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: wrapM3E(
          Builder(
            builder: (context) => M3EButton(
              label: '打开',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => M3EDialog(
                  title: '批量设置分类（12 张专辑）',
                  content: const Text('这条正文在 1.3 倍字号下要能换行而不是把对话框撑破。'),
                  actions: <Widget>[
                    M3EButton(label: '取消', variant: M3EButtonVariant.text),
                    M3EButton(
                      label: '删除歌单',
                      variant: M3EButtonVariant.destructive,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(panel);
    expect(rect.width, lessThanOrEqualTo(360));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
  });
}
