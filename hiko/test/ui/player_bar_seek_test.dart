import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/widgets/player_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放条三段式契约（1.99.59，裁决 = 方案 B）：
/// 1. 桌面端（`compact: false`）= 封面 + 220dp 标题区 + 时间码/可拖进度条 + 控制键；
///    底部 2dp 非交互细线（`M3EProgress` → `LinearProgressIndicator`）在桌面端消失；
/// 2. 点按进度条某处 → 按比例 seek 一次；拖动过程**不** seek，松手才落一次；
/// 3. 未播放（`album == null` / `duration == 0`）时进度条禁用、时间码 00:00；
/// 4. 窄桌面窗口（720dp）也不溢出。
///
/// seek 走 `FakePlayback.seek` 覆写：不碰 just_audio / 断点落盘 / libraryProvider，
/// 只验证「像素比例 → 秒数」这条换算。
/// 只覆写 seek 的假控制器（public：pumpBar 的返回类型要用到它）。
class FakePlayback extends PlaybackController {
  FakePlayback(super._ref);

  final List<double> seeks = <double>[];

  @override
  Future<void> seek(double seconds) async {
    seeks.add(seconds);
    state = state.copyWith(position: seconds);
  }
}

Album _album() => Album(
      id: 'rj000001',
      sourcePath: '/x/rj000001',
      title: 'とてもとても長いタイトルのテストアルバム名がここに入る',
      date: DateTime(2026),
      tracks: [Track(index: 0, name: 'トラック1', url: 'file:///x/1.mp3')],
    );

const double _duration = 100;

Future<FakePlayback> pumpBar(
  WidgetTester tester, {
  required Size size,
  bool withAlbum = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      playbackProvider.overrideWith((ref) => FakePlayback(ref)),
      settingsProvider.overrideWith((ref) => SettingsNotifier()),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(playbackProvider.notifier) as FakePlayback;
  final album = withAlbum ? _album() : null;
  controller.state = PlaybackState(
    album: album,
    queue: album?.tracks ?? const [],
    queueIndex: 0,
    playing: album != null,
    position: withAlbum ? 10 : 0,
    duration: withAlbum ? _duration : 0,
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Spacer(),
              PlayerBar(compact: false),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // 控制器初始化会把 position 归零（同 player_bar_mini_test），首帧后再注入一次
  controller.state = controller.state.copyWith(
    position: withAlbum ? 10 : 0,
    duration: withAlbum ? _duration : 0,
  );
  await tester.pump();
  return controller;
}

Rect seekRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('player-bar-seek')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('桌面端三段式：时间码 + 可拖进度条在场，底部细线消失', (tester) async {
    await pumpBar(tester, size: const Size(1200, 600));
    expect(tester.takeException(), isNull);

    expect(find.byKey(const ValueKey('player-bar-seek')), findsOneWidget);
    expect(find.text('0:10'), findsOneWidget, reason: '已播时间码');
    expect(find.text('1:40'), findsOneWidget, reason: '总时长（100s）');
    expect(
      find.byType(LinearProgressIndicator),
      findsNothing,
      reason: '桌面端不再有 2dp 细线，进度只在中间那条轨上',
    );
  });

  testWidgets('点进度条 3/4 处 → seek 到 75s', (tester) async {
    final controller = await pumpBar(tester, size: const Size(1200, 600));
    final rect = seekRect(tester);

    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump();

    expect(controller.seeks.length, 1);
    expect(controller.seeks.single, closeTo(75, 1.5));
  });

  testWidgets('拖动过程不 seek，松手才落一次（占比换算按起点到松手点）', (tester) async {
    final controller = await pumpBar(tester, size: const Size(1200, 600));
    final rect = seekRect(tester);
    final startX = rect.left + rect.width * 0.2;

    final gesture = await tester.startGesture(Offset(startX, rect.center.dy));
    await gesture.moveTo(Offset(rect.left + rect.width * 0.6, rect.center.dy));
    await tester.pump();

    expect(controller.seeks, isEmpty, reason: '拖动中只改本地预览，不惊动播放器');

    await gesture.up();
    await tester.pump();

    expect(controller.seeks.length, 1, reason: '松手落一次');
    expect(controller.seeks.single, closeTo(60, 1.5));
  });

  testWidgets('未播放：进度条禁用、时间码双 00:00、点它不 seek', (tester) async {
    final controller = await pumpBar(
      tester,
      size: const Size(1200, 600),
      withAlbum: false,
    );
    final rect = seekRect(tester);

    expect(find.text('0:00'), findsNWidgets(2));
    await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
    await tester.pump();

    expect(controller.seeks, isEmpty, reason: '没有时长就没有可 seek 的目标');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄桌面窗口（720dp）三段式不溢出', (tester) async {
    await pumpBar(tester, size: const Size(720, 600));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('player-bar-seek')), findsOneWidget);
  });
}
