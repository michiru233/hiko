import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/online_account.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/screens/online_screen.dart';
import 'package:hiko/ui/widgets/online_search_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在线页「点胶囊 → 放大浮层 → 提交」的端到端锁（1.99.70）。
void main() {
  testWidgets('折叠态整条可点；点开后可提交，面板自动收起', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: <Override>[
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
        onlineAccountProvider.overrideWith((ref) => OnlineAccountNotifier(ref)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(body: OnlineScreen(isMobile: true)),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // 真身 + 移动端离屏量高副本各一个；可见/可命中的只有真身
    expect(find.byType(M3ESearchEntry), findsOneWidget);
    expect(find.byType(M3ESearchEntry).hitTestable(), findsOneWidget);

    await tester.tap(find.byType(M3ESearchEntry));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(OnlineSearchOverlay), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('online-search-field')),
      'アリス',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(OnlineSearchOverlay), findsNothing);
    expect(container.read(onlineBrowseProvider).keyword, 'アリス');
  });
}
