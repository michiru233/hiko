import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.100.0 全屏播放页双样式回归锁：黑胶（默认）/ 简约方封面。
///
/// AppBar 切换按钮显示「要切去的那套」（黑胶页 → 方框图标，简约页 → 唱片图标），
/// 选择落盘到 `fullscreenPlayerStyle`。两套视图只有中央封面区形态不同，
/// 交互语义必须一致：简约封面点按同样进歌词层（与黑胶同语义）。
void main() {
  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester, {
    String style = 'vinyl',
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (style != 'vinyl') {
      container.read(settingsProvider.notifier).state =
          AppSettings(fullscreenPlayerStyle: style);
    }
    container.read(playbackProvider.notifier).state =
        playingAt(lyricsAlbum(), 0.5);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FullscreenPlayerScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('默认样式是黑胶：无方角封面，按钮指向简约', (tester) async {
    await pumpPlayer(tester);
    expect(find.byTooltip('切换为简约样式'), findsOneWidget);
    expect(find.byType(ClipOval), findsOneWidget, reason: '黑胶圆封面');
    expect(find.byType(ClipRRect), findsNothing, reason: '不该出现方角封面');
  });

  testWidgets('简约样式：方角封面静态展示，按钮指向黑胶', (tester) async {
    await pumpPlayer(tester, style: 'simple');
    expect(find.byTooltip('切换为黑胶样式'), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget, reason: '简约方角封面');
    expect(find.byType(ClipOval), findsNothing, reason: '不该出现黑胶圆盘');
  });

  testWidgets('AppBar 切换按钮：点击翻转样式并更新指向', (tester) async {
    final container = await pumpPlayer(tester);
    expect(container.read(settingsProvider).fullscreenPlayerStyle, 'vinyl');

    await tester.tap(find.byTooltip('切换为简约样式'));
    await tester.pump();
    expect(container.read(settingsProvider).fullscreenPlayerStyle, 'simple');
    expect(find.byTooltip('切换为黑胶样式'), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);

    await tester.tap(find.byTooltip('切换为黑胶样式'));
    await tester.pump();
    expect(container.read(settingsProvider).fullscreenPlayerStyle, 'vinyl');
    expect(find.byType(ClipOval), findsOneWidget);
  });

  testWidgets('简约封面点按进歌词层（与黑胶同语义）', (tester) async {
    await pumpPlayer(tester, style: 'simple');
    final area = tester.getRect(find.byType(AnimatedSwitcher));
    // 取距顶 40px 处：在中央区内、封面之外，只有铺满整片的切换手势收得到
    await tester.tapAt(Offset(area.center.dx, area.top + 40));
    // 交叉淡入 220ms 推完
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('显示封面'), findsOneWidget,
        reason: '进入歌词层后 AppBar 图标变为「显示封面」');
  });
}
