import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/detail_kit.dart';
import 'package:hiko/ui/widgets/online_appearance.dart';
import 'package:hiko/ui/widgets/online_work_grid.dart';

/// 1.96.0：可调外观的四组档位与两处入口。
///
/// 这一版的关键风险不是「功能没做」，而是**同一件事被写了两遍**：
/// ① 档位可选集在设置页与 Aa 对话框各写一份 → 两处可选值不同；
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

  // ------------------------------------------------------------ 档位一致性

  test('在线外观档位与设置层白名单逐位一致（防两处漂移）', () async {
    expect(
      tagFontSizeChoices.map((e) => e.$1).toList(),
      SettingsNotifier.validTagFontSizes,
      reason: 'UI 给不出的档位无所谓，但 UI 给得出、设置层不收就会「选中项自己跳回去」',
    );
    expect(
      onlineGridColumnsChoices.map((e) => e.$1).toList(),
      SettingsNotifier.validOnlineGridColumns,
    );

    // 倍率组没有公开白名单（归一化函数是私有的），所以逐档写进去、读回来必须原样 ——
    // 被归一化成别的值就说明这一档不在白名单里
    final notifier = SettingsNotifier();
    for (final (value, _) in onlineTextScaleChoices) {
      await notifier.setOnlineCardTextScale(value);
      expect(notifier.state.onlineCardTextScale, value);
      await notifier.setOnlineDetailTextScale(value);
      expect(notifier.state.onlineDetailTextScale, value);
    }
    for (final (value, _) in tagFontSizeChoices) {
      await notifier.setTagFontSize(value);
      expect(notifier.state.tagFontSize, value);
    }
    for (final (value, _) in onlineGridColumnsChoices) {
      await notifier.setOnlineGridColumns(value);
      expect(notifier.state.onlineGridColumns, value);
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

  group('Aa 对话框', () {
    /// 默认 800×600 放不下四组竖排（会被限高截断），把视口拉高让整份内容可见
    Future<void> pumpDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
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

    testWidgets('四组设置都在，且用的是与设置页同一份档位定义', (tester) async {
      await pumpDialog(tester);

      for (final title in ['标签胶囊字号', '在线卡片文字', '在线详情文字', '每行卡片数']) {
        expect(find.text(title), findsOneWidget);
      }
      // 标签字号 5 档
      for (final (_, label) in tagFontSizeChoices) {
        expect(find.text(label), findsOneWidget);
      }
      // 倍率组 4 档 × 2 组
      for (final (_, label) in onlineTextScaleChoices) {
        expect(find.text(label), findsNWidgets(2));
      }
    });

    testWidgets('点卡片文字那组只改卡片，不连带改详情', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      // 倍率标签在两组里各出现一次，`.first` = 卡片文字那一组
      await tester.tap(find.text('1.30×（超大）').first);
      await tester.pump();

      expect(container.read(settingsProvider).onlineCardTextScale, 1.3);
      expect(container.read(settingsProvider).onlineDetailTextScale, 1.0,
          reason: '两组是独立的旋钮');
    });

    testWidgets('点详情文字那组只改详情', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      await tester.tap(find.text('0.85×（小）').last);
      await tester.pump();

      expect(container.read(settingsProvider).onlineDetailTextScale, 0.85);
      expect(container.read(settingsProvider).onlineCardTextScale, 1.0);
    });

    testWidgets('点标签字号档位会写进设置（全局生效的那个值）', (tester) async {
      await pumpDialog(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(OnlineAppearanceDialog)));

      await tester.tap(find.text('14'));
      await tester.pump();

      expect(container.read(settingsProvider).tagFontSize, 14);
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
