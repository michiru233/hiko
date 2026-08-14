
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kikoeru/main.dart' as app;
import 'package:kikoeru/playback/playback_controller.dart';

/// macOS 端到端冒烟：真实应用 + 种子库（~/Library/Application Support/
/// top.voicehub.kikoeru/library.json，3 张专辑）验证 UI 交互与播放。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('网格渲染 → 打开详情 → 播放 → 进度推进', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 等待库加载完成（异步 load）
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 1. 网格应有 3 张卡片（标题可见）
    expect(find.text('雨夜耳语'), findsOneWidget);
    expect(find.text('深层音声'), findsOneWidget);
    expect(find.text('无RJ专辑'), findsOneWidget);

    // 2. 打开详情抽屉：点击第一张卡片
    await tester.tap(find.text('雨夜耳语'));
    await tester.pumpAndSettle();

    // 详情应显示：从头播放按钮、RJ 号、曲目
    expect(find.text('从头播放'), findsOneWidget);
    expect(find.textContaining('RJ01000112'), findsOneWidget);
    expect(find.text('01 プロローグ'), findsOneWidget);
    expect(find.text('02 本編'), findsOneWidget);

    // 3. 从头播放 → 播放状态应为 playing
    await tester.tap(find.text('从头播放'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    var playback = container.read(playbackProvider);
    debugPrint('[test] after play: album=${playback.album?.title} '
        'queueIndex=${playback.queueIndex} playing=${playback.playing} '
        'position=${playback.position} duration=${playback.duration}');
    expect(playback.album?.title, '雨夜耳语');
    expect(playback.queueIndex, 0);
    expect(playback.playing, isTrue);

    // 4. 进度推进（3 秒的 WAV，等待 1.5s 后位置应 > 0）
    await tester.pump(const Duration(milliseconds: 1500));
    playback = container.read(playbackProvider);
    debugPrint('[test] after wait: position=${playback.position} playing=${playback.playing}');
    expect(playback.position, greaterThan(0));

    // 5. 播放条应显示当前曲目
    expect(find.textContaining('01 プロローグ'), findsWidgets);

    // 6. 先暂停再下一首 → 队列推进到第 2 首（避免 3 秒 WAV 自然播完自动切曲的竞态）
    await container.read(playbackProvider.notifier).pause();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('▶▶'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(container.read(playbackProvider).queueIndex, 1);
  });
}
