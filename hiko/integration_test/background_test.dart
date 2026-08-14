import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

/// 后台播放验证：种数据 → 启动 → 播放 → 保持前台 60 秒。
/// 运行期间用 adb 检查：通知栏媒体通知 / dumpsys media_session 状态。
/// 运行：flutter test integration_test/background_test.dart -d <device> （后台跑）
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('播放并保持（验证后台播放与媒体通知）', (tester) async {
    final dir = await getApplicationSupportDirectory();
    final wav1 = await _createWav('${dir.path}/b01.wav', 440, 30);
    final wav2 = await _createWav('${dir.path}/b02.wav', 554.37, 30);
    final album = Album(
      id: 'local-bg',
      sourcePath: wav1.parent.path,
      title: '雨夜耳语',
      artist: '某社团',
      rjCode: 'RJ01000112',
      genre: 'ASMR',
      date: DateTime.now(),
      tracks: [
        Track(index: 0, name: '01 プロローグ', url: Uri.file(wav1.path).toString(), duration: 30),
        Track(index: 1, name: '02 本編', url: Uri.file(wav2.path).toString(), duration: 30),
      ],
    );
    await LibraryStore(overrideDir: dir).save([album]);

    app.main();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('雨夜耳语'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从头播放'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final playback = container.read(playbackProvider);
    debugPrint('[bg-test] playing=${playback.playing} position=${playback.position}');
    expect(playback.playing, isTrue);

    // 保持播放 60 秒（此期间外部用 adb 验证通知栏与后台播放）
    debugPrint('[bg-test] KEEPING PLAYBACK ALIVE 60s...');
    await tester.pump(const Duration(seconds: 60));
    expect(container.read(playbackProvider).playing, isTrue);
  });
}

Future<File> _createWav(String path, double frequency, int seconds) async {
  const sampleRate = 44100;
  final samples = sampleRate * seconds;
  final dataSize = samples * 2;
  final buffer = BytesBuilder()
    ..add(Uint8List.fromList([0x52, 0x49, 0x46, 0x46]))
    ..add(_le32(36 + dataSize))
    ..add(Uint8List.fromList([0x57, 0x41, 0x56, 0x45]))
    ..add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20]))
    ..add(_le32(16))
    ..add(_le16(1))
    ..add(_le16(1))
    ..add(_le32(sampleRate))
    ..add(_le32(sampleRate * 2))
    ..add(_le16(2))
    ..add(_le16(16))
    ..add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61]))
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
