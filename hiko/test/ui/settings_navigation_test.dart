import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/online_account.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页抽屉化的导航契约（1.99.58）。
///
/// 1.99.32 的设置页是「5 组 72dp 单页、从外观一路画到关于」，1.99.58 改成
/// 索引页 + 二级页：索引页只放 8 个跳转格，行都在子页里。这一组用例锁的是
/// **跳转本身**（哪一格去哪、返回落在哪、哪一项没有子页而是开对话框），
/// 不锁子页里的具体排版——排版归 `settings_layout_test.dart`。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => <String, dynamic>{
            'appName': 'Hiko',
            'packageName': 'top.voicehub.hiko',
            'version': '1.99.58',
            'buildNumber': '171',
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          null,
        );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }


  Future<void> pumpSettings(WidgetTester tester, {double width = 720}) async {
    tester.view.physicalSize = Size(width, 2400);
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
          builder: (context, child) =>
              M3ETheme(data: buildM3EThemeData(const AppSettings()), child: child!),
          home: const SettingsPage(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('索引页：4 组标签 + 8 个跳转格齐全', (tester) async {
    await pumpSettings(tester);

    for (final group in const ['通用', '在线', '库']) {
      expect(find.text(group), findsOneWidget, reason: '分组标签 $group');
    }
    // 最后一组的组标签和它的跳转格同名，所以是两处
    expect(find.text('关于'), findsNWidgets(2));
    for (final tile in const [
      '外观与显示',
      '播放与音频',
      '主界面',
      '在线账号',
      '在线外观',
      '库与扫描',
      '数据与维护',
      '关于',
    ]) {
      expect(find.text(tile), findsWidgets, reason: '跳转格 $tile');
    }
    expect(find.byType(M3EListItem), findsNWidgets(8));
  });

  testWidgets('子页返回：落在索引页而不是退出设置', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('外观与显示'));
    await settle(tester);
    expect(find.text('设置'), findsNothing, reason: '标题换成了子页名');
    expect(find.text('外观与显示'), findsOneWidget);

    await tester.tap(find.byTooltip('返回设置'));
    await settle(tester);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('通用'), findsOneWidget, reason: '回到索引页');
    expect(find.byType(M3EListItem), findsNWidgets(8));
  });

  testWidgets('在线外观没有子页：直接开 Aa 对话框', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('在线外观'));
    await settle(tester);

    // 对话框里的四组旋钮 —— 与在线页工具栏 Aa 菜单是同一个组件
    expect(find.text('标签胶囊字号'), findsOneWidget);
    expect(find.text('每行卡片数'), findsOneWidget);
    // 设置页自己没换页：标题仍是「设置」
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('播放与音频：增益/步长在，手动「重置音频输出」已删', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('播放与音频'));
    await settle(tester);

    expect(find.text('默认增益放大'), findsOneWidget);
    expect(find.text('快进/快退秒数'), findsOneWidget);
    expect(find.text('重置音频输出'), findsNothing);
    expect(find.text('立即重接'), findsNothing);
  });

  testWidgets('在线账号：在线外观的 6 行已搬走，缓存明细另开一页', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('在线账号'));
    await settle(tester);

    // 1.99.58：这 6 项只剩在线页 Aa 对话框一处入口
    for (final gone in const [
      '标签胶囊字号',
      '在线卡片文字',
      '在线详情文字',
      '曲目标题字号',
      '每行卡片数',
      '每页条数',
    ]) {
      expect(find.text(gone), findsNothing, reason: '$gone 应只剩 Aa 对话框一处');
    }
    expect(find.text('在线缓存占用'), findsNothing, reason: '占用明细搬进缓存明细页');

    await tester.tap(find.text('缓存明细'));
    await settle(tester);
    expect(find.text('在线缓存占用'), findsOneWidget);
  });

  testWidgets('主界面 → 导航栏：排序开关在三级页里', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('主界面'));
    await settle(tester);
    expect(find.text('显示刮削标签'), findsOneWidget);
    expect(find.text('每行专辑数'), findsOneWidget);

    await tester.tap(find.text('导航栏'));
    await settle(tester);
    expect(find.textContaining('决定显示哪些一级入口及顺序'), findsOneWidget);
    expect(find.byType(M3ESwitch), findsWidgets);
  });
}
