import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_snapshots.dart';
import 'package:hiko/data/online/online_account.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 历史快照在设置里的入口（1.99.62）。
///
/// 用假的 `LibrarySnapshots` 只锁**跳转与空态**：真正的文件复制/淘汰/恢复
/// 在 `test/data/library_snapshots_test.dart` 里跑普通 test（真实 IO 放进
/// `testWidgets` 的 FakeAsync 会挂死）。
class _FakeSnapshots extends LibrarySnapshots {
  _FakeSnapshots(this.items);

  final List<LibrarySnapshot> items;
  final List<LibrarySnapshot> restored = <LibrarySnapshot>[];

  @override
  Future<List<LibrarySnapshot>> list() async => items;

  @override
  Future<LibrarySnapshot?> capture({
    String reason = 'auto',
    bool force = true,
  }) async =>
      null;

  @override
  Future<void> restore(LibrarySnapshot snapshot) async => restored.add(snapshot);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => <String, dynamic>{
            'appName': 'Hiko',
            'packageName': 'top.voicehub.hiko',
            'version': '1.99.62',
            'buildNumber': '175',
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

  Future<_FakeSnapshots> pumpSettings(
    WidgetTester tester, {
    List<LibrarySnapshot> items = const [],
  }) async {
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = _FakeSnapshots(items);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
        onlineAccountProvider.overrideWith((ref) => OnlineAccountNotifier(ref)),
        librarySnapshotsProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => M3ETheme(
            data: buildM3EThemeData(const AppSettings()),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await settle(tester);
    return fake;
  }

  testWidgets('数据与维护里有「历史快照」入口，点进去是空态', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('数据与维护'));
    await settle(tester);
    expect(find.text('历史快照'), findsOneWidget);

    await tester.tap(find.text('历史快照'));
    await settle(tester);

    expect(find.textContaining('还没有历史快照'), findsOneWidget);
    expect(find.text('立即留一份快照'), findsOneWidget);
    // 标题换成子页名，索引页的四组标签不在
    expect(find.text('历史快照'), findsOneWidget);
    expect(find.text('数据与维护'), findsNothing);
    expect(find.text('通用'), findsNothing);
  });

  testWidgets('快照为空时不渲染任何恢复行', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('数据与维护'));
    await settle(tester);
    await tester.tap(find.text('历史快照'));
    await settle(tester);

    expect(find.byType(M3EListItem), findsNothing);
  });
}
