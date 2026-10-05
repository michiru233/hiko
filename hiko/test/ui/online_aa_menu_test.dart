import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/online/online_account.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/screens/home_screen.dart';
import 'package:hiko/ui/screens/online_favorites_screen.dart';
import 'package:hiko/ui/screens/online_screen.dart';
import 'package:hiko/ui/widgets/mobile_bottom_nav.dart';
import 'package:hiko/ui/widgets/online_appearance.dart';

/// 1.99.20 回归锁：移动端在线页顶栏图标收敛 + 「Aa」三合一菜单。
///
/// 背景（用户实机反馈）：移动端在线页最上方是一排 4 个图标按钮
/// （定位当前播放 / 切换主题 / 隐私模糊 / 随机播放），占掉整屏最高处最宽的一行。
/// 其中「定位当前播放」和「随机播放」都只作用于**本地库**（随机播放是盲选一张
/// 本地专辑），在在线页毫无意义；「切换主题」「隐私模糊」有用。
///
/// 裁决：Q1=B（在线 / 在线收藏都收起，收藏页补一个 Aa）、Q2=A（两端统一下拉）、
/// Q3=A（开关式、点一下不关菜单）、Q4=A（桌面顶栏保留，Aa 菜单两端一致）、
/// Q5=A（标签仍写「Aa」）。
///
/// 三处锁在这里：
/// 1. Aa 菜单三个条目齐全，且两个开关**就地切换 + 菜单不关**（开关式）；
/// 2. 「在线外观」仍落到原来的对话框；
/// 3. 移动端在线视图顶栏整行收起、本地视图保留；收藏页也有 Aa。
void main() {
  setUp(() {
    // 防社死是全局内存态（默认开），用例之间会串味
    privacyBlur.value = true;
  });

  // ────────────────────────── Aa 菜单本体 ──────────────────────────

  testWidgets('Aa 菜单：三个条目齐全（在线外观 / 防社死 / 外观切换）', (tester) async {
    await _pumpAaMenu(tester);
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();

    expect(find.text('在线外观'), findsOneWidget);
    expect(find.text('防社死'), findsOneWidget);
    expect(find.text('外观切换'), findsOneWidget);
  });

  testWidgets('防社死：点一下就切换，菜单不关（开关式，裁决 Q3=A）', (tester) async {
    expect(privacyBlur.value, isTrue, reason: '默认开启（1.52 起不持久化）');
    await _pumpAaMenu(tester);
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    expect(find.text('已开启'), findsOneWidget, reason: '条目要显示当前状态');

    await tester.tap(find.text('防社死'));
    await tester.pumpAndSettle();

    expect(privacyBlur.value, isFalse, reason: '就地切换');
    expect(find.text('已关闭'), findsOneWidget, reason: '状态要立刻刷新，不用重开菜单');
    expect(find.text('外观切换'), findsOneWidget,
        reason: '菜单必须还开着 —— 关掉了就退化成「动作式」，连点两个开关要重开两次');
  });

  testWidgets('外观切换：点一下就切明暗，菜单不关（开关式）', (tester) async {
    final container = await _pumpAaMenu(tester);
    expect(container.read(settingsProvider).theme, 'light');

    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    expect(find.text('浅色'), findsOneWidget);

    await tester.tap(find.text('外观切换'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).theme, 'dark', reason: '主题真的切了');
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('防社死'), findsOneWidget, reason: '菜单不关');
  });

  testWidgets('在线外观：仍落到原来那个对话框', (tester) async {
    await _pumpAaMenu(tester);
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('在线外观'));
    await tester.pumpAndSettle();

    // 对话框正文的第一组滑杆 —— 说明 showOnlineAppearanceDialog 被调起来了
    expect(find.text('标签胶囊字号'), findsOneWidget);
    expect(find.text('每行卡片数'), findsOneWidget);
  });

  // ────────────────────── 移动端顶栏收敛（整页） ──────────────────────

  testWidgets('移动端在线视图：顶栏图标整行收起；本地视图保留', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(const [])),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen(debugMobileLayout: true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // 本地视图（默认）——4 个图标原样在场
    expect(find.byTooltip('定位当前播放'), findsOneWidget);
    expect(find.byTooltip('切换主题'), findsOneWidget);
    expect(find.byTooltip('随机播放'), findsOneWidget);

    // 切到「在线」
    await tester.tap(
      find.descendant(
        of: find.byType(MobileBottomNav),
        matching: find.text('在线'),
      ),
    );
    await _pumpFrames(tester);
    expect(find.byType(OnlineScreen), findsOneWidget);

    expect(find.byTooltip('定位当前播放'), findsNothing, reason: '在线页收起');
    expect(find.byTooltip('切换主题'), findsNothing, reason: '并进 Aa 菜单了');
    expect(find.byTooltip('随机播放'), findsNothing, reason: '在线页收起');

    // 两个有用功能改从 Aa 菜单进
    expect(find.text('Aa'), findsOneWidget);

    // 切回本地视图 —— 必须原样恢复
    await tester.tap(
      find.descendant(
        of: find.byType(MobileBottomNav),
        matching: find.text('本地音声'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('随机播放'), findsOneWidget);
    expect(find.byTooltip('定位当前播放'), findsOneWidget);
  });

  testWidgets('在线收藏页：补上的 Aa 入口在场（裁决 Q1=B）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
        onlineAccountProvider.overrideWith((ref) => _LoggedInAccount(ref)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: OnlineFavoritesScreen(isMobile: true)),
        ),
      ),
    );
    await _pumpFrames(tester);

    // 收藏页原先没有任何外观入口；顶栏图标一收，防社死在这一页就够不着了
    expect(find.text('Aa'), findsOneWidget);
  });
}

// ─────────────────────────────── 脚手架 ───────────────────────────────

/// 单独挂 [OnlineAaMenu]（外面套一层 ProviderScope，好读设置状态）。
Future<ProviderContainer> _pumpAaMenu(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [settingsProvider.overrideWith((ref) => SettingsNotifier())],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: Center(child: OnlineAaMenu())),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// 有界 pump（不追求「全部动画停下」）。
///
/// 在线页在测试环境永远拉不到数据（flutter_test 里所有 HTTP 都返回 400），
/// 账号入口/内容区的加载圈是无限动画 —— 碰它会超时的是 `pumpAndSettle`。
Future<void> _pumpFrames(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

class _SeededLibrary extends LibraryNotifier {
  _SeededLibrary(List<Album> albums) : super(LibraryStore()) {
    state = albums;
  }
}

/// 已登录的假账号：收藏页只有登录后才走 `_buildHeader`（未登录是登录引导）。
class _LoggedInAccount extends OnlineAccountNotifier {
  _LoggedInAccount(super._ref) {
    state = OnlineAccountState(
      restoring: false,
      token: 'test-token',
      user: const OnlineUser(loggedIn: true, name: 'tester'),
    );
  }
}
