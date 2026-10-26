import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/screens/home_screen.dart';

/// 1.99.47 回归锁：首页排序入口从「自绘胶囊 + showHikoContextMenu」
/// 换成 `M3EChip` + `M3EMenu` 之后，仍然要满足三件事：
///
/// 1. 入口是 `M3EChip`（不再是 Material `Chip`，也不再是自绘胶囊）；
/// 2. 点开后 8 条排序项都在，且只有当前排序带勾；
/// 3. 选一项之后真的写回 `settingsProvider.albumSort` 并关菜单。
///
/// 另外锁住移动端 360dp：入口文案不带「排序 · 」前缀（宽屏才带），
/// 且菜单展开不产生溢出。
void main() {
  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    Size size = const Size(900, 1400),
    bool mobile = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(_library(6))),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: HomeScreen(debugMobileLayout: mobile ? true : null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return container;
  }

  /// 排序入口：唯一带 swap_vert 图标的 `M3EChip`。
  Finder sortChip() => find.ancestor(
    of: find.byIcon(Icons.swap_vert_rounded),
    matching: find.byType(M3EChip),
  );

  testWidgets('桌面端：入口是 M3EChip，8 条排序项都能选，且写回设置', (tester) async {
    final container = await pumpHome(tester);

    // 默认 albumSort = artist_asc → 宽屏带「排序 · 」前缀
    expect(
      find.text('排序 · 专辑艺术家'),
      findsOneWidget,
      reason: '默认排序入口文案不对，可能 _currentLabel 或前缀分支被改了',
    );
    expect(sortChip(), findsOneWidget, reason: '排序入口不是 M3EChip');

    await tester.tap(sortChip());
    await tester.pumpAndSettle();

    expect(
      find.byType(M3EMenuAction),
      findsNWidgets(8),
      reason: '排序项数量变了：_sortOptions 与菜单渲染不再一一对应',
    );

    final actions = tester
        .widgetList<M3EMenuAction>(find.byType(M3EMenuAction))
        .toList();
    final selected = actions.where((a) => a.selected).toList();
    expect(selected.length, 1, reason: '选中勾必须唯一，否则「当前排序」不可读');
    expect(selected.single.label, contains('专辑艺术家'));

    await tester.tap(find.text('评分优先'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).albumSort,
      'rating_desc',
      reason: '选中排序没有写回 settingsProvider',
    );
    expect(find.text('排序 · 评分优先'), findsOneWidget, reason: '选完之后入口文案没跟着更新');
    expect(
      find.byType(M3EMenuAction),
      findsNothing,
      reason: 'M3EMenuAction 应在执行回调前关掉菜单（见 _M3EMenuRow）',
    );
  });

  testWidgets('移动端 360dp：入口不带前缀，菜单展开不溢出', (tester) async {
    await pumpHome(tester, size: const Size(360, 800), mobile: true);

    expect(
      find.text('专辑艺术家'),
      findsOneWidget,
      reason: '移动端入口应只用短标签（带前缀会在 360dp 下挤压工具栏）',
    );
    expect(find.text('排序 · 专辑艺术家'), findsNothing);

    await tester.tap(sortChip());
    await tester.pumpAndSettle();

    expect(find.byType(M3EMenuAction), findsNWidgets(8));
    expect(tester.takeException(), isNull, reason: '360dp 下展开排序菜单出现溢出/布局异常');
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
