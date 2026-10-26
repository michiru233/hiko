import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/online_account.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页的窄/中/宽三档回归锁（1.99.43）。
///
/// 这一版把设置页的 Material 控件全部换掉（开关 / 下拉 / 滑杆 / 按钮），
/// 字号按 M3E 字阶整体放大了一档（10.5 → `bodySmall` 12、11 → `labelSmall` 11、
/// 12.5 → `bodyMedium` 14）。**行是 72dp 的定高双行 + 右侧控件**，
/// 纵向放大最容易在 360dp × 1.3 字号下把右侧控件挤出屏幕。
///
/// 锁法：三档宽度各 pump 一次真 `SettingsPage`（窗口开得足够高，让 ListView
/// 把大部分行真的建出来），溢出会以 `FlutterError` 让 pump 直接失败。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // package_info_plus 在测试环境没有宿主实现；版本号只影响「关于」区的一行文字
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => <String, dynamic>{
            'appName': 'Hiko',
            'packageName': 'top.voicehub.hiko',
            'version': '1.99.43',
            'buildNumber': '156',
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

  Future<void> pumpSettings(
    WidgetTester tester, {
    required double width,
    double height = 3000,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, height);
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
          builder: (context, child) => M3ETheme(
            data: buildM3EThemeData(const AppSettings()),
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    // 首帧后有版本号 / 几个 FutureBuilder 落地
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('360dp：单列不溢出', (tester) async {
    await pumpSettings(tester, width: 360);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
  });

  testWidgets('360dp × 1.3 字号：不溢出', (tester) async {
    await pumpSettings(tester, width: 360, textScale: 1.3);
    expect(find.text('播放'), findsOneWidget);
  });

  testWidgets('480dp：不溢出', (tester) async {
    await pumpSettings(tester, width: 480);
    expect(find.text('库与扫描'), findsOneWidget);
  });

  testWidgets('720dp：不溢出', (tester) async {
    await pumpSettings(tester, width: 720);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
  });

  testWidgets('设置页不再出现 Material 交互控件', (tester) async {
    await pumpSettings(tester, width: 720, height: 6000);

    for (final finder in <Finder>[
      find.byType(Switch),
      find.byWidgetPredicate((w) => w is DropdownButton),
      find.byType(OutlinedButton),
      find.byType(TextButton),
      find.byType(FilledButton),
      find.byType(ElevatedButton),
      // IconButton 不列：TextField 的自带清除钮等内部实现会用，不属设置页控件
    ]) {
      expect(finder, findsNothing);
    }
    // M3ESlider 内部本来就包一个 Material Slider（只是换了 theme），
    // 所以「没有裸 Slider」= 两者数量严格相等。
    expect(
      find.byType(Slider).evaluate().length,
      find.byType(M3ESlider).evaluate().length,
    );
    // 换上的 M3E 控件确实在场（否则「没有 Material」可能只是因为整页没建出来）
    expect(find.byType(M3ESwitch), findsWidgets);
  });
}
