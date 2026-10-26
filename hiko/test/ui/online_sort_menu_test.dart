import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/online_sort_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在线「排序 + 分级筛选」下拉的回归锁（1.99.5 裁决 Q4=B；1.99.40 换 M3EMenu）。
///
/// 要锁的是一条不显眼、但改错了也不报错的行为：**勾分级不关菜单**。
/// 功能上「勾一下就关」照样能筛，只是三个开关得开三次菜单 ——
/// 与用户点名要的「三个复选框」该有的手感相悖，且没有断言就没人会发现退化。
///
/// 1.99.40 起指示器从 Material `Checkbox` 换成菜单行右侧的勾（裁决 ②=A），
/// 所以「菜单还开着」不再能靠 `find.byType(Checkbox)` 断言，改成
/// 「三个 `M3EMenuToggle` 仍在 + 排序项仍在」—— 锁的语义不变。
///
/// 手法：单 pump `OnlineSortMenu`（1.99.5 就是为了这个才从 `online_screen.dart`
/// 抽成公开组件）。`_AgeFilterToggle` 会 watch `onlineBrowseProvider`，
/// 它的构造函数要读 `settingsProvider` → SharedPreferences，所以必须
/// `setMockInitialValues`（否则 `getInstance()` 在 widget 测试里永不返回）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// pump 菜单并返回「被切换过的分级」记录，用于断言回调次数。
  ///
  /// 窗口刻意开高（1000px）：菜单按 `min(400, 屏高 × 0.45)` 限高，
  /// 而 48dp × 11 行 + 分区标题约 577px —— 桌面窗口下也会滚，
  /// 所以下面的用例在点分级之前都会先 `ensureVisible`。
  Future<List<OnlineAgeCategory>> pumpMenu(
    WidgetTester tester, {
    OnlineSort current = OnlineSort.latestPreset,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final toggled = <OnlineAgeCategory>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 只需要换掉客户端，Notifier 就不会真的去发请求
          onlineClientProvider.overrideWith(
            (ref) => KikoeruClient(baseUrl: 'https://api.example.invalid'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: OnlineSortMenu(
                current: current,
                onSelected: (_) async {},
                onToggleAge: (c) async => toggled.add(c),
              ),
            ),
          ),
        ),
      ),
    );
    return toggled;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(M3EChip));
    await tester.pumpAndSettle();
  }

  /// 菜单是滚动容器：48dp 行 + 8 个排序之后，三个分级开关在折线下方。
  Future<void> scrollTo(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
  }

  Finder toggleChecks() => find.descendant(
    of: find.byType(M3EMenuToggle),
    matching: find.byIcon(Icons.check_rounded),
  );

  testWidgets('8 个排序 + 3 个分级开关都在，分级默认全勾（= 不筛）', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    expect(find.byType(M3EMenuAction), findsNWidgets(OnlineSort.values.length));
    expect(find.byType(M3EMenuToggle), findsNWidgets(3));
    expect(find.text('分级'), findsOneWidget);
    expect(toggleChecks(), findsNWidgets(3));
    for (final category in OnlineAgeCategory.values) {
      expect(find.text(category.label), findsOneWidget);
    }
  });

  testWidgets('点分级文字：回调恰好一次，且菜单不关', (tester) async {
    final toggled = await pumpMenu(tester);
    await openMenu(tester);

    await scrollTo(tester, OnlineAgeCategory.adult.label);
    // 点「文字」而不是点勾 —— 整行都该是可点区域
    await tester.tap(find.text(OnlineAgeCategory.adult.label));
    await tester.pumpAndSettle();

    expect(toggled, [OnlineAgeCategory.adult]);
    expect(find.byType(M3EMenuToggle), findsNWidgets(3), reason: '勾完菜单不该关');
  });

  testWidgets('点右侧勾本体：也只触发一次（两个 tap 目标不重复计）', (tester) async {
    final toggled = await pumpMenu(tester);
    await openMenu(tester);

    await scrollTo(tester, OnlineAgeCategory.adult.label);
    // 勾是行内的纯指示器，命中的仍是整行那一层 M3EPressable
    await tester.tap(
      find
          .descendant(
            of: find.byType(M3EMenuToggle).first,
            matching: find.byIcon(Icons.check_rounded),
          )
          .first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(toggled, hasLength(1));
  });

  testWidgets('连着勾两个：菜单一路开着，回调按序累积', (tester) async {
    final toggled = await pumpMenu(tester);
    await openMenu(tester);

    await scrollTo(tester, OnlineAgeCategory.r15.label);
    await tester.tap(find.text(OnlineAgeCategory.r15.label));
    await tester.pumpAndSettle();
    await scrollTo(tester, OnlineAgeCategory.general.label);
    await tester.tap(find.text(OnlineAgeCategory.general.label));
    await tester.pumpAndSettle();

    expect(toggled, [OnlineAgeCategory.r15, OnlineAgeCategory.general]);
    expect(find.byType(M3EMenuToggle), findsNWidgets(3));
  });

  testWidgets('排序项维持原行为：选了就关菜单', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    await tester.tap(find.text(OnlineSort.rjDesc.label));
    await tester.pumpAndSettle();

    expect(find.byType(M3EMenuAction), findsNothing);
    expect(find.byType(M3EMenuToggle), findsNothing);
  });
}
