import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/main.dart' as app;
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:path_provider/path_provider.dart';

/// 端到端冒烟：先向应用数据目录种入测试库（含真实 WAV），再启动应用，
/// 验证 网格渲染 → 打开详情 → 播放 → 进度推进 → 切曲。
/// 运行：flutter test integration_test -d macos / -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('网格渲染 → 打开详情 → 播放 → 进度推进', (tester) async {
    // ---- 种数据：库 + WAV 文件（应用私有目录，跨平台可读）----
    final dir = await getApplicationSupportDirectory();
    final wav1 = await _createWav('${dir.path}/01.wav', 440, 10);
    final wav2 = await _createWav('${dir.path}/02.wav', 554.37, 10);
    final album = Album(
      id: 'local-e2e',
      sourcePath: wav1.parent.path,
      title: '雨夜耳语',
      artist: '某社团',
      rjCode: 'RJ01000112',
      tags: const ['ASMR', 'バイノーラル'],
      genre: 'ASMR',
      date: DateTime.now(),
      tracks: [
        Track(index: 0, name: '01 プロローグ', url: Uri.file(wav1.path).toString(), duration: 10),
        Track(index: 1, name: '02 本編', url: Uri.file(wav2.path).toString(), duration: 10),
      ],
    );
    await LibraryStore(overrideDir: dir).save([album]);

    // ---- 启动应用（main 内会 load 上面写入的库）----
    app.main();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 1. 网格应有专辑卡片
    expect(find.text('雨夜耳语'), findsOneWidget);

    // 2. 打开详情抽屉：点击卡片
    await tester.tap(find.text('雨夜耳语'));
    await tester.pumpAndSettle();

    // 详情应显示：从头播放按钮、RJ 号、曲目
    expect(find.text('从头播放'), findsOneWidget);
    expect(find.textContaining('RJ01000112'), findsOneWidget);
    expect(find.text('01 プロローグ'), findsWidgets);

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

    // 4. 进度推进（等待 1.5s 后位置应 > 0）
    await tester.pump(const Duration(milliseconds: 1500));
    playback = container.read(playbackProvider);
    debugPrint('[test] after wait: position=${playback.position} playing=${playback.playing}');
    expect(playback.position, greaterThan(0));

    // 5. 先暂停再下一首 → 队列推进到第 2 首（避免 3 秒 WAV 自然播完的竞态）
    await container.read(playbackProvider.notifier).pause();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('▶▶'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(container.read(playbackProvider).queueIndex, 1);

    // 6. 右键菜单：应在指针位置附近弹出（而非屏幕中央）
    // 关闭详情回到网格
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    // tester.tap 支持 buttons 参数：完整指针生命周期，可靠触发 onSecondaryTapDown
    await tester.tap(
      find.text('雨夜耳语'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('刮削 DLsite 标签'), findsOneWidget);
    expect(find.text('打开所在文件夹'), findsOneWidget);
    // 菜单第一项应靠近指针（不应在屏幕中央）
    final menuTopLeft = tester.getTopLeft(find.text('刮削 DLsite 标签'));
    final tapCenter = tester.getCenter(find.text('雨夜耳语'));
    debugPrint('[test] right-click at $tapCenter, menu top-left $menuTopLeft');
    expect((menuTopLeft - tapCenter).distance, lessThan(250));
    expect((menuTopLeft - tapCenter).distance, greaterThan(0));
    // 关闭菜单（点击角落）
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('刮削 DLsite 标签'), findsNothing);
  });
}

/// 生成 44.1kHz 16bit 单声道 WAV（带淡入淡出）
Future<File> _createWav(String path, double frequency, int seconds) async {
  const sampleRate = 44100;
  final samples = sampleRate * seconds;
  final dataSize = samples * 2;
  final buffer = BytesBuilder()
    ..add(Uint8List.fromList([0x52, 0x49, 0x46, 0x46])) // RIFF
    ..add(_le32(36 + dataSize))
    ..add(Uint8List.fromList([0x57, 0x41, 0x56, 0x45])) // WAVE
    ..add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20])) // "fmt "
    ..add(_le32(16))
    ..add(_le16(1)) // PCM
    ..add(_le16(1)) // mono
    ..add(_le32(sampleRate))
    ..add(_le32(sampleRate * 2))
    ..add(_le16(2))
    ..add(_le16(16))
    ..add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61])) // "data"
    ..add(_le32(dataSize));
  for (var i = 0; i < samples; i++) {
    final fade = min(1.0, min(i / 1200, (samples - i) / 1200));
    final sample = (7000 * fade * sin(2 * pi * frequency * i / sampleRate)).round();
    buffer.add(_le16(sample));
  }
  final file = File(path);
  await file.writeAsBytes(buffer.toBytes());
  return file;
}

Uint8List _le16(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
Uint8List _le32(int v) => Uint8List.fromList([
      v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF,
    ]);
