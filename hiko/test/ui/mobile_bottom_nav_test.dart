import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/widgets/mobile_bottom_nav.dart';

/// 移动端底部导航的固定两格（1.99.6，裁决 Q6=A / Q7=A / Q11=A）。
///
/// 1.99.6 把 `home_screen.dart` 里的私有 `_MobileBottomNav` 抽成公开组件，
/// 就是为了能在这里锁住三件事：
/// 1. 「正在播放」「设置」是**固定格**，不占 `navViews` 表、用户关不掉；
/// 2. 没有正在播放的专辑时「正在播放」**置灰不可点，但格子留在原位**；
/// 3. 放不放得下的估算要算上**两个**固定格（1.99.4 只算了「设置」一个）。
void main() {
  Future<void> pumpNav(
    WidgetTester tester, {
    List<String>? views,
    int currentIndex = 0,
    bool playerEnabled = false,
    VoidCallback? onOpenPlayer,
    VoidCallback? onOpenSettings,
    void Function(int)? onTapView,
    double width = 800,
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: MobileBottomNav(
            views: views ?? AppSettings.navViewsAll,
            currentIndex: currentIndex,
            onTapView: onTapView ?? (_) {},
            onOpenPlayer: onOpenPlayer ?? () {},
            onOpenSettings: onOpenSettings ?? () {},
            playerEnabled: playerEnabled,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('「正在播放」「设置」恒在列，且固定在最后两格（顺序：正在播放、设置）', (tester) async {
    // 只显示一个一级视图：固定格照样在
    await pumpNav(tester, views: const ['本地音声']);

    for (final label in const [
      MobileBottomNav.playerLabel,
      MobileBottomNav.settingsLabel,
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label 必须是固定格');
    }

    final homeX = tester.getTopLeft(find.text('本地音声')).dx;
    final playerX = tester.getTopLeft(find.text(MobileBottomNav.playerLabel)).dx;
    final settingsX =
        tester.getTopLeft(find.text(MobileBottomNav.settingsLabel)).dx;
    expect(homeX, lessThan(playerX));
    expect(playerX, lessThan(settingsX), reason: '「正在播放」在「设置」左侧');
  });

  testWidgets('全量 7 项 + 2 固定格 = 9 格，标签齐全不重不漏', (tester) async {
    await pumpNav(tester);
    expect(AppSettings.navViewsAll.length, 7, reason: '1.99.6 起「正在播放」已移出导航表');
    for (final view in AppSettings.navViewsAll) {
      expect(find.text(view), findsOneWidget);
    }
    expect(find.text(MobileBottomNav.playerLabel), findsOneWidget);
    expect(find.text(MobileBottomNav.settingsLabel), findsOneWidget);
  });

  testWidgets('没有正在播放的专辑：该格置灰不可点，但格子留在原位', (tester) async {
    var playerTaps = 0;
    await pumpNav(
      tester,
      playerEnabled: false,
      onOpenPlayer: () => playerTaps++,
    );

    final theme = Theme.of(tester.element(find.byType(MobileBottomNav)));
    final icon = tester.widget<Icon>(find.byIcon(MobileBottomNav.playerIcon));
    expect(icon.color, theme.disabledColor, reason: '置灰（裁决 Q7=A）');

    await tester.tap(find.text(MobileBottomNav.playerLabel));
    await tester.pump();
    expect(playerTaps, 0, reason: '置灰时不可点');

    // 格子仍在、位置不跳（连同「设置」一起占位）
    final settingsLeft =
        tester.getTopLeft(find.text(MobileBottomNav.settingsLabel)).dx;
    await pumpNav(
      tester,
      playerEnabled: true,
      onOpenPlayer: () => playerTaps++,
    );
    expect(
      tester.getTopLeft(find.text(MobileBottomNav.settingsLabel)).dx,
      settingsLeft,
      reason: '可点/置灰不该让固定格位移',
    );
  });

  testWidgets('有正在播放的专辑：该格可点并回调 onOpenPlayer', (tester) async {
    var playerTaps = 0;
    var settingsTaps = 0;
    await pumpNav(
      tester,
      playerEnabled: true,
      onOpenPlayer: () => playerTaps++,
      onOpenSettings: () => settingsTaps++,
    );

    final theme = Theme.of(tester.element(find.byType(MobileBottomNav)));
    expect(
      tester.widget<Icon>(find.byIcon(MobileBottomNav.playerIcon)).color,
      theme.hintColor,
      reason: '可点时不置灰（且不参与高亮：它不是一个视图）',
    );

    await tester.tap(find.text(MobileBottomNav.playerLabel));
    await tester.pump();
    expect(playerTaps, 1);

    await tester.tap(find.text(MobileBottomNav.settingsLabel));
    await tester.pump();
    expect(settingsTaps, 1);
  });

  testWidgets('点一级视图回传它在 views 里的下标（固定格不占下标）', (tester) async {
    final taps = <int>[];
    await pumpNav(
      tester,
      views: const ['本地音声', '统计', '在线'],
      onTapView: taps.add,
    );
    await tester.tap(find.text('统计'));
    await tester.pump();
    expect(taps, [1]);
    // 「设置」走的是自己的回调，不落到 onTapView
    await tester.tap(find.text(MobileBottomNav.settingsLabel));
    await tester.pump();
    expect(taps, [1]);
  });

  testWidgets('放不放得下要算上两个固定格（+2，不是 +1）', (tester) async {
    // 7 项 + 2 固定 = 9 格 × 76 = 684px
    //  620px：684 > 620 → 整行横向滑动（旧代码按 +1 算 608 ≤ 620，会误判为放得下）
    //  700px：684 ≤ 700 → 均分，不出现滑动容器
    await pumpNav(tester, width: 620);
    expect(
      find.byType(SingleChildScrollView),
      findsOneWidget,
      reason: '9 格 × 76 = 684 > 620，必须可横向滑动（+2 的估算）',
    );

    await pumpNav(tester, width: 700);
    expect(
      find.byType(SingleChildScrollView),
      findsNothing,
      reason: '684 ≤ 700，放得下就均分，别多包一层滚动',
    );
  });
}
