import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/widgets/sidebar.dart';

/// 侧栏导航项的配置化回归锁（1.99.4）。
///
/// 1.99.4 起侧栏一级导航由 `settings.navViews` 驱动（与安卓底栏共用一份
/// 「可见 + 顺序」配置，「本地音声」为根视图永久显示）。
/// 这里锁两条不变量：
/// 1. 隐藏的视图不再渲染；
/// 2. 显示顺序跟随配置，而不是写死的旧顺序。
///
/// 注意：第二个用例会触发 `setNavViewVisible` → **写 SharedPreferences**，
/// 而 widget 测试里没有真平台通道。不设 `setMockInitialValues` 的话
/// `getInstance()` 永不返回，整个测试文件会挂死（不是失败，是卡住）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSidebar(
    WidgetTester tester,
    List<String> navViews,
  ) async {
    final navNotifier = SettingsNotifier();
    navNotifier.state = AppSettings(navViews: navViews);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => navNotifier),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Sidebar(
              activeView: '本地音声',
              onViewChanged: _noopView,
              onOpenSettings: _noopSettings,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('隐藏的视图不渲染，配置内的视图与顺序生效', (tester) async {
    await pumpSidebar(tester, ['本地音声', '统计', '在线']);

    expect(find.text('本地音声'), findsOneWidget, reason: '根视图永久显示');
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);

    // 被隐藏的项一律不出现
    expect(find.text('最近添加'), findsNothing);
    expect(find.text('最近播放'), findsNothing);
    expect(find.text('正在播放'), findsNothing);
    expect(find.text('收藏夹'), findsNothing);
    expect(find.text('在线收藏'), findsNothing);

    // 顺序跟随配置：统计排在在线之前
    final statTop = tester.getTopLeft(find.text('统计')).dy;
    final onlineTop = tester.getTopLeft(find.text('在线')).dy;
    expect(statTop, lessThan(onlineTop), reason: '顺序应跟随 navViews 配置');
  });

  testWidgets('全部隐藏项重新显示后回到列表（顺序由配置决定）', (tester) async {
    final container = await pumpSidebar(tester, ['本地音声']);
    expect(find.text('统计'), findsNothing);

    // 模拟设置页重新显示「统计」：setNavViewVisible 追加到末尾
    await container
        .read(settingsProvider.notifier)
        .setNavViewVisible('统计', true);
    await tester.pump();

    expect(find.text('统计'), findsOneWidget);
  });
}

void _noopView(String view) {}
void _noopSettings() {}
