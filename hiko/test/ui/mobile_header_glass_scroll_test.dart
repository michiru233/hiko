import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/ui/screens/home_screen.dart';

/// 1.99.25 回归锁：滚动时头部不能被 AppBar 包进半透明 `Opacity`。
///
/// 背景（用户实机反馈「深色模式下往下划，上面的玻璃边框会消失」）：
/// 头部是挂在 `SliverAppBar(bottom: PreferredSize(...))` 上的，而 `pinned: false`
/// 的 SliverAppBar 一旦开始滚动就会算
///   `bottomOpacity = clampDouble(visibleMainHeight / _bottomHeight, 0, 1) < 1`
/// （app_bar.dart），于是 Flutter 把整个 `bottom` 包进 `Opacity` —— 一层离屏
/// saveLayer。玻璃材质是 BackdropFilter：进了 saveLayer 采不到底景，**描边与填充
/// 整块消失**，只剩文字（文字还会被这层顺带压暗几个 %，所以肉眼看着「就是玻璃没了」）。
///
/// 修法：`bottom` 声明 `Size.fromHeight(0)`（除数为 0 → 上式恒等于 1.0，永不进
/// Opacity 分支），真实高度改由 `expandedHeight` / `collapsedHeight` 表达。
///
/// 这个锁故意**只锁症状**：只要滚动后头部上方没有 alpha < 1 的 `Opacity` 就行，
/// 不关心实现细节，换成别的修法也不会误报。
/// 注意 `flutter_test` 里玻璃会降级成普通子树，但这一层 `Opacity` 是框架加的，
/// 测试抓得到。
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(_library(40))),
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
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('移动端本地视图：滚动到半开位置时头部不被 Opacity 包裹', (tester) async {
    await pumpHome(tester);

    final scrollable = find.byType(CustomScrollView).first;
    final headerItem = find.text('全部');

    // 逐档往半开位置滚（头部在这几档都还在屏上：1.99.25 实测 offset≈93 时
    // 出现过 Opacity(0.127)，offset≳120 头部整体滚出，测不到了）
    for (var step = 0; step < 3; step++) {
      await tester.drag(scrollable, const Offset(0, -30));
      await tester.pumpAndSettle();

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(
        position.pixels,
        greaterThan(0),
        reason: '第 ${step + 1} 档没有真的滚动，锁会空转',
      );
      expect(
        headerItem,
        findsWidgets,
        reason: '第 ${step + 1} 档（offset=${position.pixels}）头部已经滚出屏，'
            '这一档测的不是本锁要防的场景',
      );

      final faded = find.ancestor(
        of: headerItem.first,
        matching: find.byWidgetPredicate(
          (w) => w is Opacity && w.opacity < 1.0,
        ),
      );
      expect(
        faded,
        findsNothing,
        reason: '第 ${step + 1} 档（offset=${position.pixels}）头部被半透明 Opacity '
            '包住了 —— 玻璃是 BackdropFilter，进 saveLayer 会整块消失',
      );
    }
  });
}

class _SeededLibrary extends LibraryNotifier {
  _SeededLibrary(List<Album> albums) : super(LibraryStore()) {
    state = albums;
  }
}

Album _album(String id) => Album(
      id: id,
      sourcePath: '/x/$id',
      title: id,
      date: DateTime(2026),
      tracks: [Track(index: 0, name: 'n', url: 'file:///$id.mp3')],
    );

List<Album> _library(int count) =>
    List.generate(count, (i) => _album('rj${i.toString().padLeft(3, '0')}'));
