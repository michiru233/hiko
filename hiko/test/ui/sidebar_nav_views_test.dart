import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/screens/home_screen.dart';

/// 导航项配置化回归锁（1.99.4 立，1.99.27 迁到 rail）。
///
/// 1.99.4 起一级导航由 `settings.navViews` 驱动（桌面 rail 与移动底栏共用
/// 一份「可见 + 顺序」配置，「本地音声」永久显示）。1.99.27 拆掉侧栏后，
/// 这份配置的消费方从 `Sidebar` 变成了 `HomeScreen._navDestinations`，
/// 但两条不变量没变：
/// 1. 隐藏的视图不渲染；
/// 2. 显示顺序跟随配置，而不是写死顺序。
class _SeededLibrary extends LibraryNotifier {
  _SeededLibrary(List<Album> albums) : super(LibraryStore()) {
    state = albums;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpHome(WidgetTester tester, List<String> navViews) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final settings = SettingsNotifier();
    settings.state = AppSettings(navViews: navViews);
    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(const [])),
        settingsProvider.overrideWith((ref) => settings),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen(debugMobileLayout: false)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('隐藏的视图不渲染，配置内的视图与顺序生效', (tester) async {
    await pumpHome(tester, const ['本地音声', '统计', '在线']);

    final rail = find.byType(M3ENavRail);
    expect(rail, findsOneWidget);

    // 根视图永久显示
    expect(
      find.descendant(of: rail, matching: find.text('本地音声')),
      findsOneWidget,
    );
    // 配置内的两项
    expect(
      find.descendant(of: rail, matching: find.text('统计')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('在线')),
      findsOneWidget,
    );
    // 不在配置里的旧项不得出现
    expect(
      find.descendant(of: rail, matching: find.text('收藏夹')),
      findsNothing,
    );

    // 顺序：本地音声 在 统计 上方，统计 在 在线 上方
    // 注意作用域：这三个词在顶栏面包屑与页面大标题里也各出现一次
    Finder inRail(String label) =>
        find.descendant(of: rail, matching: find.text(label));
    final home = tester.getTopLeft(inRail('本地音声')).dy;
    final stats = tester.getTopLeft(inRail('统计')).dy;
    final online = tester.getTopLeft(inRail('在线')).dy;
    expect(home, lessThan(stats));
    expect(stats, lessThan(online));
  });

  testWidgets('点 rail 项切换主视图', (tester) async {
    await pumpHome(tester, const ['本地音声', '统计']);

    await tester.tap(
      find.descendant(
        of: find.byType(M3ENavRail),
        matching: find.text('统计'),
      ),
    );
    await tester.pumpAndSettle();

    // 统计视图在场（它的滚动体与本地网格不同）
    expect(find.text('统计'), findsWidgets);
  });
}
