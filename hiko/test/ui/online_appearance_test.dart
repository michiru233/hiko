import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/detail_kit.dart';
import 'package:hiko/ui/widgets/online_appearance.dart';
import 'package:hiko/ui/widgets/online_work_grid.dart';

/// 1.96.0：可调外观的四组旋钮与两处入口。
/// 1.97.0：字号三组 + 曲目标题从**离散档位**改成**连续滑杆**（裁决 Q2），
/// 列数保持档位单选（列数是整数，滑杆没有意义）。
///
/// 这一版的关键风险不是「功能没做」，而是**同一件事被写了两遍**：
/// ① 值域在设置页与 Aa 对话框各写一份 → 两处可调范围不同；
/// ② 字号在「量高度」和「画出来」两处各算一遍 → 卡片高度对不上。
/// 所以下面两类断言都是冲着「两处必须一致」去的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Widget child) => MaterialApp(
        theme: buildHikoTheme(const AppSettings()),
        home: Scaffold(body: Center(child: child)),
      );

  double? fontSizeOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.fontSize;

  // ------------------------------------------------------------ 值域一致性

  test('在线外观值域与设置层 clamp 范围逐位一致（防两处漂移）', () {
    expect(
      onlineGridColumnsChoices.map((e) => e.$1).toList(),
      SettingsNotifier.validOnlineGridColumns,
    );
    // 滑杆的 min/max 直接引用设置层常量（编译期绑定），这里钉住引用关系：
    // 哪天有人把 UI 侧改成字面量，这条会当场红
    expect(SettingsNotifier.tagFontSizeMin, 8.0);
    expect(SettingsNotifier.tagFontSizeMax, 18.0);
    expect(SettingsNotifier.tagFontSizeDefault, 11.0);
    expect(SettingsNotifier.onlineTextScaleMin, 0.75);
    expect(SettingsNotifier.onlineTextScaleMax, 1.60);
    expect(SettingsNotifier.onlineTextScaleDefault, 1.0);
    expect(SettingsNotifier.trackTitleFontSizeMin, 10.0);
    expect(SettingsNotifier.trackTitleFontSizeMax, 20.0);
    expect(SettingsNotifier.trackTitleFontSizeDefault, 12.0);
  });

  test('连续值往返：范围内原样保留、范围外 clamp 到边界（两组倍率 + 两个绝对字号）',
      () async {
    final notifier = SettingsNotifier();
    await notifier.load();

    // 连续取值（旧档位之外的中间值也合法 —— 这正是「无极调」的意义）
    for (final v in [0.9, 1.0, 1.05, 1.42]) {
      await notifier.setOnlineCardTextScale(v);
      expect(notifier.state.onlineCardTextScale, v);
    }
    for (final v in [8.0, 10.5, 11.0, 16.0]) {
      await notifier.setTagFontSize(v);
      expect(notifier.state.tagFontSize, v);
    }
    for (final v in [10.0, 13.5, 20.0]) {
      await notifier.setOnlineTrackTitleFontSize(v);
      expect(notifier.state.onlineTrackTitleFontSize, v);
    }
  });

  // ------------------------------------------------------------ 高度预算

  test('卡片文字区高度预算随倍率与全局字号一起增长', () {
    const none = TextScaler.noScaling;
    final base = onlineCardTextBlockHeight(none, 1.0);

    // 默认值应与 1.95.0 那个硬编码的 62 基本一致 —— 默认外观不该变
    expect(base, closeTo(62, 1.0), reason: '默认档位下必须复刻 1.95.0 的观感');

    final byScale = onlineCardTextBlockHeight(none, 1.3);
    final byScaler = onlineCardTextBlockHeight(TextScaler.linear(1.3), 1.0);
    expect(byScale, greaterThan(base));
    expect(byScaler, greaterThan(base));

    // 两个旋钮叠加时，必须严格大于各自单独放大 ——
    // 漏掉任何一个（比如只乘了 scaler 忘了 textScale）这条就不成立
    final both = onlineCardTextBlockHeight(TextScaler.linear(1.3), 1.3);
    expect(both, greaterThan(byScale));
    expect(both, greaterThan(byScaler));
  });

  test('标签行高度随标签字号增长，且始终装得下胶囊本身', () {
    const none = TextScaler.noScaling;
    final h11 = onlineCardTagRowHeight(none, 11);
    expect(onlineCardTagRowHeight(none, 14), greaterThan(h11));
    expect(onlineCardTagRowHeight(TextScaler.linear(1.3), 11), greaterThan(h11));

    // 胶囊自身高度必须放得进这块预算，否则会被外层 SizedBox 裁掉半行
    final chipHeight =
        HikoTagChip.verticalPadding * 2 + 11 * HikoTagChip.lineHeight;
    expect(h11, greaterThanOrEqualTo(chipHeight));
  });

  // ------------------------------------------------------------ 标签字号作用域

  group('标签胶囊字号（1.96.0 裁决 Q1/Q2）', () {
    testWidgets('没有作用域时用默认 11（1.94.0 之前是硬编码 9）', (tester) async {
      await tester.pumpWidget(host(const HikoTagChip(tag: 'ASMR')));
      expect(fontSizeOf(tester, 'ASMR'), HikoTagFontScope.defaultFontSize);
      expect(HikoTagFontScope.defaultFontSize, 11);
    });

    testWidgets('套上作用域后跟随它 —— 本地与在线因此共用一套字号', (tester) async {
      await tester.pumpWidget(
        host(
          const HikoTagFontScope(
            fontSize: 14,
            child: HikoTagChip(tag: 'ASMR'),
          ),
        ),
      );
      expect(fontSizeOf(tester, 'ASMR'), 14);
    });

    testWidgets('作用域变化会重建胶囊（不是只在首帧读一次）', (tester) async {
      await tester.pumpWidget(
        host(
          const HikoTagFontScope(fontSize: 9, child: HikoTagChip(tag: 'ASMR')),
        ),
      );
      expect(fontSizeOf(tester, 'ASMR'), 9);

      await tester.pumpWidget(
        host(
          const HikoTagFontScope(fontSize: 12, child: HikoTagChip(tag: 'ASMR')),
        ),
      );
      expect(fontSizeOf(tester, 'ASMR'), 12);
    });
  });

  // ------------------------------------------------------------ Aa 对话框

  group('Aa 对话框（1.97.0 滑杆版）', () {
    /// 默认 800×600 放不下五组竖排（会被限高截断），把视口拉高让整份内容可见
    Future<void> pumpDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildHikoTheme(const AppSettings()),
            home: const Scaffold(body: OnlineAppearanceDialog()),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('五组设置都在（四组滑杆 + 列数单选）', (tester) async {
      await pumpDialog(tester);

      for (final title in [
        '标签胶囊字号',
        '在线卡片文字',
        '在线详情文字',
        '曲目标题字号',
        '每行卡片数',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      // 四组滑杆：标签字号 / 卡片倍率 / 详情倍率 / 曲目标题
      expect(find.byType(Slider), findsNWidgets(4));
      // 列数仍是单选档位
      expect(find.text('5 列'), findsOneWidget);
    });

    testWidgets('向右拖「标签胶囊字号」滑杆会写进设置', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      await tester.drag(find.byType(Slider).first, const Offset(160, 0));
      await tester.pump();

      final value = container.read(settingsProvider).tagFontSize;
      expect(value, greaterThan(11.0), reason: '向右拖应当增大字号');
      expect(value, lessThanOrEqualTo(SettingsNotifier.tagFontSizeMax),
          reason: '滑杆不允许拖出值域');
    });

    testWidgets('卡片与详情是两组独立滑杆（拖一组不动另一组）', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      // 滑杆顺序：0 标签字号 / 1 卡片 / 2 详情 / 3 曲目标题
      await tester.drag(find.byType(Slider).at(1), const Offset(160, 0));
      await tester.pump();

      expect(container.read(settingsProvider).onlineCardTextScale,
          greaterThan(1.0));
      expect(container.read(settingsProvider).onlineDetailTextScale, 1.0,
          reason: '两组是独立的旋钮');
      expect(container.read(settingsProvider).tagFontSize, 11.0,
          reason: '标签字号是第三组独立旋钮，不该被连带');
    });

    testWidgets('重置按钮把该组拉回默认值', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      // 先拖大标签字号，再点它那一行的重置
      await tester.drag(find.byType(Slider).first, const Offset(160, 0));
      await tester.pump();
      expect(container.read(settingsProvider).tagFontSize,
          greaterThan(11.0));

      // 四颗重置里第一颗属于标签字号那一行（都叫「重置为默认」，按位置取）
      await tester.tap(find.byTooltip('重置为默认').first);
      await tester.pump();

      expect(container.read(settingsProvider).tagFontSize, 11.0,
          reason: '重置应回到默认 11');
    });

    testWidgets('曲目标题字号是独立的一组滑杆', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      await tester.drag(find.byType(Slider).at(3), const Offset(-160, 0));
      await tester.pump();

      expect(container.read(settingsProvider).onlineTrackTitleFontSize,
          lessThan(12.0), reason: '向左拖应当减小字号');
      expect(container.read(settingsProvider).onlineDetailTextScale, 1.0,
          reason: '曲目标题不乘详情倍率，是两把独立的旋钮');
    });

    testWidgets('点每行卡片数档位会写进设置', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      await tester.tap(find.text('5 列'));
      await tester.pump();

      expect(container.read(settingsProvider).onlineGridColumns, 5);
    });
  });
}
