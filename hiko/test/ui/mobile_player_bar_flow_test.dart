import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/fullscreen_player_screen.dart';
import 'package:hiko/ui/screens/home_screen.dart';
import 'package:hiko/ui/widgets/mobile_bottom_nav.dart';
import 'package:hiko/ui/widgets/player_bar.dart';
import 'package:hiko/ui/widgets/sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「左划收起播放栏」在**主界面**这一层的接线（1.99.6）。
///
/// 只做移动端（裁决 Q10=A），而 widget 测试的宿主是 macOS ——
/// `Platform.isAndroid` 恒为 false，所以整页测试默认够不着移动布局。
/// 这里用 `HomeScreen(debugMobileLayout: true)` 这个测试缝把 isMobile 打开，
/// 锁四件事：
/// 1. 划掉 → 播放栏消失 **且** 调用 pause（裁决 Q1=B）；
/// 2. 划掉后「暂停 → 播放」的跳变把播放栏叫回来（裁决 Q8=A）；
/// 3. 划掉后底栏固定格「正在播放」仍然在（没有任何一次播放也能找回全屏播放页）；
/// 4. 左边缘起手落在播放栏上时不呼出抽屉（裁决 Q4=A，否则「想划播放栏却拉出侧栏」）。
class _FakePlayback extends PlaybackController {
  _FakePlayback(super._ref);

  int pauseCalls = 0;

  @override
  Future<void> pause() async {
    pauseCalls++;
    state = state.copyWith(playing: false);
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _FakePlayback playback;

  /// 起一个「正在播放」的移动端主界面。
  /// 画布 900×1400：macOS 宿主上播放栏会多一个桌面歌词按钮，窄了会溢出。
  Future<ProviderContainer> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final albums = [_album('rj000001'), _album('rj000002')];
    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(albums)),
        playbackProvider.overrideWith((ref) => _FakePlayback(ref)),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);
    playback = container.read(playbackProvider.notifier) as _FakePlayback;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: HomeScreen(debugMobileLayout: true),
        ),
      ),
    );
    // initState 里 500ms 的静默扫描要先走完（空目录即返，无 IO）
    await tester.pump(const Duration(milliseconds: 600));

    final album = albums.first;
    playback.state = PlaybackState(
      album: album,
      queue: album.tracks,
      queueIndex: 0,
      playing: true,
      position: 10,
      duration: 100,
    );
    await tester.pump();
    return container;
  }

  testWidgets('划掉播放栏 → 栏消失 + 暂停；下次开始播放 → 栏自己回来', (tester) async {
    await pumpHome(tester);
    expect(find.byType(PlayerBar), findsOneWidget, reason: '有正在播放的专辑就该显示');
    expect(find.byType(MobileBottomNav), findsOneWidget);

    final start = tester.getTopLeft(find.byType(PlayerBar)) + const Offset(30, 25);
    await tester.dragFrom(start, const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerBar), findsNothing, reason: '划掉即收起');
    expect(playback.pauseCalls, 1, reason: '划掉 = 收起 + 暂停（裁决 Q1=B）');
    expect(playback.state.playing, isFalse);

    // 底栏固定格仍在：划掉之后「一定找得回来」的兜底没有被破坏
    expect(find.text(MobileBottomNav.playerLabel), findsOneWidget);

    // 还原判据 = 任何一次「暂停 → 播放」的跳变（点歌/媒体键/耳机键都算）
    playback.state = playback.state.copyWith(playing: true);
    await tester.pump();
    expect(find.byType(PlayerBar), findsOneWidget, reason: '重新开始播放就该还原（裁决 Q8=A）');
  });

  testWidgets('划掉后底栏固定格「正在播放」可点（进全屏播放页不还原播放栏）', (tester) async {
    await pumpHome(tester);

    final start = tester.getTopLeft(find.byType(PlayerBar)) + const Offset(30, 25);
    await tester.dragFrom(start, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerBar), findsNothing);

    // 固定格此时可点（album != null），点击进全屏播放页
    await tester.tap(find.text(MobileBottomNav.playerLabel));
    // 全屏播放页的唱片是**无限旋转**动画（播放中不停），不能 pumpAndSettle
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(FullscreenPlayerScreen), findsOneWidget,
        reason: '固定格「正在播放」→ 全屏播放页（裁决 Q6=A）');
    // 裁决 Q9=A：进全屏播放页本身**不**还原播放栏
    expect(find.byType(PlayerBar), findsNothing);
  });

  testWidgets('起手落在播放栏左缘：呼出抽屉让位给播放栏（不拉出侧栏）', (tester) async {
    await pumpHome(tester);
    final rect = tester.getRect(find.byType(PlayerBar));

    // 左边缘 24px 内起手 + 横划 80px（远超呼出抽屉的 60px 阈值）
    await tester.dragFrom(Offset(4, rect.center.dy), const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(find.byType(Sidebar), findsNothing, reason: '裁决 Q4=A：播放栏上的手势优先');
    expect(find.byType(PlayerBar), findsOneWidget, reason: '80/900 未过收起阈值，栏还在');
  });

  testWidgets('起手落在播放栏以外（左缘上方）：抽屉照旧能呼出', (tester) async {
    await pumpHome(tester);
    final rect = tester.getRect(find.byType(PlayerBar));
    expect(rect.top, greaterThan(120), reason: '播放栏在底部，上方必有一块空白可控区');

    await tester.dragFrom(Offset(4, rect.top - 100), const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(find.byType(Sidebar), findsOneWidget, reason: '1.54 的左边缘呼出未被破坏');
  });
}
