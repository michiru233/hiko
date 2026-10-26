import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// `M3EMenu` 的规格与行为锁（1.99.40）。
///
/// 要锁两件事：
/// 1. **面板/行规格**：`surfaceContainerHigh`、圆角 4、海拔 3、行高 48、
///    `labelLarge`。这五项是「三套菜单合一」的判据，掉任何一个就又回到
///    「自绘近似 M3E」。
/// 2. **两类行的关闭语义**：动作行点完就关；开关行点完**不关**（分级筛选、
///    防社死、外观切换都靠这个手感）。
void main() {
  Future<M3EThemeData> pumpMenu(
    WidgetTester tester, {
    required List<Widget> children,
    Size size = const Size(900, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final data = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        theme: data,
        M3EMenu(
          builder: (context, controller, child) => M3EChip(
            label: '打开',
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
          children: children,
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    return data;
  }

  testWidgets('面板：surfaceContainerHigh / 圆角 4 / 海拔 3 / 去 tint', (tester) async {
    final data = await pumpMenu(
      tester,
      children: <Widget>[M3EMenuAction(label: '重命名', onPressed: () {})],
    );

    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    final style = anchor.style!;
    const states = <WidgetState>{};

    expect(
      style.backgroundColor!.resolve(states),
      data.colors.surfaceContainerHigh,
    );
    expect(style.surfaceTintColor!.resolve(states), Colors.transparent);
    expect(style.elevation!.resolve(states), M3EElevation.level3);

    final shape = style.shape!.resolve(states)! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(M3EShape.xs));
  });

  testWidgets('行高 48、labelLarge（14sp）、左右 12dp', (tester) async {
    await pumpMenu(
      tester,
      children: <Widget>[M3EMenuAction(label: '重命名', onPressed: () {})],
    );

    final row = find.byType(M3EMenuAction);
    expect(tester.getSize(row).height, 48);

    final text = tester.widget<Text>(find.text('重命名'));
    expect(text.style!.fontSize, 14);
    expect(
      text.style!.fontWeight,
      m3eTypeSpecs[M3ETypeRole.labelLarge]!.weight,
    );

    // 文字左缘到行左缘 = 12dp 内边距
    expect(
      tester.getTopLeft(find.text('重命名')).dx - tester.getTopLeft(row).dx,
      12,
    );
  });

  testWidgets('动作行：点一下回调一次，菜单关闭', (tester) async {
    var taps = 0;
    await pumpMenu(
      tester,
      children: <Widget>[M3EMenuAction(label: '重命名', onPressed: () => taps++)],
    );

    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(find.text('重命名'), findsNothing, reason: '动作行点完要关菜单');
  });

  testWidgets('选中项：右侧勾；不给整行底色（裁决 ③=A）', (tester) async {
    await pumpMenu(
      tester,
      children: <Widget>[
        M3EMenuAction(label: '销量倒序', selected: true, onPressed: () {}),
        M3EMenuAction(label: '最新发布', onPressed: () {}),
      ],
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(M3EMenuAction).first,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('destructive 行用 error 色；禁用行灰且不回调', (tester) async {
    final data = await pumpMenu(
      tester,
      children: <Widget>[
        M3EMenuAction(label: '删除歌单', destructive: true, onPressed: () {}),
        M3EMenuAction(label: '不可用', enabled: false, onPressed: () {}),
      ],
    );

    final danger = tester.widget<Text>(find.text('删除歌单'));
    expect(danger.style!.color, data.colors.error);

    final disabled = tester.widget<Text>(find.text('不可用'));
    expect(disabled.style!.color!.a, closeTo(0.38, 0.01));

    await tester.tap(find.text('不可用'));
    await tester.pumpAndSettle();
    expect(find.text('不可用'), findsOneWidget, reason: '禁用的行不该关菜单');
  });

  testWidgets('开关行：回调一次、勾出现、菜单不关（裁决 ②=A）', (tester) async {
    final changes = <bool>[];
    var value = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      wrapM3E(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return M3EMenu(
              builder: (context, controller, child) => M3EChip(
                label: '打开',
                onTap: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              children: <Widget>[
                M3EMenuToggle(
                  label: 'R18',
                  value: value,
                  onChanged: (next) {
                    changes.add(next);
                    setState(() => value = next);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget, reason: '开=有勾');
    await tester.tap(find.text('R18'));
    await tester.pumpAndSettle();

    expect(changes, <bool>[false]);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('R18'), findsOneWidget, reason: '开关行点完菜单必须还开着');
    setHostState(() {});
  });

  testWidgets('开关行：外部 value 变化后 didUpdateWidget 同步勾', (tester) async {
    final external = ValueNotifier<bool>(false);
    addTearDown(external.dispose);

    await tester.pumpWidget(
      wrapM3E(
        M3EMenu(
          builder: (context, controller, child) => M3EChip(
            label: '打开',
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
          children: <Widget>[
            ValueListenableBuilder<bool>(
              valueListenable: external,
              builder: (context, value, _) => M3EMenuToggle(
                label: '防社死',
                value: value,
                statusLabel: value ? '已开启' : '已关闭',
                onChanged: (next) => external.value = next,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('已关闭'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    // 外部（快捷键 / 另一个入口）改了状态：菜单开着也要立刻刷新
    external.value = true;
    await tester.pumpAndSettle();

    expect(find.text('已开启'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('防社死'), findsOneWidget, reason: '菜单没被重建掉');
  });

  testWidgets('标题 / 分隔线 / 自定义行：都在场且不参与关闭', (tester) async {
    await pumpMenu(
      tester,
      children: <Widget>[
        const M3EMenuHeader(label: '播放模式'),
        const M3EMenuDivider(),
        const M3EMenuCustom(
          semanticLabel: '音量',
          child: SizedBox(height: 24, child: Text('自定义内容')),
        ),
      ],
    );

    expect(find.text('播放模式'), findsOneWidget);
    expect(find.text('自定义内容'), findsOneWidget);
    expect(tester.getSize(find.byType(M3EMenuCustom)).height, 48);

    final header = tester.widget<Text>(find.text('播放模式'));
    expect(header.style!.fontSize, 12);

    await tester.tap(find.text('自定义内容'));
    await tester.pumpAndSettle();
    expect(find.text('播放模式'), findsOneWidget, reason: '自定义行没有 onTap 不该关');
  });

  testWidgets('高度封顶：min(400, 屏高×0.45) 且内容可滚', (tester) async {
    // 屏高 600 → 45% = 270，11 行 × 48 = 528 必须滚起来
    await pumpMenu(
      tester,
      size: const Size(900, 600),
      children: <Widget>[
        for (var i = 0; i < 11; i++)
          M3EMenuAction(label: '项目 $i', onPressed: () {}),
      ],
    );

    final scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget);
    expect(tester.getSize(scroll).height, lessThanOrEqualTo(270));
    expect(tester.getSize(scroll).height, greaterThan(200));

    expect(find.text('项目 0'), findsOneWidget);
    await tester.drag(scroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('项目 10'), findsOneWidget);
  });
}
