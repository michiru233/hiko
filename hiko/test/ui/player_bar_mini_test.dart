import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/widgets/player_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 迷你播放栏契约（1.99.7 方案A，仅 compact / 移动端）：
/// 1. 单行布局在**手机宽度（360dp）**下不溢出；
/// 2. 进度降级为顶边细进度线（只显示），compact 里**没有滑杆**；
/// 3. 点文字区任意处 = 点封面，都回调 `onCoverTap` 进全屏页；
/// 4. 桌面端（compact: false）仍是双控件行 + 可拖滑杆，本版零改动。
class _FakePlayback extends PlaybackController {
  _FakePlayback(super._ref);
}

Album _album() => Album(
      id: 'rj000001',
      sourcePath: '/x/rj000001',
      title: 'とてもとても長いタイトルのテストアルバム名がここに入る',
      date: DateTime(2026),
      tracks: [Track(index: 0, name: 'トラック1', url: 'file:///x/1.mp3')],
    );

Future<void> pumpBar(
  WidgetTester tester, {
  required bool compact,
  required Size size,
  void Function(Album album)? onCoverTap,
}) async {
  tester.view.physicalSize = size;
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
  final album = _album();
  controller.state = PlaybackState(
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
              PlayerBar(compact: compact, onCoverTap: onCoverTap),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('360dp 宽：单行渲染无溢出，进度线显示 10/100=0.1，无滑杆', (tester) async {
    await pumpBar(tester, compact: true, size: const Size(360, 780));
    expect(tester.takeException(), isNull, reason: '窄屏单行不得溢出');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    // 首帧后注入进度再断言（控制器初始化时会把 position 归零）
    final container = tester.element(find.byType(PlayerBar));
    final controller = ProviderScope.containerOf(container)
        .read(playbackProvider.notifier) as _FakePlayback;
    controller.state = controller.state.copyWith(position: 10, duration: 100);
    await tester.pump();

    final line = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(line.value, closeTo(0.1, 0.001));
  });

  testWidgets('点文字区（封面右侧空白）→ 回调 onCoverTap', (tester) async {
    var taps = 0;
    await pumpBar(
      tester,
      compact: true,
      size: const Size(360, 780),
      onCoverTap: (_) => taps++,
    );

    // 元信息区在封面和控件按钮之间：从栏内左上往右约 90dp 处
    final rect = tester.getRect(find.byType(PlayerBar));
    await tester.tapAt(Offset(rect.left + 90, rect.top + 30));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('桌面端（compact: false）不受影响：仍有可拖进度滑杆', (tester) async {
    // 900 宽给足桌面按钮行（macOS 宿主还会多一个桌面歌词按钮）
    await pumpBar(tester, compact: false, size: const Size(900, 1000));
    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
