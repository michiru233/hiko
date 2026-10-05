import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/screens/home_screen.dart';

/// 1.99.24 回归锁：移动端顶栏必须垫上与内容区一致的不透明底色。
///
/// 背景（用户实机反馈「深色模式下最上面一层有色差」）：
/// `home_screen.dart` 的 Stack 首子项是「正在播放封面环境光晕」（σ80、深色
/// 不透明度 0.15）。它**只**在顶栏那条透出来 —— 因为移动端本地视图的头部从
/// 1.99.9 起就垫了页面底色（`_buildLocalScrollable` 里的 `ColoredBox`），
/// 顶栏却一直是透明的。实测顶栏 (53,50,59) 而其余全屏 (30,31,36)，
/// 横向还有一条左亮右暗的渐变；同一时刻滚动后的截图（没有正在播放）则全场均匀。
///
/// 这里锁的就是「顶栏上方存在一层全不透明的垫色」，且桌面端**不能有**
/// （桌面主列整列透明，光晕本来就该从顶栏一带透出来）。
void main() {
  const switchTheme = '切换主题';

  Future<void> pumpHome(WidgetTester tester, {required bool mobile}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(mobile ? 900 : 1440, 1400);
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
        child: MaterialApp(
          home: HomeScreen(debugMobileLayout: mobile ? true : false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// 顶栏那一排按钮的所有**全不透明**垫色祖先。
  ///
  /// 用 `ColoredBox` 而不是泛泛的「有没有背景」：垫色就是靠它铺的，
  /// 而且判 alpha 才能区分「垫了页面底色」和「垫了一层透明/半透明的东西」。
  Finder opaqueBackdropsAbove(Finder barItem) => find.ancestor(
        of: barItem,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color.a == 1.0,
        ),
      );

  testWidgets('移动端顶栏垫了全不透明底色（光晕不会只在顶栏透出一条）', (tester) async {
    await pumpHome(tester, mobile: true);
    expect(find.byTooltip(switchTheme), findsOneWidget, reason: '顶栏在位');

    expect(
      opaqueBackdropsAbove(find.byTooltip(switchTheme)),
      findsWidgets,
      reason: '顶栏必须在光晕之上垫一层不透明底色，否则「正在播放封面光晕」'
          '只会在顶栏这条透出来，形成一道横向色差',
    );
  });

  testWidgets('桌面端顶栏不垫底色（垫了会在桌面凭空造出横向接缝）', (tester) async {
    await pumpHome(tester, mobile: false);
    expect(find.byTooltip(switchTheme), findsOneWidget, reason: '顶栏在位');

    expect(
      opaqueBackdropsAbove(find.byTooltip(switchTheme)),
      findsNothing,
      reason: '桌面主列整列透明，光晕本来就该从顶栏一带透出来（1.55 的原始意图）',
    );
  });
}

class _SeededLibrary extends LibraryNotifier {
  _SeededLibrary(List<Album> albums) : super(LibraryStore()) {
    state = albums;
  }
}
