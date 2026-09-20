import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/transitions/fullscreen_player_route.dart';

const _homeKey = Key('home');
const _pageKey = Key('page');

Widget _pushedPage() =>
    const Scaffold(body: Center(child: Text('PAGE', key: _pageKey)));

void main() {
  test('路由时长与标识：进 250ms / 退 200ms，带可识别的路由名', () {
    final route = FullscreenPlayerRoute<void>();
    expect(route.transitionDuration, const Duration(milliseconds: 250));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 200));
    expect(route.settings.name, fullscreenPlayerRouteName);
    // 关闭必须比打开快（transitions.dev open/close 不对称）
    expect(route.reverseTransitionDuration, lessThan(route.transitionDuration));
  });

  testWidgets('推入时：被覆盖页在前 150ms 内退场（淡出 + 微缩 + 模糊）',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildHikoTheme(const AppSettings()),
      navigatorKey: navKey,
      home: const Scaffold(body: Center(child: Text('HOME', key: _homeKey))),
    ));

    unawaited(navKey.currentState!.push<void>(
      MaterialPageRoute<void>(builder: (_) => _pushedPage()),
    ));
    await tester.pump();
    // 250ms 转场的 75ms 处：二次动画进度 0.3，前载曲线（150/250）后为 0.5
    await tester.pump(const Duration(milliseconds: 75));

    final homeOpacity = tester.widget<Opacity>(
      find.ancestor(of: find.byKey(_homeKey), matching: find.byType(Opacity)),
    );
    expect(homeOpacity.opacity, inInclusiveRange(0.1, 0.9));

    // 退场模糊只在仍可见时挂载——这是最贵的一项，不能常态挂着
    expect(
      find.ancestor(
        of: find.byKey(_homeKey),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
    // 入场页此时已部分升起淡入
    final pageOpacity = tester.widget<Opacity>(
      find.ancestor(of: find.byKey(_pageKey), matching: find.byType(Opacity)),
    );
    expect(pageOpacity.opacity, greaterThan(0.0));
    expect(pageOpacity.opacity, lessThan(1.0));
  });

  testWidgets('静息态零开销：转场结束后不残留模糊与半透明图层', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildHikoTheme(const AppSettings()),
      navigatorKey: navKey,
      home: const Scaffold(body: Center(child: Text('HOME', key: _homeKey))),
    ));

    unawaited(navKey.currentState!.push<void>(
      MaterialPageRoute<void>(builder: (_) => _pushedPage()),
    ));
    await tester.pumpAndSettle();

    // 转场器挂在全局主题上、每个路由都在，静息态绝不能留全屏高斯模糊
    expect(find.byType(ImageFiltered), findsNothing);
    // 入场页到位后也不再挂透明度图层
    expect(
      find.ancestor(of: find.byKey(_pageKey), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('系统「减弱动态效果」开启时不做转场', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: buildHikoTheme(const AppSettings()),
          navigatorKey: navKey,
          home: const Scaffold(
            body: Center(child: Text('HOME', key: _homeKey)),
          ),
        ),
      ),
    );

    unawaited(navKey.currentState!.push<void>(
      MaterialPageRoute<void>(builder: (_) => _pushedPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));

    // 直接交还子树：推入页上不应有任何透明度图层
    expect(
      find.ancestor(of: find.byKey(_pageKey), matching: find.byType(Opacity)),
      findsNothing,
    );
  });
}
