import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';

import 'lyrics_fixture.dart';

/// 1.99.29 黑胶退场锁（裁决 D7，plan §8.5）：
/// 播放页只剩一种封面形态 —— 320dp 角 28 的大封面（播放态 28↔32 形变）。
/// 旧 `fullscreenPlayerStyle` 字段仍在设置里，但**不再影响任何 UI**：
/// 这条锁防的是「黑胶/样式切换」从任何入口回流。
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
    container.read(playbackProvider.notifier).state = playingAt(
      lyricsAlbum(),
      0.5,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FullscreenPlayerScreen(heroTag: style)),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('无样式切换按钮（黑胶/简约二选一的入口已删）', (tester) async {
    await pumpPlayer(tester);
    expect(find.byTooltip('切换为简约样式'), findsNothing);
    expect(find.byTooltip('切换为黑胶样式'), findsNothing);
  });

  testWidgets('封面是圆角方形（角 28），无黑胶圆盘', (tester) async {
    await pumpPlayer(tester);
    expect(find.byType(ClipRRect), findsWidgets, reason: 'M3E 大封面');
    expect(find.byType(ClipOval), findsNothing, reason: '黑胶圆盘不得回流');
  });

  testWidgets('旧样式字段值不影响渲染（vinyl 值也不再出圆盘）', (tester) async {
    await pumpPlayer(tester, style: 'vinyl');
    expect(find.byType(ClipOval), findsNothing);
    expect(find.byType(ClipRRect), findsWidgets);
  });

  testWidgets('封面点按进歌词层（交互语义不变）', (tester) async {
    await pumpPlayer(tester);
    final area = tester.getRect(
      find.byKey(const ValueKey('player-central-switcher')),
    );
    // 取距顶 40px 处：在中央区内、封面之外，只有铺满整片的切换手势收得到
    await tester.tapAt(Offset(area.center.dx, area.top + 40));
    // 交叉淡入 220ms 推完
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byTooltip('显示封面'),
      findsOneWidget,
      reason: '进入歌词层后 AppBar 图标变为「显示封面」',
    );
  });

  testWidgets('音量菜单：M3EMenu + M3ESlider（不再嵌 Material Slider 样式）', (
    tester,
  ) async {
    await pumpPlayer(tester);

    // 默认音量 1.0 → 图标是 volume_up
    await tester.tap(find.byTooltip(RegExp(r'^音量')));
    await tester.pumpAndSettle();

    // key 挂在 M3ESlider 上（拖动/回归测试的锚点）
    final slider = tester.widget<M3ESlider>(
      find.byKey(const ValueKey('volume-slider')),
    );
    expect(slider.value, isNotNull);
    // 播放页现在有三处 M3EMenu：音量 / 播放模式 / 桌面歌词
    expect(find.byType(M3EMenu), findsWidgets);
  });
}
