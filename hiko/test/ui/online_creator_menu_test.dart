import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/online_detail_panel.dart';

/// 创作者胶囊菜单的行为锁（1.99.48）。
///
/// 这一版把仓库里最后一处 `showMenu`（36dp 行高 / 12sp 字 / 无图标）
/// 换成了 `M3EMenu`。**换材质不能换行为**：三条动作一条都不能丢，
/// 也不能因为菜单组件换了就改掉「点一下之后要不要关菜单」。
///
/// 为什么值得单独测：这三条路径各自牵着一个别的子系统
/// （列表筛选回调 / 剪贴板 / 服务端黑名单），任何一条断了都不会有编译错误。
void main() {
  const circleName = 'サークル名';
  const vaName = '声優あ';

  OnlineDetail detail() => OnlineDetail(
    work: OnlineWork.fromJson(<String, dynamic>{
      'id': 1,
      'title': '作品',
      'name': circleName,
      'vas': <String>[vaName],
      'source_id': 'RJ01657200',
    }),
    tracks: const <OnlineTrack>[],
    tree: const <OnlineNode>[],
  );

  Future<ProviderContainer> pumpPanel(
    WidgetTester tester, {
    required List<OnlineCreatorFilter> filters,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        onlineClientProvider.overrideWith(
          (ref) => KikoeruClient(baseUrl: 'https://api.asmr.one'),
        ),
        onlineDetailProvider(1).overrideWith((ref) async => detail()),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: OnlineDetailBody(workId: 1, onSelectCreator: filters.add),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return container;
  }

  Future<void> openMenu(WidgetTester tester, String pillText) async {
    await tester.tap(find.text(pillText));
    await tester.pumpAndSettle();
  }

  testWidgets('胶囊菜单是 M3EMenu：三条动作齐全、行高 48', (tester) async {
    await pumpPanel(tester, filters: <OnlineCreatorFilter>[]);

    await openMenu(tester, circleName);

    expect(find.text('按此社团筛选'), findsOneWidget);
    expect(find.text('复制名字'), findsOneWidget);
    expect(find.text('屏蔽此社团'), findsOneWidget);
    expect(find.byType(M3EMenu), findsWidgets, reason: '菜单必须是 M3EMenu');
    // 旧的 36dp PopupMenuItem 已经不在；M3E 行高固定 48
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('复制名字'),
                  matching: find.byType(M3EPressable),
                )
                .first,
          )
          .height,
      48,
    );
  });

  testWidgets('「按此社团筛选」把 kind + name 交回给调用方，并关掉菜单', (tester) async {
    final filters = <OnlineCreatorFilter>[];
    await pumpPanel(tester, filters: filters);

    await openMenu(tester, circleName);
    await tester.tap(find.text('按此社团筛选'));
    await tester.pumpAndSettle();

    expect(filters, hasLength(1));
    expect(filters.single.kind, OnlineCreatorKind.circle);
    expect(filters.single.name, circleName);
    expect(find.text('复制名字'), findsNothing, reason: 'Action 行应当先关菜单再执行');
  });

  testWidgets('声优胶囊是同一件菜单，文案跟着 kind 走', (tester) async {
    final filters = <OnlineCreatorFilter>[];
    await pumpPanel(tester, filters: filters);

    await openMenu(tester, vaName);
    expect(find.text('按此声优筛选'), findsOneWidget);
    expect(find.text('屏蔽此声优'), findsOneWidget);

    await tester.tap(find.text('按此声优筛选'));
    await tester.pumpAndSettle();
    expect(filters.single.kind, OnlineCreatorKind.va);
    expect(filters.single.name, vaName);
  });

  testWidgets('「屏蔽此社团」写进服务端黑名单并给反馈', (tester) async {
    final container = await pumpPanel(tester, filters: <OnlineCreatorFilter>[]);

    await openMenu(tester, circleName);
    await tester.tap(find.text('屏蔽此社团'));
    await tester.pumpAndSettle();

    final blocked = container.read(settingsProvider).blockedCreators;
    expect(blocked, hasLength(1));
    expect(blocked.single.name, circleName);
    expect(blocked.single.kind, OnlineCreatorBlock.kindCircle);
    expect(
      find.textContaining('已屏蔽社团「$circleName」'),
      findsOneWidget,
      reason: '屏蔽是「看不见结果」的动作，必须有提示',
    );

    // toast 自己有 3.2s 的停留计时器；测试结束前让它走完，
    // 否则 binding 会因为「widget 树销毁时还有 pending timer」报错。
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('「复制名字」走剪贴板并提示', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await pumpPanel(tester, filters: <OnlineCreatorFilter>[]);

    await openMenu(tester, circleName);
    await tester.tap(find.text('复制名字'));
    await tester.pumpAndSettle();

    expect(copied, circleName);
    expect(find.text('已复制 $circleName'), findsOneWidget);
  });

  testWidgets('没有 onSelectCreator 时胶囊不可点、不出菜单', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineClientProvider.overrideWith(
            (ref) => KikoeruClient(baseUrl: 'https://api.asmr.one'),
          ),
          onlineDetailProvider(1).overrideWith((ref) async => detail()),
          settingsProvider.overrideWith((ref) => SettingsNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OnlineDetailBody(workId: 1)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await openMenu(tester, circleName);
    expect(find.text('复制名字'), findsNothing);
  });
}
