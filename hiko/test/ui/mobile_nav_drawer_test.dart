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
import 'package:shared_preferences/shared_preferences.dart';

/// 移动端导航从底部五宫格搬到左抽屉（1.99.65）在**主界面**层的接线。
///
/// widget 测试的宿主是 macOS，`Platform.isAndroid` 恒 false，移动布局靠
/// `HomeScreen(debugMobileLayout: true)` 这个测试缝打开（与 1.99.6 的播放栏测试同款）。
///
/// 锁四件事：
/// 1. 底部导航整条消失（`M3ENavBar` findsNothing）；
/// 2. 左缘往右拖能拉出抽屉，条目与旧底栏是同一份（本地音声 / 在线 … / 更多）；
/// 3. 点「更多」→ 抽屉收起 + 底部面板出现「设置」；
/// 4. 没有播放时「正在播放」是禁用态，点它不跳全屏播放页。
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

  testWidgets('底部导航已撤，左缘拖拽拉出抽屉', (tester) async {
    await pumpHome(tester);

    expect(find.byType(M3ENavBar), findsNothing, reason: '1.99.65 起移动端不再有底部导航');
    expect(find.text('更多'), findsNothing, reason: '抽屉日常隐藏');

    await openDrawer(tester);

    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('本地音声'), findsWidgets);
    expect(find.text('更多'), findsOneWidget);
    expect(find.textContaining('从屏幕左缘往右拖可随时拉出'), findsOneWidget);
  });

  testWidgets('点「更多」→ 抽屉收起 + 底部面板出现设置', (tester) async {
    await pumpHome(tester);
    await openDrawer(tester);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing, reason: '选完条目抽屉要收起');
    expect(find.text('设置'), findsOneWidget, reason: '更多面板里仍有设置入口');
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
}
