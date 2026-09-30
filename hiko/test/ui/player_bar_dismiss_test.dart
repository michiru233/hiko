import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/widgets/player_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「从左往右划掉播放栏」的手势契约（1.99.6，裁决 Q1=B / Q5=A / Q10=A）。
///
/// 这里锁的是 [PlayerBar] 自己那一层：
/// 1. 传了 `onDismiss` 才有 [Dismissible]（桌面端传 null，行为必须与旧版一模一样）；
/// 2. 跟手位移过阈值 → 回调一次；**从右往左**划不回调（只认 startToEnd）；
/// 3. 栏内三个滑杆**天然排除** —— 横划落在进度条上时滑杆赢下手势竞技场，
///    既不会收起播放栏，进度条也照常跟随（这是本功能最容易踩坏的地方）。
///
/// 用计数器版控制器（[_FakePlayback]）避免碰媒体通道；进度条拖动会真的调
/// `seek`，这里把调用数也记下来当作「拖拽确实到达了滑杆」的证据。
class _FakePlayback extends PlaybackController {
  // 只能走 super 参数：基类构造参数名是私有的 `_ref`，写不出 `super(ref)` 的简写
  _FakePlayback(super._ref);

  int pauseCalls = 0;
  int seekCalls = 0;

  @override
  Future<void> pause() async {
    pauseCalls++;
    state = state.copyWith(playing: false);
  }

  @override
  Future<void> seek(double seconds) async {
    seekCalls++;
    state = state.copyWith(position: seconds);
  }
}

Album _album() => Album(
      id: 'rj000001',
      sourcePath: '/x/rj000001',
      title: 'テストアルバム',
      date: DateTime(2026),
      tracks: [Track(index: 0, name: 'トラック1', url: 'file:///x/1.mp3')],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _FakePlayback playback;

  /// 把播放条挂在「和主界面一样」的位置（Column 底部）。
  ///
  /// 画布给 900×1000：测试宿主是 macOS，[PlayerBar] 会额外带上「桌面歌词」按钮
  /// （`Platform.isMacOS`），真机那种 400px 窄宽在测试宿主上会直接溢出报错。
  /// 划动阈值是**比例**（0.35 × 栏宽），所以放大画布不影响这里测的东西。
  Future<void> pumpBar(
    WidgetTester tester, {
    required VoidCallback? onDismiss,
  }) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        playbackProvider.overrideWith((ref) => _FakePlayback(ref)),
        settingsProvider.overrideWith((ref) => SettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playbackProvider.notifier);
    playback = controller as _FakePlayback;
    final album = _album();
    playback.state = PlaybackState(
      album: album,
      queue: album.tracks,
      queueIndex: 0,
      playing: true,
      position: 10,
      duration: 100,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Spacer(),
                PlayerBar(compact: true, onDismiss: onDismiss),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 栏内左上角的封面处（不是滑杆、不是按钮正中），从这里起手最干净
  Offset coverPoint(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PlayerBar)) + const Offset(30, 25);

  testWidgets('不传 onDismiss 时完全没有 Dismissible（桌面端行为不变）', (tester) async {
    await pumpBar(tester, onDismiss: null);
    expect(find.byType(PlayerBar), findsOneWidget);
    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('从左往右划过大半 → onDismiss 恰好回调一次', (tester) async {
    var dismissCalls = 0;
    await pumpBar(tester, onDismiss: () => dismissCalls++);
    expect(find.byType(Dismissible), findsOneWidget);

    await tester.dragFrom(coverPoint(tester), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(dismissCalls, 1, reason: '500/900 远过 0.35 阈值');
  });

  testWidgets('从左往右只划一点点（未过阈值）→ 不回调', (tester) async {
    var dismissCalls = 0;
    await pumpBar(tester, onDismiss: () => dismissCalls++);

    await tester.dragFrom(coverPoint(tester), const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(dismissCalls, 0, reason: '80/900 未过 0.35 阈值，应弹回');
    expect(find.byType(PlayerBar), findsOneWidget);
  });

  testWidgets('从右往左划（反方向）→ 不回调，方向锁死 startToEnd', (tester) async {
    var dismissCalls = 0;
    await pumpBar(tester, onDismiss: () => dismissCalls++);

    // 起手点取栏内右上角（顶行尾部按钮区，横划同样由 drag 识别器接管）
    final rect = tester.getRect(find.byType(PlayerBar));
    await tester.dragFrom(
      Offset(rect.right - 150, rect.top + 25),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(dismissCalls, 0);
  });

  testWidgets('横划落在进度条上 → 进度条赢，播放栏不收起', (tester) async {
    var dismissCalls = 0;
    await pumpBar(tester, onDismiss: () => dismissCalls++);

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget, reason: 'compact 布局只有进度条一个滑杆');

    await tester.dragFrom(tester.getCenter(slider), const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(playback.seekCalls, greaterThan(0),
        reason: '拖拽确实落在滑杆上（否则这条测试是空过的）');
    expect(dismissCalls, 0, reason: '滑杆在竞技场里更内层，横划不该被播放栏吃掉');
  });
}
