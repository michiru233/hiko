import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/online_account.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/screens/online_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在线工具栏的窄屏锁：**360dp + 1.3 字号不溢出**（1.99.41）。
///
/// 这一行塞了三枚入口（只看带字幕 / 排序 / Aa）+ 一条状态行，是全站最挤的
/// 横向 Row 之一。1.99.40 把三枚 11sp compact `Chip` 换成 14sp `M3EChip` 后，
/// 排序胶囊从 116dp 涨到 154dp，360dp × 1.3 字号下把整行挤爆 8.3dp
/// （`RenderFlex overflowed`）。1.99.41 去掉「排序：」前缀、换回 swap_vert 图标，
/// 胶囊回到 121dp，与旧版持平。
///
/// 锁法：真挂 `OnlineScreen`（移动壳）+ 根层 `TextScaler(1.3)`。
/// 溢出会以 `FlutterError` 的形式让 `pump` 直接失败，所以「跑绿」本身就是断言；
/// 不需要（也不该）逐像素比对宽度，否则改文案就得改测试。
void main() {
  testWidgets('360dp × 1.3 字号：在线工具栏三枚入口不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
        onlineAccountProvider.overrideWith((ref) => OnlineAccountNotifier(ref)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // 设置页的 1.30 档：与 `main.dart` 根层同一个 TextScaler
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(body: OnlineScreen(isMobile: true)),
        ),
      ),
    );
    // 在线页在测试环境永远拉不到数据（HTTP 一律 400），加载圈是无限动画，
    // 所以用有界 pump 而不是 pumpAndSettle。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(OnlineScreen), findsOneWidget);
    // 1.99.45：预设两枚 + 字幕 + 排序 + Aa，整页胶囊统一成 5 枚 M3EChip
    expect(find.byType(M3EChip), findsNWidgets(5));
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });
}
