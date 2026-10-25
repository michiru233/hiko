import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

void main() {
  testWidgets('small：preferredSize = 64 + 状态栏 inset', (tester) async {
    const bar = M3EAppBar.small(title: Text('标题'), topInset: 24);
    expect(bar.preferredSize, const Size.fromHeight(88));
    await tester.pumpWidget(
      wrapM3E(Column(mainAxisSize: MainAxisSize.min, children: <Widget>[bar])),
    );
    expect(tester.getSize(find.byType(M3EAppBar)), const Size(800, 88));
  });

  testWidgets('large：152 高', (tester) async {
    const bar = M3EAppBar.large(title: Text('大标题'));
    expect(bar.preferredSize, const Size.fromHeight(152));
  });

  testWidgets('透明覆盖底色不画 scrolled 投影', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const M3EAppBar.small(
          title: Text('播放'),
          scrolled: true,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(M3EAppBar),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.boxShadow, isNull);
  });

  testWidgets('leading + actions 同时存在', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        M3EAppBar.small(
          title: const Text('设置'),
          leading: M3EIconButton(
            icon: Icons.arrow_back,
            tooltip: '返回',
            onPressed: () {},
          ),
          actions: <Widget>[
            M3EIconButton(icon: Icons.close, tooltip: '关闭', onPressed: () {}),
          ],
        ),
      ),
    );
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
