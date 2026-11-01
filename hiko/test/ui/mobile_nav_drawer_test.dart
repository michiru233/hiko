import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';
import 'package:hiko/ui/screens/home_screen.dart';
import 'package:hiko/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 移动端导航从底部五宫格搬到左抽屉（1.99.65）在**主界面**层的接线。
///
/// widget 测试的宿主是 macOS，`Platform.isAndroid` 恒 false，移动布局靠
/// `HomeScreen(debugMobileLayout: true)` 这个测试缝打开（与 1.99.6 的播放栏测试同款）。
///
/// 锁五件事：
/// 1. 底部导航整条消失（`M3ENavBar` findsNothing）；
/// 2. **左半屏任意位置**往右拖都能拉出抽屉（1.99.67：不再只认 24dp 边缘）；
/// 3. 抽屉**跟手**：拖到一半时面板就露在手指位置，松手按进度/速度吸附；
/// 4. 抽屉里的条目与旧底栏是同一份（本地音声 / 在线 / 下载 / 设置）；
/// 5. 没有播放时「正在播放」是禁用态，点它不跳全屏播放页。
class _SilentPlayback extends PlaybackController {
  _SilentPlayback(super._ref);
}

class _EmptyLibrary extends LibraryNotifier {
  _EmptyLibrary() : super(LibraryStore());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _EmptyLibrary()),
        playbackProvider.overrideWith((ref) => _SilentPlayback(ref)),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: HomeScreen(debugMobileLayout: true),
        ),
      ),
    );
    // initState 里 500ms 的静默扫描要先走完（空目录即返，无 IO）
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// 从左缘起手往右拖，把抽屉拉出来。
  Future<void> openDrawer(WidgetTester tester) async {
    await tester.dragFrom(const Offset(2, 700), const Offset(320, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('底部导航已撤，左半屏右滑拉出抽屉', (tester) async {
    await pumpHome(tester);

    expect(find.byType(M3ENavBar), findsNothing, reason: '1.99.65 起移动端不再有底部导航');
    expect(find.text('更多'), findsNothing, reason: '抽屉日常隐藏');

    await openDrawer(tester);

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('本地音声'), findsWidgets);
    // 1.99.66：不再折叠 —— 「在线」「下载」「设置」都直接躺在抽屉里
    expect(find.text('在线'), findsWidgets);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('更多'), findsNothing, reason: '「更多」面板已并入抽屉');
    expect(find.textContaining('左半屏右滑'), findsOneWidget);
  });

  testWidgets('点「设置」→ 抽屉收起并打开设置页', (tester) async {
    await pumpHome(tester);
    await openDrawer(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing, reason: '选完条目抽屉要收起');
    expect(find.byType(SettingsPage), findsOneWidget, reason: '设置页被推进来');
  });

  testWidgets('没有播放时「正在播放」禁用，点了不进全屏播放页', (tester) async {
    await pumpHome(tester);
    await openDrawer(tester);

    await tester.tap(find.text('正在播放'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(FullscreenPlayerScreen), findsNothing);
    // 禁用的条目不该收起抽屉（没发生过任何导航）
    expect(find.byType(Drawer), findsOneWidget);
  });

  testWidgets('左半屏中间起手也能拉出抽屉（不再只认边缘）', (tester) async {
    await pumpHome(tester);
    // 450dp 起手仍然落在左半屏（900 宽 → 分界在 450）
    await tester.dragFrom(const Offset(320, 500), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget, reason: '左半屏任意位置都能起手');
  });

  testWidgets('拖到一半就跟着手指走；不超过 40% 松手会弹回去', (tester) async {
    await pumpHome(tester);
    final gesture = await tester.startGesture(const Offset(180, 500));
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 60dp / 216dp ≈ 28%：面板应该已经露出来一部分，而不是「等松手才出现」
    final drawer = find.byType(Drawer);
    expect(drawer, findsOneWidget, reason: '拖动过程中抽屉就存在');
    final left = tester.getTopLeft(drawer).dx;
    expect(left, lessThan(0), reason: '还没完全展开');
    expect(left, greaterThan(-216), reason: '已经露出一部分（跟手）');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing, reason: '不到 40%，回弹收起');
  });

  testWidgets('拖过 40% 松手会吸附展开，点遮罩收起', (tester) async {
    await pumpHome(tester);
    final gesture = await tester.startGesture(const Offset(120, 500));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(18, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.getTopLeft(find.byType(Drawer)).dx, 0, reason: '吸附到完全展开');

    // 遮罩上点一下收起（x 落在抽屉右侧的遮罩区）
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
  });
}
