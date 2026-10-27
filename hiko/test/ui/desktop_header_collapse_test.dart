import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/ui/screens/home_screen.dart';

/// 1.99.50 裁决：桌面端头部（hero / 分类行 / 筛选行 / 结果行 / 续播横幅）
/// **滚走即收起，且只有滚回最顶才重新展开**。
///
/// 这和移动端的 floating（上滑跟手就回来）是两条不同语义：桌面用鼠标滚轮，
/// 往回滚一格就把整块头部顶回来，阅读时很烦。所以这里锁死三件事：
///
/// 1. 往下滚 → 头部整块消失（不是淡出，是不占高度）；
/// 2. 往回滚但没到顶 → **仍然不出现**（这条是本次裁决与 floating 的分水岭）；
/// 3. 回到 offset 0 → 展开。
///
/// 另有一条护栏：内容本来就几乎不超一屏时，不许收起（否则「收起 → 视口变高
/// → offset 被夹回 0 → 展开」会来回抖）。
void main() {
  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    Size size = const Size(1000, 720),
    int count = 24,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(_library(count))),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return container;
  }

  /// 网格自己的滚动位置（页面里还有侧栏等滚动体，必须限定在网格内）
  ScrollPosition gridPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(MasonryGridView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  /// hero 的眼眉文案，只在头部里出现，用来判断头部是否还在
  final hero = find.text('PERSONAL LIBRARY');

  testWidgets('桌面端：滚下去头部整块收起，滚回一半不出现，回到顶部才展开', (tester) async {
    await pumpHome(tester);
    expect(hero, findsOneWidget, reason: '刚进页面时头部必须在');

    final position = gridPosition(tester);
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: '种子库要足够长，否则这条用例量不到滚动',
    );

    // ① 往下滚一段 → 收起
    position.jumpTo(300);
    await tester.pumpAndSettle();
    expect(hero, findsNothing, reason: '滚下去之后头部应整块消失（不是淡出）');

    // ② 往回滚但没到顶 → 仍然不出现（与 floating 的区别）
    position.jumpTo(120);
    await tester.pumpAndSettle();
    expect(hero, findsNothing, reason: '只往上滚一点就露头，等于又变回 floating 了');

    // ③ 回到最顶 → 展开
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(hero, findsOneWidget, reason: 'offset 归零必须展开');
  });

  testWidgets('收起后再往下滚不会闪一下头部（状态稳定）', (tester) async {
    await pumpHome(tester);
    final position = gridPosition(tester);

    position.jumpTo(400);
    await tester.pumpAndSettle();
    expect(hero, findsNothing);

    // 连续小步往下滚：每步都不该把头部带回来
    for (var i = 0; i < 3; i++) {
      position.jumpTo(position.pixels + 40);
      await tester.pumpAndSettle();
      expect(hero, findsNothing, reason: '收起状态下继续下滚不应重新展开');
    }
  });

  testWidgets('内容几乎不超一屏时不收起（防「收起↔展开」抖动）', (tester) async {
    // 3 张卡在 1000x720 下基本一屏放得下
    await pumpHome(tester, count: 3);
    expect(hero, findsOneWidget);

    // 有得滚就滚到底；没得滚 maxScrollExtent = 0，drag 也会被夹住
    await tester.drag(find.byType(MasonryGridView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(
      hero,
      findsOneWidget,
      reason: '短内容收起后没得滚，会把 offset 夹回 0 再展开，必须不进入这个循环',
    );
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
